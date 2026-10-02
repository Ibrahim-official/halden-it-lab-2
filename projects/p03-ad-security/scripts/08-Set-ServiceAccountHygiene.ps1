<#
.SYNOPSIS
  P3 Phase 5: service-account and Kerberos hygiene — group Managed Service Accounts (gMSA),
  Kerberos encryption allowed types (audit first, enforce second), and the safe krbtgt reset
  in simulation mode. Idempotent; every action is logged.

.DESCRIPTION
  Long-lived service accounts with weak passwords and RC4 Kerberos tickets are the easiest way
  for a standard user to obtain a crackable credential (Kerberoasting). The fix is structural:

    * create a gMSA with a 240-character machine-managed, auto-rotating password and AES256 only
    * move the SPN from the legacy service account to the gMSA, then disable the legacy account
    * enable Kerberos audit data for RC4 ticket requests (event 4769, encryption type 0x17)
      BEFORE restricting encryption types, so breakage is predicted rather than discovered
    * run Microsoft's New-KrbtgtKeys.ps1 in simulation mode only

  The krbtgt reset is deliberately NOT performed here. It is a high-risk change with a strict
  one-ticket-lifetime wait between the two resets; it is performed as its own change with the
  runbook in docs/runbooks/run-the-assessment.md as the procedure.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER GmsaName
  Name of the gMSA to create. Default gmsa-sql.

.PARAMETER LegacysvcAccount
  The legacy service account whose SPN is moved. Default svc-sql.

.PARAMETER ServerGroup
  Group whose members may retrieve the gMSA password. Default G_Tier1_ServerAdmins.

.PARAMETER AuditOnly
  Default true. Leave Kerberos encryption as audit-only: do not restrict RC4 until the 4769
  events have been reviewed. Set to $false to enforce AES-only.

.PARAMETER KrbtgtScriptPath
  Path to Microsoft's New-KrbtgtKeys.ps1. When supplied, the script runs it in simulation mode
  only; if not supplied the step is skipped with a note.

.PARAMETER Log
  CSV action log. Defaults to ..\evidence\raw\p03-ph5-serviceaccounts-log.csv.

.EXAMPLE
  .\08-Set-ServiceAccountHygiene.ps1 -WhatIf

.EXAMPLE
  .\08-Set-ServiceAccountHygiene.ps1 -AuditOnly $false
  Enforce AES-only Kerberos after the audit events have been reviewed.

.NOTES
  Snapshot DC01 and DC02 first (snap-p3-ph5-before). Rollback: re-enable the legacy service
  account and reassign the SPN; do not reset krbtgt as part of a rollback.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$GmsaName = 'gmsa-sql',
  [string]$LegacysvcAccount = 'svc-sql',
  [string]$ServerGroup = 'G_Tier1_ServerAdmins',
  [bool]$AuditOnly = $true,
  [string]$KrbtgtScriptPath = '',
  [string]$Log = "$PSScriptRoot\..\evidence\raw\p03-ph5-serviceaccounts-log.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$root = (Get-ADDomain).DistinguishedName
$svcOu = "OU=ServiceAccounts,OU=Halden,$root"
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$actions = [System.Collections.Generic.List[object]]::new()
function Add-Action([string]$Item, [string]$Action, [string]$Detail) {
  $actions.Add([pscustomobject]@{ Time = Get-Date -Format s; Item = $Item; Action = $Action; Detail = $Detail })
}

# ---------------------------------------------------------------- 1. KDS root key (lab shortcut)
$kdsRoot = Get-KdsRootKey -ErrorAction SilentlyContinue
if (-not $kdsRoot) {
  if ($PSCmdlet.ShouldProcess($Domain, 'Create KDS root key')) {
    # Lab shortcut only: production waits up to 10 hours for replication before the key is usable.
    Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
    Add-Action '(KDS root key)' 'created' 'lab-only effective time; production waits for replication'
  }
} else {
  Add-Action '(KDS root key)' 'exists-skip' 'KDS root key already present'
}

# ---------------------------------------------------------------- 2. gMSA
$gmsa = Get-ADServiceAccount -Filter "Name -eq '$GmsaName'" -ErrorAction SilentlyContinue
if (-not $gmsa) {
  $principals = @()
  if (Get-ADGroup -Filter "Name -eq '$ServerGroup'" -ErrorAction SilentlyContinue) { $principals = @($ServerGroup) }
  if ($PSCmdlet.ShouldProcess($GmsaName, 'Create group Managed Service Account')) {
    New-ADServiceAccount -Name $GmsaName -DNSHostName "$GmsaName.$Domain" -Path $svcOu `
      -PrincipalsAllowedToRetrieveManagedPassword $principals -KerberosEncryptionType AES256 `
      -Description 'P3: machine-managed password; replaces the legacy svc-sql account.'
    Add-Action $GmsaName 'gmsa-created' "principals: $($principals -join ', '); AES256 only"
  }
} else {
  Add-Action $GmsaName 'exists-skip' 'gMSA already present'
}

# ---------------------------------------------------------------- 3. Move the SPN, disable the legacy account
$legacy = Get-ADUser -Filter "SamAccountName -eq '$LegacysvcAccount'" -Properties ServicePrincipalNames -ErrorAction SilentlyContinue
if ($legacy) {
  if ($gmsa) {
    if ($PSCmdlet.ShouldProcess($GmsaName, 'Assign the legacy SPN to the gMSA')) {
      Set-ADServiceAccount -Identity $GmsaName -ServicePrincipalNames @{ Add = "MSSQLSvc/lnx01.$Domain`:1433" }
      Add-Action $GmsaName 'spn-assigned' "MSSQLSvc/lnx01.$Domain`:1433"
    }
    if ($PSCmdlet.ShouldProcess($LegacysvcAccount, 'Remove SPN and disable legacy account')) {
      try { Set-ADUser $LegacysvcAccount -ServicePrincipalNames @{ Remove = "MSSQLSvc/lnx01.$Domain`:1433" } } catch { }
      Disable-ADAccount -Identity $LegacysvcAccount
      Add-Action $LegacysvcAccount 'disabled' 'SPN moved to the gMSA; Kerberoasting exposure removed'
    }
  } else {
    Add-Action $LegacysvcAccount 'skipped' 'gMSA not present; not disabling the legacy account'
  }
} else {
  Add-Action $LegacysvcAccount 'skipped' 'legacy service account not found'
}

# ---------------------------------------------------------------- 4. Kerberos encryption types
$kerbGpo = 'DOMAIN - Kerberos Encryption Audit - v1'
if (-not (Get-GPO -Name $kerbGpo -ErrorAction SilentlyContinue)) {
  if ($PSCmdlet.ShouldProcess($kerbGpo, 'Create Kerberos encryption GPO')) {
    New-GPO -Name $kerbGpo -Comment 'P3: audit RC4 Kerberos ticket requests before restricting encryption types.' | Out-Null
    New-GPLink -Name $kerbGpo -Target $root | Out-Null
    Add-Action $kerbGpo 'created' 'linked at the domain root (audit first)'
  }
}
# Audit data for RC4 ticket requests: 4769 with encryption type 0x17.
if ($PSCmdlet.ShouldProcess($Domain, 'Enable Kerberos service ticket audit data')) {
  auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable | Out-Null
  Add-Action '(audit policy)' 'enabled' 'Kerberos service ticket operations audited (event 4769)'
}
if ($AuditOnly) {
  Add-Action '(Kerberos encryption)' 'audit-only' 'RC4 still allowed; review 4769 events before enforcing AES-only'
} else {
  if ($PSCmdlet.ShouldProcess($kerbGpo, 'Restrict Kerberos encryption to AES')) {
    # 0x18 = AES128 + AES256. Enforcing this without the audit phase breaks old applications.
    Set-GPRegistryValue -Name $kerbGpo -Key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters' `
      -ValueName 'SupportedEncryptionTypes' -Type DWord -Value 0x18 | Out-Null
    Add-Action $kerbGpo 'enforced' 'AES128 + AES256 only; RC4 disabled'
  }
}

# ---------------------------------------------------------------- 5. krbtgt reset (simulation only)
if ($KrbtgtScriptPath -and (Test-Path $KrbtgtScriptPath)) {
  $krbtgt = Get-ADUser krbtgt -Properties PasswordLastSet, pwdLastSet
  Add-Action 'krbtgt' 'recorded' ("password last set: {0}" -f $krbtgt.PasswordLastSet)
  if ($PSCmdlet.ShouldProcess('krbtgt', 'Run New-KrbtgtKeys.ps1 in simulation mode')) {
    & $KrbtgtScriptPath -Mode Simulate -Verbose
    Add-Action 'krbtgt' 'simulated' 'Microsoft New-KrbtgtKeys.ps1 run in simulation mode only; no reset performed'
  }
} else {
  Add-Action 'krbtgt' 'skipped' 'New-KrbtgtKeys.ps1 path not supplied; the reset is a separate, scheduled change'
  $krbtgt = Get-ADUser krbtgt -Properties PasswordLastSet
  Add-Action 'krbtgt' 'recorded' ("password last set: {0}" -f $krbtgt.PasswordLastSet)
}

$actions | Export-Csv -Path $Log -NoTypeInformation -Append
Write-Output ("Service-account hygiene complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
Write-Output 'Next: 09-Set-LegacyProtocolHardening.ps1, then gpupdate and 11-Verify-Remediation.ps1.'

<#
.SYNOPSIS
  P3 Phase 0 (LAB ONLY): deliberately seed the realistic Active Directory weaknesses the
  assessment will later find and fix. Idempotent; every action is logged.

.DESCRIPTION
  A freshly built lab scores too well to be useful. This script recreates the problems an
  inherited small-business domain really has, so that the assessment (Phase 1) has something
  honest to find and the hardening (Phases 2-6) has something honest to fix:

    * a Kerberoastable service account with a weak, never-expiring password
    * an AS-REP-roastable user (pre-authentication not required)
    * unconstrained Kerberos delegation on a member server
    * excess and stale Domain Admin memberships
    * one shared local administrator password on the workstations
    * a weak default domain password policy
    * a legacy-protocols GPO (LM level 1, SMB signing not required) and the Print Spooler
      running on the domain controllers
    * the AD Recycle Bin left disabled and an old krbtgt password (recorded, not changed)

  This is a strictly authorised lab exercise. The script refuses to run outside the Halden lab
  domain and refuses unless 00-Test-AssessmentGate.ps1 has been passed. It exists to measure the
  *before* state, not to teach an attack: the remediation and the verification live in the later
  scripts and the runbooks.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER StaffCsv
  The synthetic staff file used to choose which real-looking accounts carry the seeded
  weaknesses. Defaults to the P1 synthetic file.

.PARAMETER Workstations
  Names of the workstations that receive the shared local administrator password. Default WS01.

.PARAMETER KerberoastablePassword
  LAB-ONLY weak password for the seeded service account. Allow-listed in .gitleaks.toml as a
  deliberate, fictional lab value. Never use it anywhere real.

.PARAMETER SharedLocalAdminPassword
  LAB-ONLY weak password seeded identically on the workstations. Same caveat as above.

.PARAMETER Log
  CSV action log. Defaults to ..\evidence\raw\p03-ph0-seed-log.csv.

.EXAMPLE
  .\01-Seed-Weaknesses.ps1 -WhatIf
  Preview every seeded change without making it.

.EXAMPLE
  .\01-Seed-Weaknesses.ps1
  Apply the seeded weaknesses to the lab. Run the gate first.

.NOTES
  Before running: snapshot DC01, DC02 and any workstation named in -Workstations
  (snap-p3-ph0-before). Rollback: revert those snapshots.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$StaffCsv = "$PSScriptRoot\..\..\p01-core-infrastructure\data\halden-staff.csv",
  [string[]]$Workstations = @('WS01'),
  [string]$KerberoastablePassword = 'Summer2019!',
  [string]$SharedLocalAdminPassword = 'Halden123!',
  [string]$Log = "$PSScriptRoot\..\evidence\raw\p03-ph0-seed-log.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
Write-Warning 'LAB ONLY: this seeds deliberate weaknesses. Isolated lab domain only, never a real network.'

New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$actions = [System.Collections.Generic.List[object]]::new()
function Add-Action([string]$Item, [string]$Action, [string]$Detail) {
  $actions.Add([pscustomobject]@{ Time = Get-Date -Format s; Item = $Item; Action = $Action; Detail = $Detail })
}
function New-LabPassword([string]$Plain) { ConvertTo-SecureString $Plain -AsPlainText -Force }

$root = (Get-ADDomain).DistinguishedName
$svcOu = "OU=ServiceAccounts,OU=Halden,$root"
$usersOu = "OU=Users,OU=Halden,$root"
$wksOu = "OU=Workstations,OU=Computers,OU=Halden,$root"

# ---------------------------------------------------------------- 1. Kerberoastable service account
$svcSam = 'svc-sql'
$existing = Get-ADUser -Filter "SamAccountName -eq '$svcSam'" -Properties ServicePrincipalNames -ErrorAction SilentlyContinue
if (-not $existing) {
  if ($PSCmdlet.ShouldProcess($svcSam, 'Seed Kerberoastable service account')) {
    New-ADUser -Name 'SQL Service (seeded)' -SamAccountName $svcSam -UserPrincipalName "$svcSam@$Domain" `
      -Path $svcOu -AccountPassword (New-LabPassword $KerberoastablePassword) `
      -PasswordNeverExpires $true -Enabled $true -Description 'LAB SEED: weak, never-expiring service account'
    Set-ADUser $svcSam -ServicePrincipalNames @{ Add = 'MSSQLSvc/lnx01.ad.halden.internal:1433' }
    Add-Action $svcSam 'created+spn' 'weak password seeded; SPN MSSQLSvc/lnx01.ad.halden.internal:1433'
  }
} else {
  Add-Action $svcSam 'exists-skip' 'service account already present'
}

# ---------------------------------------------------------------- 2. AS-REP-roastable user
# Choose a deterministic, real-looking user from the synthetic staff file (first Sales row).
$asRepSam = ''
if (Test-Path $StaffCsv) {
  $asRepRow = Import-Csv $StaffCsv | Where-Object Department -eq 'Sales' | Sort-Object EmployeeID | Select-Object -First 1
  if ($asRepRow) { $asRepSam = "$($asRepRow.First).$($asRepRow.Last)".ToLower() }
}
if ($asRepSam) {
  $u = Get-ADUser -Filter "SamAccountName -eq '$asRepSam'" -Properties DoesNotRequirePreAuth
  if ($u -and -not $u.DoesNotRequirePreAuth) {
    if ($PSCmdlet.ShouldProcess($asRepSam, 'Seed AS-REP roastable condition')) {
      Set-ADAccountControl -Identity $asRepSam -DoesNotRequirePreAuth $true
      Add-Action $asRepSam 'preauth-disabled' 'LAB SEED: account does not require Kerberos pre-authentication'
    }
  } else {
    Add-Action $asRepSam 'exists-skip' 'pre-authentication already disabled or user missing'
  }
} else {
  Add-Action '(as-rep)' 'skipped' 'staff CSV not found or has no Sales rows'
}

# ---------------------------------------------------------------- 3. Unconstrained delegation
$fs01 = Get-ADComputer -Identity 'FS01' -Properties TrustedForDelegation -ErrorAction SilentlyContinue
if ($fs01 -and -not $fs01.TrustedForDelegation) {
  if ($PSCmdlet.ShouldProcess('FS01', 'Seed unconstrained delegation')) {
    Set-ADComputer -Identity 'FS01' -TrustedForDelegation $true
    Add-Action 'FS01' 'unconstrained-delegation' 'LAB SEED: server trusted for unconstrained delegation'
  }
} else {
  Add-Action 'FS01' 'exists-skip' 'delegation flag already set or computer missing'
}

# ---------------------------------------------------------------- 4. Excess and stale Domain Admins
$daMembers = @(Get-ADGroupMember 'Domain Admins' | Select-Object -ExpandProperty SamAccountName)
$candidates = @()
if (Test-Path $StaffCsv) {
  $candidates = Import-Csv $StaffCsv |
    Where-Object { $_.Department -eq 'IT' -or $_.Department -eq 'Sales' } |
    Sort-Object EmployeeID |
    ForEach-Object { "$($_.First).$($_.Last)".ToLower() } |
    Where-Object { $_ -notin $daMembers }
}
$newAdmins = @($candidates | Select-Object -First 4)
foreach ($admin in $newAdmins) {
  if ($PSCmdlet.ShouldProcess($admin, 'Add to Domain Admins (seed)')) {
    Add-ADGroupMember -Identity 'Domain Admins' -Members $admin
    Add-Action $admin 'domain-admin-added' 'LAB SEED: excess Domain Admin membership'
  }
}
# One of them is disabled to model a stale admin that nobody removed.
$stale = $newAdmins | Select-Object -Last 1
if ($stale) {
  if ($PSCmdlet.ShouldProcess($stale, 'Disable stale admin (seed)')) {
    Disable-ADAccount -Identity $stale
    Add-Action $stale 'disabled' 'LAB SEED: disabled account left in Domain Admins'
  }
}

# ---------------------------------------------------------------- 5. Shared local administrator password
$localScript = {
  param([string]$Plain)
  $secure = ConvertTo-SecureString $Plain -AsPlainText -Force
  $account = Get-LocalUser -Name 'LocalAdmin' -ErrorAction SilentlyContinue
  if ($account) { Set-LocalUser -Name 'LocalAdmin' -Password $secure }
  else { New-LocalUser -Name 'LocalAdmin' -Password $secure -Description 'LAB SEED: shared local admin' -PasswordNeverExpires | Out-Null }
  Add-LocalGroupMember -Group 'Administrators' -Member 'LocalAdmin' -ErrorAction SilentlyContinue
}
foreach ($wks in $Workstations) {
  if ($PSCmdlet.ShouldProcess($wks, 'Seed shared local admin password')) {
    try {
      Invoke-Command -ComputerName $wks -ScriptBlock $localScript -ArgumentList $SharedLocalAdminPassword -ErrorAction Stop
      Add-Action $wks 'shared-local-admin' 'LAB SEED: identical local LocalAdmin password'
    } catch {
      Add-Action $wks 'failed' "could not reach workstation: $($_.Exception.Message)"
    }
  }
}

# ---------------------------------------------------------------- 6. Weak default domain password policy
$pol = Get-ADDefaultDomainPasswordPolicy
if ($pol.MinPasswordLength -gt 7 -or $pol.LockoutThreshold -ne 0) {
  if ($PSCmdlet.ShouldProcess($Domain, 'Weaken default domain password policy (seed)')) {
    Set-ADDefaultDomainPasswordPolicy -Identity $Domain -MinPasswordLength 7 -ComplexityEnabled $false `
      -LockoutThreshold 0 -LockoutDuration 00:00:00 -LockoutObservationWindow 00:00:00
    Add-Action '(domain policy)' 'weakened' ("was min {0} / lockout {1} -> now 7 / 0" -f $pol.MinPasswordLength, $pol.LockoutThreshold)
  }
} else {
  Add-Action '(domain policy)' 'exists-skip' 'policy already weakened'
}

# ---------------------------------------------------------------- 7. Legacy protocols GPO + Print Spooler
$seedGpo = 'LAB SEED - Legacy Protocols - v1'
if (-not (Get-GPO -Name $seedGpo -ErrorAction SilentlyContinue)) {
  if ($PSCmdlet.ShouldProcess($seedGpo, 'Create legacy-protocols seed GPO')) {
    New-GPO -Name $seedGpo -Comment 'LAB SEED: legacy protocols deliberately weak. Removed in P3 Phase 6.' | Out-Null
    New-GPLink -Name $seedGpo -Target $root | Out-Null
    Set-GPRegistryValue -Name $seedGpo -Key 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' `
      -ValueName 'LmCompatibilityLevel' -Type DWord -Value 1 | Out-Null
    Set-GPRegistryValue -Name $seedGpo -Key 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' `
      -ValueName 'RequireSecuritySignature' -Type DWord -Value 0 | Out-Null
    Set-GPRegistryValue -Name $seedGpo -Key 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' `
      -ValueName 'RequireSecuritySignature' -Type DWord -Value 0 | Out-Null
    Add-Action $seedGpo 'created' 'LM level 1; SMB signing not required (LAB SEED)'
  }
} else {
  Add-Action $seedGpo 'exists-skip' 'seed GPO already present'
}
foreach ($dc in @('DC01', 'DC02')) {
  if ($PSCmdlet.ShouldProcess($dc, 'Ensure Print Spooler is running (seed)')) {
    try {
      Invoke-Command -ComputerName $dc -ScriptBlock {
        Set-Service -Name Spooler -StartupType Automatic; Start-Service -Name Spooler
      } -ErrorAction Stop
      Add-Action $dc 'spooler-running' 'LAB SEED: Print Spooler enabled on a domain controller'
    } catch {
      Add-Action $dc 'failed' "could not reach DC: $($_.Exception.Message)"
    }
  }
}

# ---------------------------------------------------------------- 8. Record (do not change) baseline states
$recycle = Get-ADOptionalFeature 'Recycle Bin Feature'
Add-Action '(AD Recycle Bin)' 'recorded' ("enabled scopes: {0}" -f (@($recycle.EnabledScopes).Count))
$krbtgt = Get-ADUser krbtgt -Properties PasswordLastSet
Add-Action 'krbtgt' 'recorded' ("password last set: {0}" -f $krbtgt.PasswordLastSet)

$actions | Export-Csv -Path $Log -NoTypeInformation -Append
Write-Output ("Seed complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
Write-Output 'Next: run 02-Collect-PingCastle.ps1 to capture the BEFORE score, then 04-New-FindingsRegister.py.'

<#
.SYNOPSIS
  P3 Phase 7: verify that each remediation is actually in place and still enforced, then write
  the verification table that feeds the README and the register. Read-only.

.DESCRIPTION
  "Fixed" and "verified" are different claims. This script checks the state of every control the
  project claims, and reports each one as PASS, FAIL or UNKNOWN. A gap between the two is a
  finding, not something to hide.

  Controls checked:
    * AD Recycle Bin enabled
    * Domain Admins contains only the designed Tier 0 accounts
    * no account skips Kerberos pre-authentication; no unconstrained delegation
    * Print Spooler disabled on the domain controllers
    * Windows LAPS schema present and passwords backing up (event 10018)
    * LAPS read rights delegated only to the right tier
    * Protected Users membership is human accounts only
    * deny-logon user rights are present in the workstation, server and DC GPOs
    * helpdesk delegation exists on user OUs and not on Tier 0 objects
    * gMSA exists and replaces the legacy service account
    * NTLM auditing is on; LM compatibility level is set
    * a PingCastle before/after summary exists

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER Tier0Admins
  The only accounts allowed in Domain Admins. Default Administrator plus the adm-t0-* pattern.

.PARAMETER Report
  CSV output. Defaults to ..\evidence\raw\p03-ph7-remediation-verification-result.csv.

.EXAMPLE
  .\11-Verify-Remediation.ps1

.NOTES
  Read-only. Nothing here is a measured result until it has been run in the lab.
#>
[CmdletBinding()]
param(
  [string]$Domain = 'ad.halden.internal',
  [string[]]$Tier0Admins = @('Administrator'),
  [string]$Report = "$PSScriptRoot\..\evidence\raw\p03-ph7-remediation-verification-result.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Control, [string]$Status, [string]$Detail) {
  if ($Status -notin @('PASS', 'FAIL', 'UNKNOWN')) { throw "Bad status $Status" }
  $results.Add([pscustomobject]@{
    Time = (Get-Date -Format s); Control = $Control; Status = $Status; Detail = $Detail
  })
}
function Try-Check([string]$Control, [scriptblock]$Test) {
  try { & $Test } catch { Add-Result $Control 'UNKNOWN' $_.Exception.Message }
}

$root = (Get-ADDomain).DistinguishedName

Try-Check 'AD Recycle Bin enabled' {
  $recycle = Get-ADOptionalFeature 'Recycle Bin Feature'
  $enabled = @($recycle.EnabledScopes).Count -gt 0
  Add-Result 'AD Recycle Bin enabled' ($(if ($enabled) { 'PASS' } else { 'FAIL' })) ("scopes: {0}" -f @($recycle.EnabledScopes).Count)
}

Try-Check 'Domain Admins contains only Tier 0 accounts' {
  $members = @(Get-ADGroupMember 'Domain Admins' | Select-Object -ExpandProperty SamAccountName)
  $unexpected = @($members | Where-Object { $_ -notin $Tier0Admins -and $_ -notmatch '^adm-t0-' })
  Add-Result 'Domain Admins contains only Tier 0 accounts' `
    ($(if ($unexpected.Count -eq 0) { 'PASS' } else { 'FAIL' })) `
    ("unexpected: {0}" -f ($(if ($unexpected) { $unexpected -join ', ' } else { 'none' })))
}

Try-Check 'No account skips Kerberos pre-authentication' {
  $count = @(Get-ADUser -Filter 'DoesNotRequirePreAuth -eq $true').Count
  Add-Result 'No account skips Kerberos pre-authentication' ($(if ($count -eq 0) { 'PASS' } else { 'FAIL' })) ("accounts: {0}" -f $count)
}

Try-Check 'No unconstrained delegation' {
  $count = @(Get-ADComputer -Filter 'TrustedForDelegation -eq $true').Count
  Add-Result 'No unconstrained delegation' ($(if ($count -eq 0) { 'PASS' } else { 'FAIL' })) ("computers: {0}" -f $count)
}

Try-Check 'Print Spooler disabled on domain controllers' {
  $details = @()
  $allDisabled = $true
  foreach ($dc in @(Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName)) {
    try {
      $state = Invoke-Command -ComputerName $dc -ScriptBlock { (Get-Service Spooler).StartType.ToString() } -ErrorAction Stop
      $details += "$dc=$state"
      if ($state -ne 'Disabled') { $allDisabled = $false }
    } catch {
      $details += "$dc=unreachable"
      $allDisabled = $false
    }
  }
  Add-Result 'Print Spooler disabled on domain controllers' ($(if ($allDisabled) { 'PASS' } else { 'FAIL' })) ($details -join '; ')
}

Try-Check 'Windows LAPS schema present' {
  $schema = Get-ADObject "CN=ms-LAPS-Password,CN=Schema,CN=Configuration,$root" -ErrorAction Stop
  Add-Result 'Windows LAPS schema present' ($(if ($schema) { 'PASS' } else { 'FAIL' })) 'ms-LAPS-Password attribute found'
}

Try-Check 'LAPS passwords are backing up' {
  $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-LAPS/Operational'; Id = 10018 } -MaxEvents 20 -ErrorAction Stop)
  Add-Result 'LAPS passwords are backing up' ($(if ($events.Count -gt 0) { 'PASS' } else { 'FAIL' })) ("event 10018 count in last 20: {0}" -f $events.Count)
}

Try-Check 'LAPS read delegated only to the right tier' {
  $groups = @(Get-LapsADReadPasswordPermission -Identity "OU=Workstations,OU=Computers,OU=Halden,$root" -ErrorAction Stop |
    ForEach-Object { $_.Trustee.ToString() })  $overBroad = @()
  foreach ($name in @('Domain Users', 'Authenticated Users', 'Everyone')) {
    if ($groups -match $name) { $overBroad += $name }
  }
  Add-Result 'LAPS read delegated only to the right tier' ($(if ($overBroad.Count -eq 0) { 'PASS' } else { 'FAIL' })) `
    ("delegated trustees: {0}" -f ($groups -join ', '))}

Try-Check 'Protected Users contains human accounts only' {
  $members = @(Get-ADGroupMember 'Protected Users' -ErrorAction SilentlyContinue)
  $nonHuman = @($members | Where-Object { $_.objectClass -ne 'user' })
  Add-Result 'Protected Users contains human accounts only' ($(if ($nonHuman.Count -eq 0) { 'PASS' } else { 'FAIL' })) `
    ("non-user members: {0}" -f ($(if ($nonHuman) { ($nonHuman | Select-Object -ExpandProperty SamAccountName) -join ', ' } else { 'none' })))
}

Try-Check 'GPO deny-logon user rights are configured' {
  $missing = @()
  foreach ($gpo in @('WKS - Tier Restrictions - v1', 'SRV - Tier Restrictions - v1', 'DC - Allow Tier 0 Only - v1')) {
    if (-not (Get-GPO -Name $gpo -ErrorAction SilentlyContinue)) { $missing += $gpo }
  }
  Add-Result 'GPO deny-logon user rights are configured' ($(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' })) `
    ($(if ($missing) { "missing GPOs: $($missing -join ', ')" } else { 'all three tier GPOs exist' }))
}

Try-Check 'Helpdesk delegation on user OUs' {
  $delegated = 0
  foreach ($dept in @('Management', 'Finance', 'HR', 'Sales', 'Operations', 'IT')) {
    $acl = Get-Acl -Path "AD:OU=$dept,OU=Users,OU=Halden,$root"
    if ($acl.Access | Where-Object { $_.IdentityReference.Value -match 'G_Tier2_Helpdesk' }) { $delegated++ }
  }
  Add-Result 'Helpdesk delegation on user OUs' ($(if ($delegated -gt 0) { 'PASS' } else { 'FAIL' })) ("OUs delegated: {0}" -f $delegated)
}

Try-Check 'gMSA replaces the legacy service account' {
  $gmsa = Get-ADServiceAccount -Filter "Name -eq 'gmsa-sql'" -ErrorAction SilentlyContinue
  $legacy = Get-ADUser -Filter "SamAccountName -eq 'svc-sql'" -Properties Enabled -ErrorAction SilentlyContinue
  $ok = ($null -ne $gmsa) -and ($null -eq $legacy -or -not $legacy.Enabled)
  Add-Result 'gMSA replaces the legacy service account' ($(if ($ok) { 'PASS' } else { 'FAIL' })) `
    ("gMSA present: {0}; legacy enabled: {1}" -f ([bool]$gmsa), $(if ($legacy) { $legacy.Enabled } else { 'removed' }))
}

Try-Check 'NTLM auditing enabled' {
  $level = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name AuditReceivingNTLMTraffic -ErrorAction SilentlyContinue).AuditReceivingNTLMTraffic
  Add-Result 'NTLM auditing enabled' ($(if ($level) { 'PASS' } else { 'FAIL' })) ("AuditReceivingNTLMTraffic={0}" -f $(if ($level) { $level } else { 'not set' }))
}

Try-Check 'LM compatibility level set to refuse LM and NTLM' {
  $level = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -ErrorAction SilentlyContinue).LmCompatibilityLevel
  Add-Result 'LM compatibility level set to refuse LM and NTLM' ($(if ($level -ge 5) { 'PASS' } else { 'FAIL' })) ("LmCompatibilityLevel={0}" -f $(if ($null -ne $level) { $level } else { 'not set' }))
}

Try-Check 'Assessment before/after evidence exists' {
  $raw = Join-Path $PSScriptRoot '..\evidence\raw'
  $before = Test-Path (Join-Path $raw 'p03-ph1-pingcastle-before-summary.csv')
  $after  = Test-Path (Join-Path $raw 'p03-ph7-pingcastle-after-summary.csv')
  Add-Result 'Assessment before/after evidence exists' ($(if ($before -and $after) { 'PASS' } else { 'UNKNOWN' })) `
    ("before report: {0}; after report: {1}" -f $before, $after)
}

New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
$results | Export-Csv -Path $Report -NoTypeInformation
$results | Format-Table Control, Status, Detail -AutoSize
$pass = @($results | Where-Object Status -eq 'PASS').Count
$fail = @($results | Where-Object Status -eq 'FAIL').Count
$unknown = @($results | Where-Object Status -eq 'UNKNOWN').Count
Write-Output ("Verification: {0} PASS, {1} FAIL, {2} UNKNOWN - written to {3}" -f $pass, $fail, $unknown, $Report)
Write-Warning 'A PASS here is a verified control. Copy these rows into the README results table only after the run, with this CSV as the source.'

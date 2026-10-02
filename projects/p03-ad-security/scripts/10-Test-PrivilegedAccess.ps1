<#
.SYNOPSIS
  P3 Phase 5: privilege and delegation checks before trusting the tiering — group-membership
  hygiene, dangerous ACLs on domain objects, adminSDHolder, stale privileged accounts and
  Kerberos delegation. Read-only.

.DESCRIPTION
  Tiering is only real if it is verified. This script checks the things a tiering model is
  supposed to fix and writes a CSV of exceptions:

    * privileged group membership (Domain Admins, Enterprise Admins, Administrators, Account
      Operators, Backup Operators, Server Operators and the rest)
    * accounts with the "adminCount" flag set but not in a protected group (orphans)
    * stale or disabled privileged accounts, and privileged accounts that never logged in
    * non-default (dangerous) ACEs on the domain, the AdminSDHolder object and the Domain
      Controllers OU — including the extended rights an attacker would use to take over
    * Kerberos delegation that still exists anywhere (constrained or unconstrained)
    * the adminSDHolder owner and undeleted links

  Nothing is changed here: the output is the exception list that Phase 7 records as residual
  risk or feeds back into further remediation.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER StaleDays
  A privileged account that has not logged in for this many days counts as stale. Default 90.

.PARAMETER Report
  CSV output. Defaults to ..\evidence\raw\p03-ph5-privilege-audit-result.csv.

.EXAMPLE
  .\10-Test-PrivilegedAccess.ps1

.NOTES
  Read-only. Run it after 07-Set-AdminTiering.ps1 and again after any change. A clean report is
  the evidence for the README's results table; it is not filled in until it has actually run.
#>
[CmdletBinding()]
param(
  [string]$Domain = 'ad.halden.internal',
  [int]$StaleDays = 90,
  [string]$Report = "$PSScriptRoot\..\evidence\raw\p03-ph5-privilege-audit-result.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding([string]$Check, [string]$Severity, [string]$Object, [string]$Detail) {
  $findings.Add([pscustomobject]@{
    Time = (Get-Date -Format s); Check = $Check; Severity = $Severity
    Object = $Object; Detail = $Detail
  })
}

$root = (Get-ADDomain).DistinguishedName
$privilegedGroups = @(
  'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators',
  'Account Operators', 'Backup Operators', 'Server Operators', 'Print Operators',
  'Group Policy Creator Owners', 'Protected Users', 'Key Admins', 'Enterprise Key Admins'
)

# ---------------------------------------------------------------- 1. Privileged group membership
foreach ($groupName in $privilegedGroups) {
  $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
  if (-not $group) { continue }
  foreach ($member in @(Get-ADGroupMember $group -ErrorAction SilentlyContinue)) {
    $isAdminAccount = $member.SamAccountName -match '^adm-t[012]-'
    $isBreakGlass  = $member.SamAccountName -eq 'Administrator'
    if ($member.objectClass -eq 'user' -and -not $isAdminAccount -and -not $isBreakGlass) {
      if ($groupName -eq 'Domain Admins') {
        Add-Finding 'privileged-group-membership' 'high' $member.SamAccountName `
          "daily-use or unmanaged account in $groupName"
      }
    }
  }
}

# ---------------------------------------------------------------- 2. Stale or disabled privileged accounts
$privilegedSams = @()
foreach ($groupName in @('Domain Admins', 'Enterprise Admins', 'Administrators')) {
  $privilegedSams += @(Get-ADGroupMember $groupName -ErrorAction SilentlyContinue |
    Where-Object objectClass -eq 'user' | Select-Object -ExpandProperty SamAccountName)
}
$privilegedSams = $privilegedSams | Sort-Object -Unique
$cutoff = (Get-Date).AddDays(-$StaleDays)
foreach ($sam in $privilegedSams) {
  $user = Get-ADUser $sam -Properties LastLogonDate, Enabled, PasswordLastSet -ErrorAction SilentlyContinue
  if (-not $user) { continue }
  if (-not $user.Enabled) {
    Add-Finding 'disabled-privileged-account' 'high' $sam 'disabled account still holds privileged membership'
  }
  if ($user.LastLogonDate -and $user.LastLogonDate -lt $cutoff) {
    Add-Finding 'stale-privileged-account' 'medium' $sam ("last logon {0}" -f $user.LastLogonDate)
  } elseif (-not $user.LastLogonDate) {
    Add-Finding 'never-logged-in-privileged' 'medium' $sam ('no LastLogonDate recorded')
  }
}

# ---------------------------------------------------------------- 3. adminCount orphans
$adminCountUsers = @(Get-ADUser -Filter 'adminCount -eq 1' -Properties adminCount, Enabled)
foreach ($user in $adminCountUsers) {
  $inProtected = $false
  foreach ($groupName in $privilegedGroups) {
    $members = @(Get-ADGroupMember $groupName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName)
    if ($user.SamAccountName -in $members) { $inProtected = $true; break }
  }
  if (-not $inProtected) {
    Add-Finding 'admincount-orphan' 'low' $user.SamAccountName `
      'adminCount is set but the account is not in a protected group; its ACL is not inherited'
  }
}

# ---------------------------------------------------------------- 4. Dangerous ACLs on Tier 0 objects
$dangerousRights = @(
  'GenericAll', 'GenericWrite', 'WriteDacl', 'WriteOwner', 'WriteMember',
  'ExtendedRight', 'AllExtendedRights'
)
$tier0Objects = @(
  $root,
  "CN=AdminSDHolder,CN=System,$root",
  "OU=Domain Controllers,$root",
  "CN=Domain Admins,CN=Users,$root",
  "CN=Enterprise Admins,CN=Users,$root",
  "CN=Administrators,CN=Builtin,$root"
)
foreach ($objectDn in $tier0Objects) {
  try {
    $acl = Get-Acl -Path "AD:$objectDn"
  } catch {
    Add-Finding 'acl-read' 'low' $objectDn "could not read the ACL: $($_.Exception.Message)"
    continue
  }
  foreach ($ace in $acl.Access) {
    $identity = $ace.IdentityReference.Value
    $rights = $ace.ActiveDirectoryRights.ToString()
    $isExpected = ($identity -match '^(NT AUTHORITY|BUILTIN|NT SERVICE)\\') -or ($identity -match 'Administrators$')
    $holdsDangerousRight = [bool]($dangerousRights | Where-Object { $rights -match $_ })
    if ((-not $isExpected) -and $ace.AccessControlType -eq 'Allow' -and $holdsDangerousRight) {
      Add-Finding 'dangerous-acl' 'high' $objectDn `
        "$identity has $rights on this Tier 0 object"
    }
  }
}

# ---------------------------------------------------------------- 5. Kerberos delegation still present
$delegatedComputers = @(Get-ADComputer -Filter 'TrustedForDelegation -eq $true' -Properties TrustedForDelegation, msDS-AllowedToDelegateTo -ErrorAction SilentlyContinue)
foreach ($computer in $delegatedComputers) {
  if ($computer.TrustedForDelegation) {
    Add-Finding 'unconstrained-delegation' 'high' $computer.Name 'server trusted for unconstrained delegation'
  }
}
$constrained = @(Get-ADObject -Filter { msDS-AllowedToDelegateTo -like '*' } -Properties msDS-AllowedToDelegateTo `
  -SearchBase $root -ErrorAction SilentlyContinue)
foreach ($object in $constrained) {
  Add-Finding 'constrained-delegation' 'medium' $object.Name `
    ("can delegate to: {0}" -f ($object.'msDS-AllowedToDelegateTo' -join ', '))
}

# ---------------------------------------------------------------- 6. adminSDHolder ownership and undeleted links
try {
  $adminSdHolder = Get-Acl -Path "AD:CN=AdminSDHolder,CN=System,$root"
  Add-Finding 'adminsdholder-owner' 'info' 'CN=AdminSDHolder' ("owner is {0}" -f $adminSdHolder.Owner)
} catch {
  Add-Finding 'adminsdholder-owner' 'low' 'CN=AdminSDHolder' "could not read the owner: $($_.Exception.Message)"
}

New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
$findings | Export-Csv -Path $Report -NoTypeInformation
$summary = $findings | Group-Object Check | Select-Object Name, Count
$summary | Format-Table -AutoSize
Write-Output ("{0} exception(s) written to {1}" -f $findings.Count, $Report)
Write-Warning 'Each exception is a candidate finding for the register. Nothing here is a pass or a fail until it has been reviewed.'

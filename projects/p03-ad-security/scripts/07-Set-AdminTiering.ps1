<#
.SYNOPSIS
  P3 Phase 4: create the three-tier privileged access model — the _Admin OU tree, the tiered
  admin accounts and groups, logon restrictions, Protected Users, the Tier 0 PAW, and delegated
  helpdesk rights. Idempotent; every action is logged.

.DESCRIPTION
  A practical, small-business version of Microsoft's Enterprise Access Model:

    Tier 0  domain and identity infrastructure   -> adm-t0-*   -> DCs and the PAW only
    Tier 1  member servers and applications      -> adm-t1-*   -> servers only
    Tier 2  workstations and user support        -> adm-t2-*   -> workstations only

  Every IT person keeps a separate daily-use account with no admin rights. Admin accounts are
  marked "sensitive and cannot be delegated"; human Tier 0 accounts are added to Protected Users
  (test account first — see the runbook). Logon restrictions are applied through a GptTmpl.inf
  user-rights file inside each GPO, because user rights are not registry values.

  Test the deny-logon rules before trusting them: 10-Test-PrivilegedAccess.ps1 checks them.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER InventoryCsv
  The synthetic account/group inventory that plans the tiering. Defaults to
  ..\data\halden-account-inventory.csv.

.PARAMETER ProtectedUsersTier0
  Add human Tier 0 admin accounts to Protected Users. Default false; enable it only after the
  test account has been proven to work (see docs/runbooks/tier0-credential-exposure.md).

.PARAMETER PawComputer
  The workstation used as the Tier 0 Privileged Access Workstation. Default WS02.

.PARAMETER Log
  CSV action log. Defaults to ..\evidence\raw\p03-ph4-tiering-log.csv.

.EXAMPLE
  .\07-Set-AdminTiering.ps1 -WhatIf
  Preview the whole tiering change.

.EXAMPLE
  .\07-Set-AdminTiering.ps1 -ProtectedUsersTier0

.NOTES
  Snapshot DC01 and DC02 first (snap-p3-ph4-before). Rollback: revert the snapshots, or remove
  the created OUs, groups and admin accounts by running the script's log in reverse. Do not
  delete an account that has been logged in with until you have confirmed it is unused.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$InventoryCsv = "$PSScriptRoot\..\data\halden-account-inventory.csv",
  [switch]$ProtectedUsersTier0,
  [string]$PawComputer = 'WS02',
  [string]$Log = "$PSScriptRoot\..\evidence\raw\p03-ph4-tiering-log.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$root = (Get-ADDomain).DistinguishedName
$adminOu = "OU=_Admin,$root"
$passwordLog = "$PSScriptRoot\..\logs\p03-admin-passwords-$((Get-Date).ToString('yyyyMMdd')).csv"
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null

$actions = [System.Collections.Generic.List[object]]::new()
$initialPasswords = [System.Collections.Generic.List[object]]::new()
function Add-Action([string]$Item, [string]$Action, [string]$Detail) {
  $actions.Add([pscustomobject]@{ Time = Get-Date -Format s; Item = $Item; Action = $Action; Detail = $Detail })
}
function New-Ou([string]$Name, [string]$Path) {
  if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess("OU=$Name,$Path", 'Create OU')) {
      New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
      Add-Action "OU=$Name" 'created' "under $Path"
    }
  }
}
function New-AdminGroup([string]$Name, [string]$Path) {
  if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($Name, 'Create admin group')) {
      New-ADGroup -Name $Name -GroupScope Global -Path $Path
      Add-Action $Name 'group-created' "in $Path"
    }
  }
}
function New-RandomPassword {
  $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%+='.ToCharArray()
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}
function Get-GroupSid([string]$Name) {
  $group = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
  if ($group) { "*$($group.SID.Value)" } else { $null }
}

# ---------------------------------------------------------------- 1. _Admin OU tree
New-Ou 'Tier0' $adminOu; New-Ou 'Tier1' $adminOu; New-Ou 'Tier2' $adminOu; New-Ou 'PAW' $adminOu
foreach ($tier in @('Tier0', 'Tier1', 'Tier2')) {
  New-Ou 'Accounts' "OU=$tier,$adminOu"
  New-Ou 'Groups' "OU=$tier,$adminOu"
}
New-Ou 'Devices' "OU=PAW,$adminOu"

# ---------------------------------------------------------------- 2. Groups
$groups = @(
  @{ Name = 'G_Tier0_Admins';       Path = "OU=Groups,OU=Tier0,$adminOu" },
  @{ Name = 'G_Tier1_Admins';       Path = "OU=Groups,OU=Tier1,$adminOu" },
  @{ Name = 'G_Tier2_Admins';       Path = "OU=Groups,OU=Tier2,$adminOu" },
  @{ Name = 'G_Tier1_ServerAdmins'; Path = "OU=Groups,OU=Tier1,$adminOu" },
  @{ Name = 'G_Tier2_Helpdesk';     Path = "OU=Groups,OU=Tier2,$adminOu" }
)
foreach ($group in $groups) { New-AdminGroup $group.Name $group.Path }

# ---------------------------------------------------------------- 3. Admin accounts from the inventory
$adminAccounts = @()
if (Test-Path $InventoryCsv) {
  $adminAccounts = @(Import-Csv $InventoryCsv | Where-Object { $_.Type -eq 'Admin' -and $_.ProposedTier -match '^[012]$' })
} else {
  Write-Warning "Inventory CSV not found at $InventoryCsv; skipping admin account creation."
}
foreach ($row in $adminAccounts) {
  $sam = $row.Account
  if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) { continue }
  $tier = $row.ProposedTier
  $target = "OU=Accounts,OU=Tier$tier,$adminOu"
  $password = New-RandomPassword
  if ($PSCmdlet.ShouldProcess($sam, "Create Tier $tier admin account")) {
    New-ADUser -Name $row.DisplayName -SamAccountName $sam -UserPrincipalName "$sam@$Domain" -Path $target `
      -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
      -ChangePasswordAtLogon $true -Enabled $true -Description "P3: Tier $tier admin for $($row.AdminFor)"
    Set-ADAccountControl -Identity $sam -AccountNotDelegated $true -DoesNotRequirePreAuth $false
    $tierGroup = "G_Tier$tier`_Admins"
    if (Get-ADGroup -Filter "Name -eq '$tierGroup'" -ErrorAction SilentlyContinue) {
      Add-ADGroupMember -Identity $tierGroup -Members $sam
    }
    $initialPasswords.Add([pscustomobject]@{ Account = $sam; InitialPassword = $password })
    Add-Action $sam 'admin-account-created' "Tier $tier; not delegable; member of $tierGroup"
  }
}

# ---------------------------------------------------------------- 4. Service/admin hygiene flags
$adminInTier0 = @(Get-ADGroupMember 'G_Tier0_Admins' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName)
foreach ($sam in $adminInTier0) {
  if ($PSCmdlet.ShouldProcess($sam, 'Mark account sensitive and not delegable')) {
    Set-ADAccountControl -Identity $sam -AccountNotDelegated $true
    Add-Action $sam 'not-delegable' 'Account is sensitive and cannot be delegated'
  }
}

# ---------------------------------------------------------------- 5. Protected Users (humans only)
if ($ProtectedUsersTier0) {
  foreach ($sam in $adminInTier0) {
    $isHuman = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if (-not $isHuman) { continue }   # never add computer or service accounts
    $member = Get-ADGroupMember 'Protected Users' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
    if ($sam -notin $member) {
      if ($PSCmdlet.ShouldProcess($sam, 'Add to Protected Users')) {
        Add-ADGroupMember 'Protected Users' -Members $sam
        Add-Action $sam 'protected-users' 'human Tier 0 account added (no NTLM, no delegation, no cached credentials)'
      }
    }
  }
} else {
  Add-Action '(Protected Users)' 'skipped' 'not requested; prove the test account first, then re-run with -ProtectedUsersTier0'
}

# ---------------------------------------------------------------- 6. Logon-restriction GPOs (user rights via GptTmpl.inf)
function Set-UserRightsGpo {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [string]$GpoName,
    [string]$TargetOu,
    [hashtable]$Rights
  )
  $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
  if (-not $gpo) {
    if (-not $PSCmdlet.ShouldProcess($GpoName, 'Create logon-restriction GPO')) { return }
    $gpo = New-GPO -Name $GpoName -Comment 'P3: tier logon restrictions (user rights).'
    New-GPLink -Name $GpoName -Target $TargetOu | Out-Null
  }
  $lines = @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1', '[Privilege Rights]')
  foreach ($right in $Rights.Keys) {
    $sids = @($Rights[$right] | ForEach-Object { Get-GroupSid $_ } | Where-Object { $_ })
    if ($sids.Count -gt 0) { $lines += ("{0} = {1}" -f $right, ($sids -join ',')) }
  }
  $infPath = "\\$Domain\SYSVOL\$Domain\Policies\{$($gpo.Id)}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
  if ($PSCmdlet.ShouldProcess($infPath, 'Write user rights')) {
    New-Item -ItemType Directory -Force (Split-Path $infPath) | Out-Null
    $lines | Set-Content -Path $infPath -Encoding Unicode
    Add-Action $GpoName 'user-rights-written' ("linked to {0}" -f $TargetOu)
  }
}
$wksOu = "OU=Workstations,OU=Computers,OU=Halden,$root"
$srvOu = "OU=Servers,OU=Halden,$root"
$dcOu = "OU=Domain Controllers,$root"

Set-UserRightsGpo -GpoName 'WKS - Tier Restrictions - v1' -TargetOu $wksOu -Rights @{
  SeDenyInteractiveLogonRight       = @('G_Tier0_Admins', 'G_Tier1_Admins')
  SeDenyRemoteInteractiveLogonRight = @('G_Tier0_Admins', 'G_Tier1_Admins')
  SeDenyBatchLogonRight             = @('G_Tier0_Admins', 'G_Tier1_Admins')
  SeDenyServiceLogonRight           = @('G_Tier0_Admins', 'G_Tier1_Admins')
  SeInteractiveLogonRight           = @('G_Tier2_Admins', 'G_AllStaff')
  SeRemoteInteractiveLogonRight     = @('G_Tier2_Admins')
}
Set-UserRightsGpo -GpoName 'SRV - Tier Restrictions - v1' -TargetOu $srvOu -Rights @{
  SeDenyInteractiveLogonRight       = @('G_Tier0_Admins', 'G_Tier2_Admins')
  SeDenyRemoteInteractiveLogonRight = @('G_Tier0_Admins', 'G_Tier2_Admins')
  SeInteractiveLogonRight           = @('G_Tier1_Admins', 'G_Tier1_ServerAdmins')
  SeRemoteInteractiveLogonRight     = @('G_Tier1_Admins', 'G_Tier1_ServerAdmins')
}
Set-UserRightsGpo -GpoName 'DC - Allow Tier 0 Only - v1' -TargetOu $dcOu -Rights @{
  SeInteractiveLogonRight           = @('G_Tier0_Admins')
  SeRemoteInteractiveLogonRight     = @('G_Tier0_Admins')
  SeDenyRemoteInteractiveLogonRight = @('G_Tier1_Admins', 'G_Tier2_Admins')
}

# ---------------------------------------------------------------- 7. Helpdesk delegation on user OUs
function Grant-ResetPasswordDelegation([string]$OuDn, [string]$GroupName) {
  $group = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
  if (-not $group) { Add-Action $OuDn 'skipped' "$GroupName does not exist"; return }
  if (-not (Get-ADOrganizationalUnit -Identity $OuDn -ErrorAction SilentlyContinue)) { return }
  if ($PSCmdlet.ShouldProcess("$OuDn -> $GroupName", 'Delegate Reset Password')) {
    $ou = [ADSI]"LDAP://$OuDn"
    $sid = New-Object System.Security.Principal.SecurityIdentifier($group.SID.Value)
    # Extended right 00299570-246d-11d0-a768-00aa006e0529 = Reset Password.
    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
      $sid, [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight, 'Allow',
      [guid]'00299570-246d-11d0-a768-00aa006e0529')
    $acl = $ou.ObjectSecurity
    $acl.AddAccessRule($rule)
    $ou.ObjectSecurity = $acl
    $ou.CommitChanges()
    Add-Action "$OuDn / $GroupName" 'delegation' 'Reset Password granted; no Domain Admin needed'
  }
}
foreach ($dept in @('Management', 'Finance', 'HR', 'Sales', 'Operations', 'IT')) {
  Grant-ResetPasswordDelegation -OuDn "OU=$dept,OU=Users,OU=Halden,$root" -GroupName 'G_Tier2_Helpdesk'
}

# ---------------------------------------------------------------- 8. Tier 0 PAW
$pawOu = "OU=Devices,OU=PAW,$adminOu"
$paw = Get-ADComputer -Filter "Name -eq '$PawComputer'" -ErrorAction SilentlyContinue
if ($paw) {
  if ($PawComputer -ne 'WS01') {
    if ($PSCmdlet.ShouldProcess($PawComputer, 'Move to the PAW OU')) {
      Move-ADObject -Identity $paw.DistinguishedName -TargetPath $pawOu
      Add-Action $PawComputer 'paw' 'moved to the Privileged Access Workstation OU; network lockdown is added in P6'
    }
  }
} else {
  Add-Action $PawComputer 'skipped' 'computer object not found; create the PAW VM first'
}

if ($initialPasswords.Count -gt 0) {
  New-Item -ItemType Directory -Force (Split-Path $passwordLog) | Out-Null
  $initialPasswords | Export-Csv -Path $passwordLog -NoTypeInformation
  Write-Warning "Initial admin passwords written to $passwordLog (git-ignored). Hand them over securely and delete the file after first use."
}
$actions | Export-Csv -Path $Log -NoTypeInformation -Append
Write-Output ("Tiering complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
Write-Output 'Next: run gpupdate, then 10-Test-PrivilegedAccess.ps1 to prove the deny-logon rules actually work.'

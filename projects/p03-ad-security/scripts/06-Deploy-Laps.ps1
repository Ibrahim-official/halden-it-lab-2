<#
.SYNOPSIS
  P3 Phase 3: extend the AD schema for Windows LAPS, delegate password read rights, create the
  LAPS Group Policy objects, and (optionally) enable the managed local administrator account.
  Idempotent; every action is logged.

.DESCRIPTION
  Windows LAPS is built into Windows Server 2019+ and Windows 11 and gives every workstation and
  member server a unique, rotating local administrator password backed up to Active Directory and
  encrypted. This script does the directory side of the rollout:

    * Update-LapsADSchema (once, requires Schema Admin)
    * grant computers the right to write their own password (self permission) on the
      Workstations and Servers OUs
    * grant the helpdesk group read rights on workstations and the server admins on servers
    * create the three LAPS GPOs described in configs/p03-laps-gpo-settings.conf
    * optionally create the managed local administrator account

  The one thing it must never do is grant read rights to a broad group: a readable LAPS password
  is a working local administrator credential. Nothing is measured until 09-Test-LapsAccess.ps1
  and 11-Verify-Remediation.ps1 have run.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER WorkstationOu
  Distinguished name of the Workstations OU.

.PARAMETER ServerOu
  Distinguished name of the Servers OU.

.PARAMETER HelpdeskGroup
  Group allowed to read workstation LAPS passwords. Default G_Tier2_Helpdesk.

.PARAMETER ServerAdminGroup
  Group allowed to read server LAPS passwords. Default G_Tier1_ServerAdmins.

.PARAMETER ManagedLocalAdmin
  Name of the managed local administrator account to create. Default LocalAdmin.

.PARAMETER Log
  CSV action log. Defaults to ..\evidence\raw\p03-ph3-laps-log.csv.

.EXAMPLE
  .\06-Deploy-Laps.ps1 -WhatIf
  Preview every change.

.EXAMPLE
  .\06-Deploy-Laps.ps1 -WorkstationOu 'OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal' `
    -ServerOu 'OU=Servers,OU=Halden,DC=ad,DC=halden,DC=internal'

.NOTES
  Snapshot DC01 and DC02 first (snap-p3-ph3-before). Schema changes are forest-wide and
  irreversible: this is the reason the whole forest is snapshotted before the phase.
  Rollback: revert DC01 and DC02 snapshots together.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$WorkstationOu,
  [string]$ServerOu,
  [string]$HelpdeskGroup = 'G_Tier2_Helpdesk',
  [string]$ServerAdminGroup = 'G_Tier1_ServerAdmins',
  [string]$ManagedLocalAdmin = 'LocalAdmin',
  [string]$Log = "$PSScriptRoot\..\evidence\raw\p03-ph3-laps-log.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$root = (Get-ADDomain).DistinguishedName
if (-not $WorkstationOu) { $WorkstationOu = "OU=Workstations,OU=Computers,OU=Halden,$root" }
if (-not $ServerOu) { $ServerOu = "OU=Servers,OU=Halden,$root" }

New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$actions = [System.Collections.Generic.List[object]]::new()
function Add-Action([string]$Item, [string]$Action, [string]$Detail) {
  $actions.Add([pscustomobject]@{ Time = Get-Date -Format s; Item = $Item; Action = $Action; Detail = $Detail })
}

# ---------------------------------------------------------------- 1. Schema extension
try {
  $schemaState = Get-ADObject "CN=ms-LAPS-Password,CN=Schema,CN=Configuration,$root" -ErrorAction Stop
  Add-Action '(LAPS schema)' 'exists-skip' 'ms-LAPS-Password attribute already present'
} catch {
  if ($PSCmdlet.ShouldProcess($Domain, 'Extend schema for Windows LAPS')) {
    Update-LapsADSchema -Confirm:$false
    Add-Action '(LAPS schema)' 'extended' 'Windows LAPS schema attributes added (forest-wide, irreversible)'
  }
}

# ---------------------------------------------------------------- 2. Self permission (computers write their own password)
function Grant-SelfPermission([string]$Ou) {
  $existing = Get-LapsADComputerSelfPermission -Identity $Ou -ErrorAction SilentlyContinue
  if ($existing) {
    Add-Action $Ou 'exists-skip' 'computer self permission already present'
    return
  }
  if ($PSCmdlet.ShouldProcess($Ou, 'Grant LAPS computer self permission')) {
    Set-LapsADComputerSelfPermission -Identity $Ou
    Add-Action $Ou 'self-permission' 'computers may write their own LAPS password'
  }
}
Grant-SelfPermission $WorkstationOu
Grant-SelfPermission $ServerOu

# ---------------------------------------------------------------- 3. Read permission (only the right tier)
function Grant-ReadPermission([string]$Ou, [string]$Principal) {
  $group = Get-ADGroup -Filter "Name -eq '$Principal'" -ErrorAction SilentlyContinue
  if (-not $group) {
    Add-Action $Ou 'skipped' "principal $Principal does not exist yet"
    return
  }
  $existing = Get-LapsADReadPasswordPermission -Identity $Ou -ErrorAction SilentlyContinue
  if (@($existing) -match $Principal) {
    Add-Action "$Ou / $Principal" 'exists-skip' 'read permission already delegated'
    return
  }
  if ($PSCmdlet.ShouldProcess("$Ou -> $Principal", 'Delegate LAPS password read')) {
    Set-LapsADReadPasswordPermission -Identity $Ou -AllowedPrincipals "HALDEN\$Principal"
    Add-Action "$Ou / $Principal" 'read-permission' 'allowed to read LAPS passwords on this OU'
  }
}
Grant-ReadPermission $WorkstationOu $HelpdeskGroup
Grant-ReadPermission $ServerOu $ServerAdminGroup

# ---------------------------------------------------------------- 4. LAPS GPOs (settings in configs)
$gpoSettings = [ordered]@{
  'WKS - LAPS - v1' = @{
    Target = $WorkstationOu
    Decryptors = $HelpdeskGroup
    Comment = 'P3: Windows LAPS for workstations; passwords encrypted, helpdesk may read.'
  }
  'SRV - LAPS - v1' = @{
    Target = $ServerOu
    Decryptors = $ServerAdminGroup
    Comment = 'P3: Windows LAPS for member servers; passwords encrypted, server admins may read.'
  }
  'DC - LAPS - v1' = @{
    Target = "OU=Domain Controllers,$root"
    Decryptors = 'G_Tier0_Admins'
    Comment = 'P3: Windows LAPS for domain controllers, including DSRM password backup.'
  }
}
foreach ($name in $gpoSettings.Keys) {
  $settings = $gpoSettings[$name]
  if (Get-GPO -Name $name -ErrorAction SilentlyContinue) {
    Add-Action $name 'exists-skip' 'GPO already present'
    continue
  }
  if ($PSCmdlet.ShouldProcess($name, 'Create LAPS GPO')) {
    New-GPO -Name $name -Comment $settings.Comment | Out-Null
    New-GPLink -Name $name -Target $settings.Target | Out-Null

    $lapsKey = 'HKLM\SOFTWARE\Microsoft\Policies\LAPS'
    # Numeric policy values follow the Windows LAPS ADMX. The authoritative, human-readable
    # specification is configs/p03-laps-gpo-settings.conf: confirm each mapping against the
    # current Microsoft Windows LAPS documentation before the run.
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'BackupDirectory' -Type DWord -Value 2 | Out-Null   # 2 = Active Directory
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'PasswordComplexity' -Type DWord -Value 4 | Out-Null # 4 = large+small+numbers+specials
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'PasswordLength' -Type DWord -Value 20 | Out-Null
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'PasswordAgeDays' -Type DWord -Value 30 | Out-Null
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'PasswordExpirationProtectionEnabled' -Type DWord -Value 1 | Out-Null
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'ADPasswordEncryptionEnabled' -Type DWord -Value 1 | Out-Null
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'ADPasswordEncryptionPrincipal' -Type String -Value "HALDEN\$($settings.Decryptors)" | Out-Null
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'PostAuthenticationActions' -Type DWord -Value 1 | Out-Null  # reset password and log off
    Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'PostAuthenticationResetDelay' -Type DWord -Value 8 | Out-Null
    if ($name -like 'DC - LAPS*') {
      # Windows LAPS can also back up the Directory Services Restore Mode password for a DC.
      Set-GPRegistryValue -Name $name -Key $lapsKey -ValueName 'BackupDSRMPassword' -Type DWord -Value 1 | Out-Null
    }
    Add-Action $name 'created' "linked to $($settings.Target)"
  }
}

# ---------------------------------------------------------------- 5. Managed local administrator account
if ($PSCmdlet.ShouldProcess($ManagedLocalAdmin, 'Configure managed local administrator account (GPO)')) {
  $name = 'WKS - LAPS - v1'
  if (Get-GPO -Name $name -ErrorAction SilentlyContinue) {
    Set-GPRegistryValue -Name $name -Key 'HKLM\SOFTWARE\Microsoft\Policies\LAPS' `
      -ValueName 'AdministratorAccountName' -Type String -Value $ManagedLocalAdmin | Out-Null
    Add-Action $ManagedLocalAdmin 'managed-account' "LAPS manages the '$ManagedLocalAdmin' local account"
  }
}

$actions | Export-Csv -Path $Log -NoTypeInformation -Append
Write-Output ("LAPS deployment complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
Write-Output 'Next: run gpupdate on the endpoints, then 10-Test-PrivilegedAccess.ps1 to prove access control.'

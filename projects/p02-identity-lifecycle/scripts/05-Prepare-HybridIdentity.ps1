<#
.SYNOPSIS
  Phase 3: prepare on-premises AD for hybrid identity (UPN suffix, on-prem admin separation).

.DESCRIPTION
  Does the on-premises half of hybrid identity, before the Cloud Sync agent is installed:

    - adds an alternative UPN suffix that matches the tenant's verified or onmicrosoft.com domain
    - updates the UPNs of the managed users to that suffix (the .internal UPN cannot be used for
      cloud sign-in and must not be synced as if it were a routable address)
    - asserts that no privileged (_Admin) or service account is in scope for the scripted sync: the
      real control is the Cloud Sync scope on FS01 (configs\cloud-sync-scope.json), and this script
      prints the on-prem view so the two can be compared

  This is the AD-preparation step, not the sync step. The Cloud Sync agent is a GUI install and is a
  runbook step (docs\runbooks\mfa-and-conditional-access.md): the scope, exclusions and UPNs around
  it are scripted here, which is what actually matters for least privilege.

.PARAMETER UpnSuffix
  The suffix to add and apply, e.g. 'haldenlab.onmicrosoft.com'. Must match the tenant's domain.

.PARAMETER Apply
  Actually change UPNs. Without it the script reports only (read-only by design).

.PARAMETER ExcludeOu
  OUs whose users must keep their original UPN and never receive the routable suffix. Defaults to the
  service-accounts OU; _Admin accounts are cloud-only and are handled in Phase 3's break-glass step.

.EXAMPLE
  .\05-Prepare-HybridIdentity.ps1 -UpnSuffix 'haldenlab.onmicrosoft.com'
  Report what would change. Changes nothing.

.EXAMPLE
  .\05-Prepare-HybridIdentity.ps1 -UpnSuffix 'haldenlab.onmicrosoft.com' -Apply
  Add the suffix and update the managed users' UPNs.

.NOTES
  Run on DC01. Snapshot DC01 first: snap-p3-before (this changes every user object's UPN).
  Rollback: re-run with -Apply -UpnSuffix 'ad.halden.internal', or revert the snapshot.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)] [string] $UpnSuffix,
    [switch] $Apply,
    [string[]] $ExcludeOu = @('OU=ServiceAccounts,OU=Halden'),
    [string] $SearchBase,
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop

$root = (Get-ADDomain).DistinguishedName
if (-not $SearchBase) { $SearchBase = "OU=Users,OU=Halden,$root" }
$operator = "$env:USERDOMAIN\$env:USERNAME"

if ($UpnSuffix -match '\.internal$') {
    throw "Refusing suffix '$UpnSuffix': a .internal name cannot be verified in a tenant and must not be used for cloud UPNs."
}

# --- Add the alternative suffix -----------------------------------------------------------------
$forest = Get-ADForest
if ($forest.UPNSuffixes -contains $UpnSuffix) {
    Write-Host "UPN suffix '$UpnSuffix' is already registered on the forest (idempotent)." -ForegroundColor DarkYellow
} elseif ($PSCmdlet.ShouldProcess($UpnSuffix, 'Register forest UPN suffix')) {
    Set-ADForest -Identity $forest.Name -UPNSuffixes @{ Add = $UpnSuffix }
    Write-Host "Registered UPN suffix '$UpnSuffix'." -ForegroundColor Cyan
}

# --- Who is in scope ----------------------------------------------------------------------------
$targets = @(Get-ADUser -Filter { Enabled -eq $true } -SearchBase $SearchBase -Properties UserPrincipalName, EmployeeID, extensionAttribute1)
$excluded = foreach ($ou in $ExcludeOu) {
    Get-ADUser -Filter * -SearchBase "$ou,$root" -ErrorAction SilentlyContinue
}
$excludedSams = @($excluded | ForEach-Object { $_.SamAccountName })

Write-Host ''
Write-Host "Users in $SearchBase : $($targets.Count)"
Write-Host "Excluded OUs: $($ExcludeOu -join ', ') ($($excludedSams.Count) account(s))"

$toChange = @($targets | Where-Object { $_.SamAccountName -notin $excludedSams -and $_.UserPrincipalName -notlike "*@$UpnSuffix" })
Write-Host "UPNs to update: $($toChange.Count)"
$toChange | Select-Object -First 10 SamAccountName, UserPrincipalName | Format-Table -AutoSize
if ($toChange.Count -gt 10) { Write-Host "  ... and $($toChange.Count - 10) more" }

# --- The Tier 0 assertion -----------------------------------------------------------------------
$adminOu = "OU=_Admin,$root"
$adminsInScope = @()
if (Get-ADOrganizationalUnit -Filter "Name -eq '_Admin'" -SearchBase $root -SearchScope OneLevel -ErrorAction SilentlyContinue) {
    $adminsInScope = @(Get-ADUser -Filter * -SearchBase $adminOu -ErrorAction SilentlyContinue |
        Where-Object { $_.DistinguishedName -like "*$SearchBase*" })
}
if ($adminsInScope.Count -gt 0) {
    Write-Warning "$($adminsInScope.Count) account(s) from OU=_Admin fall inside the sync search base. Fix the scope before syncing: admin accounts must stay cloud-only or on-prem-only."
} else {
    Write-Host 'No _Admin accounts fall inside the user sync scope. Confirm the same on the Cloud Sync agent scope.' -ForegroundColor Green
}

# --- Apply --------------------------------------------------------------------------------------
if (-not $Apply) {
    Write-Host ''
    Write-Host 'Read-only report. Re-run with -Apply to change the UPNs.' -ForegroundColor Cyan
    return
}

$changed = 0
foreach ($u in $toChange) {
    $newUpn = "$($u.SamAccountName)@$UpnSuffix"
    if ($PSCmdlet.ShouldProcess($u.SamAccountName, "Set UPN to $newUpn")) {
        Set-ADUser -Identity $u.SamAccountName -UserPrincipalName $newUpn
        [pscustomobject] @{
            Timestamp = (Get-Date).ToString('s'); Action = 'SetCloudUpn'; Target = $u.SamAccountName
            Before = $u.UserPrincipalName; After = $newUpn; Operator = $operator
        } | Export-Csv -Path "$PSScriptRoot\..\logs\jml-audit.csv" -NoTypeInformation -Append -Encoding UTF8
        $changed++
    }
}
Write-Host ''
Write-Host "Updated $changed UPN(s)." -ForegroundColor Cyan
Write-Host 'Next: install the Cloud Sync agent on FS01 (GUI) and point its scope at configs\cloud-sync-scope.json.' -ForegroundColor Cyan
Write-Host 'Verify: no _Admin or ServiceAccounts object appears in the agent scope, and the agent reports the expected object count.' -ForegroundColor Cyan

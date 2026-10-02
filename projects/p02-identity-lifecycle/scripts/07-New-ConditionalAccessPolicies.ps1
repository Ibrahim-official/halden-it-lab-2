<#
.SYNOPSIS
  Phase 3: deploy the CA001-CA005 Conditional Access policies from configs\conditional-access\*.json.

.DESCRIPTION
  Reads every policy definition in configs\conditional-access\ and creates or updates it in the
  tenant. The JSON files carry a "_comment" header (ignored here) and a "__BREAKGLASS_UPNS__" token,
  which this script replaces with the real break-glass UPNs passed in - so no tenant values live in
  the repository.

  Default state is report-only. This is deliberate and is the whole point of the script: a wrong
  policy that is enforced can lock every user out of the tenant. Report-only records what *would*
  happen, the sign-in logs are reviewed, and only then are the policies enabled:

      .\07-New-ConditionalAccessPolicies.ps1 -State reportOnly -BreakGlassUpn 'a@x','b@x'   # review
      .\07-New-ConditionalAccessPolicies.ps1 -State Enabled   -BreakGlassUpn 'a@x','b@x'   # enforce

  CA003's privileged role list is read from configs\privileged-roles.json and each role name is
  resolved to its template id at deploy time, so the repository stores no role ids and no invented
  values. Microsoft's built-in "Phishing-resistant MFA" authentication strength id in the CA003
  definition is a public constant, not a tenant value.

.PARAMETER State
  reportOnly (default) or Enabled.

.PARAMETER BreakGlassUpn
  The break-glass account UPNs to exclude from every policy. Required: a policy set with no
  break-glass exclusion is a lock-out waiting to happen.

.PARAMETER PolicyNameFilter
  Deploy only policies whose file name matches this substring (e.g. 'CA002' to stage one at a time).

.EXAMPLE
  .\07-New-ConditionalAccessPolicies.ps1 -State reportOnly -BreakGlassUpn 'bg1@tenant','bg2@tenant'
  Create all five policies in report-only and exclude the break-glass accounts.

.EXAMPLE
  .\07-New-ConditionalAccessPolicies.ps1 -State Enabled -BreakGlassUpn 'bg1@tenant','bg2@tenant' -PolicyNameFilter CA001
  Turn on CA001 only.

.NOTES
  Requires Microsoft.Graph (Authentication, Identity.ConditionalAccess) and the
  Conditional Access Administrator role. Run the break-glass script FIRST (06-New-BreakGlassAccounts.ps1).
  Verify with .\09-Invoke-ScubaGear.ps1 before and after.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('reportOnly', 'Enabled')] [string] $State = 'reportOnly',
    [Parameter(Mandatory)] [string[]] $BreakGlassUpn,
    [string] $PolicyDir = "$PSScriptRoot\..\configs\conditional-access",
    [string] $RoleFile  = "$PSScriptRoot\..\configs\privileged-roles.json",
    [string] $PolicyNameFilter = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md Section 2) ------------------------------------------------------------
$markerFile = 'C:\halden-lab-marker'
if (-not (Test-Path $markerFile -PathType Leaf)) {
    throw "Not a Halden lab host (no $markerFile). Aborting. Create it once: New-Item -ItemType File -Path '$markerFile' -Force"
}
$adRoot = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
if ($adRoot -and $adRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }

foreach ($m in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.SignIns') {
    if (-not (Get-Module -ListAvailable -Name $m)) { throw "Required module '$m' is not installed." }
    Import-Module $m -ErrorAction Stop
}

if ($BreakGlassUpn.Count -lt 2) {
    Write-Warning 'Fewer than two break-glass accounts were supplied. One is a single point of failure - the lab design calls for two.'
}
Connect-MgGraph -Scopes 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess' -NoWelcome

# Second half of the guard: refuse to act unless the signed-in tenant is the lab tenant.
$tenantConfig = Join-Path $PSScriptRoot '..\configs\lab-tenant.json'
$tenantDomain = (Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsInitial -or $_.Name -like '*.onmicrosoft.com' } |
    Select-Object -First 1 -ExpandProperty Name
if (Test-Path $tenantConfig) {
    $expected = (Get-Content $tenantConfig -Raw | ConvertFrom-Json).labTenantDomain
    if (-not $expected) { throw 'configs\lab-tenant.json has an empty labTenantDomain. Fill it in before running the cloud scripts.' }
    if ($tenantDomain -ne $expected) { throw "Signed-in tenant does not match the lab tenant in configs\lab-tenant.json. Aborting." }
}
Write-Host 'Signed in to the lab tenant.' -ForegroundColor Green

$stateValue = if ($State -eq 'Enabled') { 'enabled' } else { 'enabledForReportingButNotEnforced' }

# --- Resolve privileged role names to template ids (no ids stored in the repo) -------------------
$adminRole = @('All')
if (Test-Path $RoleFile) {
    $roleNames = (Get-Content $RoleFile -Raw | ConvertFrom-Json).roles
    $templates = Get-MgDirectoryRoleTemplate
    $ids = foreach ($name in $roleNames) {
        $t = $templates | Where-Object { $_.DisplayName -eq $name } | Select-Object -First 1
        if (-not $t) { Write-Warning "Role '$name' not found in the tenant; skipping it."; continue }
        $t.Id
    }
    if ($ids.Count -gt 0) { $adminRole = @($ids) }
} else {
    Write-Warning "Role file $RoleFile not found; CA003 will not target any privileged role."
    $adminRole = @()
}

# --- Deploy each policy -------------------------------------------------------------------------
$deployed = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-ChildItem -Path $PolicyDir -Filter '*.json' | Sort-Object Name) {
    if ($PolicyNameFilter -and $file.Name -notmatch $PolicyNameFilter) { continue }

    Write-Host "Policy file: $($file.Name)" -ForegroundColor Cyan
    $raw = Get-Content $file.FullName -Raw

    # Substitute the tokens. JSON-encode the list, then strip the surrounding quotes so it can be
    # inlined as an array inside the larger JSON document.
    $upnJson   = (ConvertTo-Json -InputObject @($BreakGlassUpn) -Compress)
    $roleJson  = (ConvertTo-Json -InputObject @($adminRole) -Compress)
    $raw = $raw.Replace('["__BREAKGLASS_UPNS__"]', $upnJson).Replace('"__BREAKGLASS_UPNS__"', ($upnJson -replace '^\[|\]$', ''))
    $raw = $raw.Replace('["__ADMIN_ROLE_IDS__"]', $roleJson).Replace('"__ADMIN_ROLE_IDS__"', ($roleJson -replace '^\[|\]$', ''))

    if ($raw -match '__') {
        Write-Warning "  $($file.Name) still contains an unresolved token after substitution - check the placeholder shape."
    }
    $policy = $raw | ConvertFrom-Json
    $body = @{
        displayName = $policy.displayName
        state       = $stateValue
        conditions  = $policy.conditions
    }
    if ($policy.PSObject.Properties.Name -contains 'grantControls')      { $body.grantControls = $policy.grantControls }
    if ($policy.PSObject.Properties.Name -contains 'sessionControls')    { $body.sessionControls = $policy.sessionControls }

    $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($policy.displayName)'" -ErrorAction SilentlyContinue
    if ($existing) {
        if ($PSCmdlet.ShouldProcess($policy.displayName, "Update CA policy to state '$stateValue'")) {
            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -BodyParameter $body | Out-Null
            Write-Host "  updated: $($policy.displayName) -> $stateValue" -ForegroundColor DarkGreen
            $deployed.Add("$($policy.displayName) (updated, $stateValue, id $($existing.Id))")
        }
    } elseif ($PSCmdlet.ShouldProcess($policy.displayName, "Create CA policy in state '$stateValue'")) {
        $new = New-MgIdentityConditionalAccessPolicy -BodyParameter $body
        Write-Host "  created: $($policy.displayName) -> $stateValue" -ForegroundColor DarkGreen
        $deployed.Add("$($policy.displayName) (created, $stateValue, id $($new.Id))")
    }
}

Write-Host ''
Write-Host "Deployed $($deployed.Count) policy/policies in state '$stateValue'." -ForegroundColor Cyan
$deployed | ForEach-Object { Write-Host "  $_" }
Write-Host ''
if ($State -eq 'reportOnly') {
    Write-Host 'NEXT: watch Sign-in logs -> Conditional Access for a few days before enforcing.' -ForegroundColor Yellow
    Write-Host 'Confirm the break-glass accounts are NOT challenged, then re-run with -State Enabled one policy at a time.' -ForegroundColor Yellow
} else {
    Write-Host 'Verify: a password-only sign-in is challenged (CA001); a legacy client is blocked (CA002).' -ForegroundColor Cyan
}
Write-Host 'Never publish the policy ids, tenant id or UPNs (AGENTS.md 4.6) - record only the policy names and states.' -ForegroundColor DarkYellow

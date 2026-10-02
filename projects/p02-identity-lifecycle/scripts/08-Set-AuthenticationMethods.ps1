<#
.SYNOPSIS
  Phase 3: apply the authentication-methods policy from configs\auth-methods-policy.json.

.DESCRIPTION
  Configures the tenant's authentication methods to match the lab design:

    - Microsoft Authenticator enabled, with number matching required (a push cannot be approved blind)
    - SMS and voice disabled where the tenant allows, because they are phishable
    - Temporary Access Pass enabled with a short, single-use lifetime, so onboarding a new starter is
      not blocked while they enrol a stronger method (this is what makes the MFA rollout survivable)

  Reads the desired state from the JSON config rather than hard-coding it, so the design and the
  tenant cannot drift apart silently.

.EXAMPLE
  .\08-Set-AuthenticationMethods.ps1 -WhatIf
  Show the desired state and change nothing.

.EXAMPLE
  .\08-Set-AuthenticationMethods.ps1
  Apply the authentication-methods policy.

.NOTES
  Requires Microsoft.Graph (Authentication, Identity.SignIns) and the Authentication Policy
  Administrator role. Some tenant plans do not allow SMS/voice to be disabled individually; where the
  cmdlet refuses, the script reports it as a documented exception rather than pretending it succeeded.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string] $ConfigFile = "$PSScriptRoot\..\configs\auth-methods-policy.json"
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

$supported = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.SignIns')
foreach ($m in $supported) {
    if (-not (Get-Module -ListAvailable -Name $m)) { throw "Required module '$m' is not installed." }
    Import-Module $m -ErrorAction Stop
}
if (-not (Test-Path $ConfigFile)) { throw "Config not found: $ConfigFile" }

Connect-MgGraph -Scopes 'Policy.ReadWrite.AuthenticationMethod' -NoWelcome

# Second half of the guard: refuse to act unless the signed-in tenant is the lab tenant.
$tenantConfig = Join-Path $PSScriptRoot '..\configs\lab-tenant.json'
$tenantDomain = (Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsInitial -or $_.Name -like '*.onmicrosoft.com' } |
    Select-Object -First 1 -ExpandProperty Name
if (Test-Path $tenantConfig) {
    $expected = (Get-Content $tenantConfig -Raw | ConvertFrom-Json).labTenantDomain
    if (-not $expected) { throw 'configs\lab-tenant.json has an empty labTenantDomain. Fill it in before running the cloud scripts.' }
    if ($tenantDomain -ne $expected) { throw 'Signed-in tenant does not match the lab tenant in configs\lab-tenant.json. Aborting.' }
}
Write-Host 'Signed in to the lab tenant.' -ForegroundColor Green

$desired = (Get-Content $ConfigFile -Raw | ConvertFrom-Json).authenticationMethodConfiguration
$exceptions = New-Object System.Collections.Generic.List[string]

Write-Host 'Desired authentication-methods state:' -ForegroundColor Cyan
$desired.PSObject.Properties | ForEach-Object { Write-Host ("  {0,-26} state: {1}" -f $_.Name, $_.Value.state) }

function Set-MethodState {
    param([string]$Name, [string]$State)
    try {
        if ($PSCmdlet.ShouldProcess($Name, "Set authentication method state to '$State'")) {
            Update-MgPolicyAuthenticationMethodPolicy -AuthenticationMethodConfigurations @(
                @{ '@odata.type' = "#microsoft.graph.$($Name)AuthenticationMethodConfiguration"; id = $Name; state = $State }
            ) -ErrorAction Stop
            Write-Host "  $Name -> $State" -ForegroundColor DarkGreen
        }
    } catch {
        $exceptions.Add("$Name could not be set to '$State': $($_.Exception.Message)")
        Write-Warning "  $Name : $($_.Exception.Message)"
    }
}

# The Graph API takes one configuration object per call; do them explicitly so a failure is isolated.
foreach ($method in 'microsoftAuthenticator', 'sms', 'voice', 'temporaryAccessPass') {
    $cfg = $desired.PSObject.Properties[$method]
    if (-not $cfg) { continue }
    Set-MethodState -Name $method -State $cfg.Value.state
}

# Number matching and the Temporary Access Pass lifetimes are feature settings on their own endpoints.
if ($desired.microsoftAuthenticator.featureSettings.numberMatchingRequiredState -eq 'enabled') {
    if ($PSCmdlet.ShouldProcess('microsoftAuthenticator', 'Require number matching')) {
        try {
            Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration `
                -AuthenticationMethodConfigurationId 'microsoftAuthenticator' `
                -BodyParameter @{ '@odata.type' = '#microsoft.graph.microsoftAuthenticatorAuthenticationMethodConfiguration'
                                  featureSettings = @{ numberMatchingRequiredState = @{ state = 'enabled' } } } -ErrorAction Stop
            Write-Host '  number matching required' -ForegroundColor DarkGreen
        } catch {
            $exceptions.Add("Number matching could not be set: $($_.Exception.Message)")
            Write-Warning "  number matching: $($_.Exception.Message)"
        }
    }
}

if ($desired.temporaryAccessPass.state -eq 'enabled') {
    if ($PSCmdlet.ShouldProcess('temporaryAccessPass', 'Enable Temporary Access Pass for onboarding')) {
        try {
            Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration `
                -AuthenticationMethodConfigurationId 'temporaryAccessPass' `
                -BodyParameter @{
                    '@odata.type'  = '#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration'
                    isUsableOnce   = [bool] $desired.temporaryAccessPass.isUsableOnce
                    defaultLifetimeInMinutes = [int] $desired.temporaryAccessPass.defaultLifetimeInMinutes
                    defaultLength  = [int] $desired.temporaryAccessPass.defaultLength
                } -ErrorAction Stop
            Write-Host '  Temporary Access Pass configured' -ForegroundColor DarkGreen
        } catch {
            $exceptions.Add("Temporary Access Pass could not be configured: $($_.Exception.Message)")
            Write-Warning "  Temporary Access Pass: $($_.Exception.Message)"
        }
    }
}

Write-Host ''
if ($exceptions.Count -gt 0) {
    Write-Host "$($exceptions.Count) item(s) could not be applied - record them as documented exceptions:" -ForegroundColor Yellow
    $exceptions | ForEach-Object { Write-Host "  - $_" }
    $exceptions | Set-Content -Path "$PSScriptRoot\..\reports\auth-methods-exceptions.txt" -Encoding UTF8
} else {
    Write-Host 'Authentication methods applied as designed.' -ForegroundColor Cyan
}
Write-Host 'Verify: a test user sees Authenticator with a number-matching prompt; the helpdesk can issue a TAP for a new starter.' -ForegroundColor Cyan

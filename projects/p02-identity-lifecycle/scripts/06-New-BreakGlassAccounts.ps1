<#
.SYNOPSIS
  Phase 3: create the two cloud-only break-glass accounts and record them in the evidence.

.DESCRIPTION
  A policy that requires MFA for everyone can lock the last administrator out of the tenant. The
  standard defence is two emergency access accounts that bypass every Conditional Access policy, are
  monitored, and are used only when normal administration is unavailable.

  This script creates them as cloud-only accounts on the tenant's onmicrosoft.com domain (so they do
  not depend on the on-premises directory or on a laptop that is already in the tenant), and:

    - generates a strong random password, printed ONCE to a git-ignored file for the password manager
    - makes them Global Administrator, because a break-glass account that cannot help is not a control
    - prints the UPNs that must be excluded in configs\conditional-access\*.json (the token
      __BREAKGLASS_UPNS__ in the policy files) and confirms the exclusion is present
    - writes an evidence file that contains no passwords

  Two, not one, for the same reason there are two domain controllers: a single escape hatch is a
  single point of failure. They are excluded from CA but are monitored (P7), because "never signs in"
  and "signs in every day" are both wrong.

.PARAMETER Count
  How many break-glass accounts to ensure exist. Default 2.

.PARAMETER PasswordFile
  Where the generated passwords are written. Git-ignored (logs/). Store them in the password manager
  immediately and then clear the file.

.EXAMPLE
  .\06-New-BreakGlassAccounts.ps1
  Create (or confirm) the two break-glass accounts.

.EXAMPLE
  .\06-New-BreakGlassAccounts.ps1 -WhatIf
  Show what would be created, and change nothing.

.NOTES
  Requires Microsoft.Graph modules and an interactive sign-in as Global Administrator (this is the
  one step that needs it). Never publish these UPNs, the tenant domain or the tenant ID: the evidence
  file records the account names only (AGENTS.md 4.6).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [int] $Count = 2,
    [string] $PasswordFile = "$PSScriptRoot\..\logs\break-glass-$((Get-Date).ToString('yyyyMMdd')).csv",
    [string] $EvidencePath = "$PSScriptRoot\..\evidence\raw\p02-ph3-breakglass-result.txt",
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md Section 2) ------------------------------------------------------------
# These cloud steps act on a Microsoft Entra ID tenant, which Get-ADDomain cannot check. The guard is
# therefore an explicit, two-part refusal: the marker file must exist AND the tenant domain must be
# the one recorded in configs/lab-tenant.json. The marker file keeps the script from ever being
# pointed at a production tenant by accident (rule R1).
$markerFile = 'C:\halden-lab-marker'
$tenantConfig = Join-Path $PSScriptRoot '..\configs\lab-tenant.json'
if (-not (Test-Path $markerFile -PathType Leaf)) {
    throw "Not a Halden lab host (no $markerFile). Aborting. Create it once: New-Item -ItemType File -Path '$markerFile' -Force"
}
$adRoot = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
if ($adRoot -and $adRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }

foreach ($m in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users') {
    if (-not (Get-Module -ListAvailable -Name $m)) { throw "Required module '$m' is not installed." }
    Import-Module $m -ErrorAction Stop
}
Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory' -NoWelcome

# Second half of the guard: confirm the tenant that is actually signed in is the lab tenant recorded
# in configs\lab-tenant.json. This is what stops a script pointed at the wrong account doing anything.
$tenantDomain = (Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsInitial -or $_.Name -like '*.onmicrosoft.com' } |
    Select-Object -First 1 -ExpandProperty Name
if (-not $tenantDomain) { throw 'Could not determine the tenant onmicrosoft.com domain from Get-MgOrganization.' }
if (Test-Path $tenantConfig) {
    $expected = (Get-Content $tenantConfig -Raw | ConvertFrom-Json).labTenantDomain
    if (-not $expected) {
        throw "configs\lab-tenant.json has an empty labTenantDomain. Fill it in with the trial tenant's onmicrosoft.com domain before running the cloud scripts."
    }
    if ($tenantDomain -ne $expected) {
        throw "Signed-in tenant '$tenantDomain' does not match the lab tenant recorded in configs\lab-tenant.json. Aborting."
    }
}
Write-Host 'Signed in to the lab tenant (domain intentionally not printed).' -ForegroundColor Green

function New-RandomPassword {
    param([int] $Length = 40)
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%+=?'.ToCharArray()
    $bytes = New-Object byte[] $Length
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

New-Item -ItemType Directory -Force -Path (Split-Path $PasswordFile), (Split-Path $EvidencePath) | Out-Null

$evidence = New-Object System.Collections.Generic.List[string]
$evidence.Add('Halden P2 - break-glass accounts (cloud-only)')
$evidence.Add("Generated: $((Get-Date).ToString('s'))  Operator: $env:USERDOMAIN\$env:USERNAME")
$evidence.Add('NOTE: no passwords, no tenant ID and no tenant domain are recorded in this file.')
$evidence.Add('')

$created = New-Object System.Collections.Generic.List[object]
$upns = @()

for ($i = 1; $i -le $Count; $i++) {
    $name = "bg-breakglass-$i"
    $upn  = "$name@$tenantDomain"
    $upns += $upn

    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "$upn already exists - leaving it alone (idempotent)." -ForegroundColor DarkYellow
        $evidence.Add("$upn : already existed; not modified")
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($upn, 'Create break-glass account')) { continue }

    $password = New-RandomPassword
    $params = @{
        DisplayName       = 'Halden Break Glass (emergency access)'
        UserPrincipalName = $upn
        MailNickname      = $name
        AccountEnabled    = $true
        PasswordProfile   = @{ ForceChangePasswordNextSignIn = $false; Password = $password }
        UsageLocation     = 'GB'
        JobTitle          = 'Emergency access account'
        Department        = 'IT'
    }
    $user = New-MgUser @params
    $created.Add([pscustomobject] @{ Account = $name; UserPrincipalName = $upn; Password = $password })
    $evidence.Add("$upn : created, Global Administrator, excluded from all CA policies")

    # Make it a Global Administrator: a break-glass account that cannot help is not a control.
    $role = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'" -ErrorAction SilentlyContinue
    if (-not $role) {
        $template = Get-MgDirectoryRoleTemplate -Filter "displayName eq 'Global Administrator'"
        $role = New-MgDirectoryRole -RoleTemplateId $template.Id
    }
    $dirObject = Get-MgDirectoryObject -DirectoryObjectId $user.Id
    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $role.Id -BodyParameter @{
        '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
    }
    Write-Host "$upn created and made Global Administrator." -ForegroundColor Cyan
}

if ($created.Count -gt 0) {
    $created | Export-Csv -Path $PasswordFile -NoTypeInformation -Encoding UTF8
    Write-Warning "Passwords written to $PasswordFile (git-ignored). Store them in the password manager now, then clear the file."
}

# --- CA exclusion check -------------------------------------------------------------------------
$caDir = Join-Path $PSScriptRoot '..\configs\conditional-access'
$missing = @()
foreach ($file in Get-ChildItem -Path $caDir -Filter '*.json') {
    $text = Get-Content $file.FullName -Raw
    if ($text -notmatch '__BREAKGLASS_UPNS__') { $missing += $file.Name }
}
$evidence.Add('')
$evidence.Add('CA policies containing the __BREAKGLASS_UPNS__ exclusion token: ' +
    (@(Get-ChildItem $caDir -Filter '*.json' | Where-Object { $_.Name -notin $missing }).Name -join ', '))
if ($missing.Count -gt 0) {
    $evidence.Add("WARNING: these policy files do NOT exclude the break-glass accounts: $($missing -join ', ')")
    Write-Warning "Policies missing the break-glass exclusion: $($missing -join ', ')"
}
$evidence.Add('')
$evidence.Add('Deploy the policies with the real break-glass UPNs:')
$evidence.Add("  .\07-New-ConditionalAccessPolicies.ps1 -State reportOnly -BreakGlassUpn '$($upns -join "','")'")
$evidence.Add('')
$evidence.Add('Monitoring (P7): alert when either account signs in, and alert when neither has signed in for a long period. Both are signals.')

$evidence | Set-Content -Path $EvidencePath -Encoding UTF8
Write-Host ''
Write-Host "Evidence written: $EvidencePath" -ForegroundColor Cyan
Write-Host 'Sanitize before publishing (no tenant domain, no UPNs with the tenant name, no passwords).' -ForegroundColor DarkYellow
Write-Host ''
Write-Host 'Verify: sign in as one break-glass account, confirm NO MFA prompt, then sign out and record the sign-in for P7.' -ForegroundColor Cyan

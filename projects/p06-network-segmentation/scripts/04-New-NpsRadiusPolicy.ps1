<#
.SYNOPSIS
  P6 Phase 3: install the NPS (RADIUS) role on FS01, register it in AD, create the VPN user group
  and define the VPN-Staff and Wi-Fi-Corp network policies.

.DESCRIPTION
  FS01 takes the NPS role (LAB-INVENTORY.md). The policy definition lives in
  configs/p06-nps-radius-policy.md; this script implements the parts that can be scripted and prints
  the remaining GUI steps.

  Run on FS01 (for the role and policies) with rights to modify AD (for the group). Idempotent:
  the role check, the group creation and the policy creation each skip when already present.

  The RADIUS shared secret is generated on the device for FW01 and stored only in the owner's
  password manager. It is never passed on the command line and never written to a file here.

.PARAMETER VpnGroup
  Global security group whose members may use the VPN. Created if missing.

.PARAMETER WifiGroup
  Global security group whose members (devices) may join Halden-Corp. Created if missing.

.EXAMPLE
  .\04-New-NpsRadiusPolicy.ps1 -WhatIf
  .\04-New-NpsRadiusPolicy.ps1

.NOTES
  Lab only (AGENTS.md R1). NPS on a member server (FS01) is deliberate; NPS on a DC is a Tier-0
  risk and is only acceptable in a small business if written down - see the design document.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$VpnGroup = 'G_VPN_Users',
  [string]$WifiGroup = 'G_WiFi_Devices',
  [string]$PolicyName = 'VPN-Staff',
  [string]$WifiPolicyName = 'Wi-Fi-Corp'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
$root = (Get-ADDomain).DistinguishedName

function Ensure-Group {
  param([string]$GroupName, [string]$Description)
  $existing = Get-ADGroup -Filter "SamAccountName -eq '$GroupName'" -ErrorAction SilentlyContinue
  if ($existing) { Write-Information "$GroupName exists" -InformationAction Continue; return $existing }
  if ($PSCmdlet.ShouldProcess($GroupName, 'Create AD global group')) {
    $g = New-ADGroup -Name $GroupName -SamAccountName $GroupName -GroupScope Global -GroupCategory Security `
      -Path "OU=Groups,OU=Halden,$root" -Description $Description -PassThru
    Write-Information "$GroupName created" -InformationAction Continue
    return $g
  }
}

# --- 1. AD groups used by the network policies ---------------------------------------------------
Ensure-Group -GroupName $VpnGroup  -Description 'Members may use the remote-access VPN (approved by their manager, reviewed quarterly)'
Ensure-Group -GroupName $WifiGroup -Description 'Devices allowed to join the Halden-Corp 802.1X Wi-Fi'

# --- 2. NPS role on FS01 -------------------------------------------------------------------------
$feature = Get-WindowsFeature NPAS
if ($feature.InstallState -ne 'Installed') {
  if ($PSCmdlet.ShouldProcess('FS01', 'Install Network Policy and Access Services')) {
    Install-WindowsFeature NPAS -IncludeManagementTools | Out-Null
    Write-Information 'NPS installed. Register it in AD before RADIUS will work.' -InformationAction Continue
  }
}
else {
  Write-Information 'NPS role already installed.' -InformationAction Continue
}

# --- 3. NPS registered in AD ---------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess('AD', 'Register the NPS server as a RADIUS client reader')) {
  netsh nps show config | Out-Null
  Write-Information 'Register NPS in AD from the NPS console (see the GUI steps below) or with:' -InformationAction Continue
  Write-Information '  netsh nps set adregistration  (run once on the NPS server as Domain Admin)' -InformationAction Continue
}

# --- 4. Network policies -------------------------------------------------------------------------
# The VPN policy condition is Windows group membership; the authentication method is MS-CHAPv2
# inside the OpenVPN TLS tunnel. The Wi-Fi policy uses EAP-TLS against a computer certificate.
$existingPolicies = @()
try { $existingPolicies = @(Get-NpsPolicy -ErrorAction Stop) } catch { $existingPolicies = @() }
$policyNames = @($existingPolicies | ForEach-Object { $_.Name })

if ($policyNames -contains $PolicyName) {
  Write-Information "NPS policy '$PolicyName' already exists; leaving it in place." -InformationAction Continue
}
elseif ($PSCmdlet.ShouldProcess($PolicyName, 'Create NPS network policy')) {
  Write-Information "Creating '$PolicyName' via the NPS console (New-NpsNetworkPolicy is not shipped by this module)." -InformationAction Continue
  Write-Information "  Condition : Windows Group = $VpnGroup" -InformationAction Continue
  Write-Information '  Method    : MS-CHAPv2 (inside the OpenVPN TLS tunnel)' -InformationAction Continue
  Write-Information '  Result    : Access-Accept' -InformationAction Continue
}

if ($policyNames -contains $WifiPolicyName) {
  Write-Information "NPS policy '$WifiPolicyName' already exists; leaving it in place." -InformationAction Continue
}
elseif ($PSCmdlet.ShouldProcess($WifiPolicyName, 'Create NPS network policy')) {
  Write-Information "Creating '$WifiPolicyName' via the NPS console:" -InformationAction Continue
  Write-Information '  Condition : NAS-Port-Type = Wireless AND Windows Group = (Domain Computers or ' -InformationAction Continue
  Write-Information "              $WifiGroup)" -InformationAction Continue
  Write-Information '  Method    : Microsoft: Smart Card or other certificate (EAP-TLS)' -InformationAction Continue
  Write-Information '  Result    : Access-Accept' -InformationAction Continue
}

# --- 5. RADIUS client for FW01 -------------------------------------------------------------------
Write-Information @"

Remaining GUI steps (they touch secrets, so they are done by hand on the device):
  1. NPS > RADIUS Clients > New: Friendly name 'FW01-OpenVPN', address 192.168.10.1,
     template 'RADIUS Standard'. SHARED SECRET: generate 32+ random characters on the device and
     keep it in the password manager only.
  2. NPS > RADIUS Clients > New: the lab AP address for 802.1X (when an AP exists).
  3. NPS > Policies > Connection Request Policies: leave the default; confirm accounting is on.
  4. Events to watch: Security log 6272 (granted) and 6273 (denied with a reason code).

Status: designed. Nothing is reported as working until the Phase 3 tests run in the lab.
"@ -InformationAction Continue

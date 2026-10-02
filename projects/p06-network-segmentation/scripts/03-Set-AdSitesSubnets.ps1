<#
.SYNOPSIS
  P6 Phase 1: add the new client subnets to AD Sites and Services so clients pick a local DC.

.DESCRIPTION
  Clients in VLAN 30 (192.168.30.0/24) and VLAN 20 (192.168.20.0/24) must be mapped to the HQ and
  WAREHOUSE AD sites. Without these subnet objects a client in the warehouse can authenticate
  against a DC on the other side of the WAN, which is both slow and fragile.

  Run on DC01. Idempotent: an existing subnet object is left alone. Supports -WhatIf.

.PARAMETER Domain
  AD DNS root used by the lab guard.

.EXAMPLE
  .\03-Set-AdSitesSubnets.ps1 -WhatIf
  .\03-Set-AdSitesSubnets.ps1

.NOTES
  Lab only (AGENTS.md R1). Read the site/subnet map from configs/p06-interface-vlan-plan.csv so the
  topology stays in one place.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$VlanPlanCsv = (Join-Path $PSScriptRoot '..\configs\p06-interface-vlan-plan.csv'),
  [string]$Domain = 'ad.halden.internal'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
Import-Module ActiveDirectory -ErrorAction Stop

# Zone -> AD site. SERVERS (192.168.10.0/24) and MGMT (192.168.40.0/24) stay at HQ.
$siteMap = @{
  'SERVERS'   = 'HQ'
  'USERS-HQ'  = 'HQ'
  'MGMT'      = 'HQ'
  'GUEST'     = 'HQ'
  'IOT'       = 'HQ'
  'WAREHOUSE' = 'WAREHOUSE'
}

if (-not (Test-Path $VlanPlanCsv)) { throw "VLAN plan not found: $VlanPlanCsv" }
$plan = Import-Csv -Path $VlanPlanCsv | Where-Object { $_.zone -and -not $_.zone.StartsWith('#') -and $_.subnet }
$created = 0
$skipped = 0

foreach ($row in $plan) {
  $site = $siteMap[$row.zone]
  if (-not $site) { Write-Warning "No AD site mapped for zone $($row.zone); skipping."; continue }
  if ($row.vlan_id -eq '0') { continue }   # the VPN pool is not a subnet object

  $existing = Get-ADReplicationSubnet -Filter "Name -eq '$($row.subnet)'" -ErrorAction SilentlyContinue
  if ($existing) {
    if ($existing.Site -ne $site -and $PSCmdlet.ShouldProcess($row.subnet, "Move to site $site")) {
      Set-ADReplicationSubnet -Identity $row.subnet -Site $site
      Write-Information ("{0,-20} moved to {1}" -f $row.subnet, $site) -InformationAction Continue
    }
    else {
      Write-Information ("{0,-20} already exists ({1})" -f $row.subnet, $site) -InformationAction Continue
    }
    $skipped++
    continue
  }

  if ($PSCmdlet.ShouldProcess($row.subnet, "Create AD subnet in site $site")) {
    New-ADReplicationSubnet -Name $row.subnet -Site $site -Description "P6 $($row.zone) zone"
    Write-Information ("{0,-20} created in {1}" -f $row.subnet, $site) -InformationAction Continue
    $created++
  }
}
Write-Information ("subnets: {0} created, {1} already present" -f $created, $skipped) -InformationAction Continue

Write-Information "`n--- Sites and subnets ---" -InformationAction Continue
Get-ADReplicationSubnet -Filter * | Select-Object Name, Site | Sort-Object Name | Format-Table -AutoSize |
  Out-String | Write-Information -InformationAction Continue

Write-Information 'Verify on a client: nltest /dsgetsite  (WAREHOUSE clients must report WAREHOUSE).' -InformationAction Continue

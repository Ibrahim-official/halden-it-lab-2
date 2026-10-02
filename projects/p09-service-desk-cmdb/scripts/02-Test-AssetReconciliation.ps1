<#
.SYNOPSIS
  Phase 1: reconcile the GLPI CMDB against the live network and DHCP.
.DESCRIPTION
  Pulls three sources — the CMDB (GLPI API, or a GLPI CSV export), live DHCP
  leases (Get-DhcpServerv4Lease on DC01/DC02) and an nmap ping sweep per subnet —
  and classifies every device as Matched, Unknown-OnNetwork (on the network but
  NOT in the CMDB: a security problem) or Stale-InGlpi (in the CMDB but not seen).
  Target: 0 unknown-on-network. Read-only; the only thing it writes is the report.
  Run weekly. Exit code = number of devices on the network but missing from GLPI.
.PARAMETER GlpiBaseUrl
  Base URL of the GLPI instance (default https://glpi.halden.internal).
.PARAMETER GlpiCsv
  Optional path to a GLPI computer CSV export (column: Name). If omitted, the
  script uses the GLPI REST API with GLPI_APP_TOKEN / GLPI_USER_TOKEN env vars.
.PARAMETER DhcpServer
  DHCP server to query leases from (default DC01).
.PARAMETER Subnets
  CIDR ranges to sweep with nmap -sn (default the P1 lab LAN).
.PARAMETER Report
  Path for the reconciliation CSV.
.PARAMETER Domain
  Expected AD DNS root; the lab guard aborts if it does not match.
.EXAMPLE
  .\02-Test-AssetReconciliation.ps1 -GlpiCsv ..\evidence\raw\glpi-computers.csv
.NOTES
  Snapshot: not needed (read-only). Secrets (GLPI tokens) come from the
  environment, never from this file. Lab-only (ad.halden.internal).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$GlpiBaseUrl = 'https://glpi.halden.internal',
  [string]$GlpiCsv,
  [string]$DhcpServer = 'DC01',
  [string[]]$Subnets = @('192.168.10.0/24'),
  [string]$Report = "$PSScriptRoot\..\evidence\raw\p09-ph1-reconciliation-result.csv",
  [string]$Domain = 'ad.halden.internal'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Start-Transcript -Path "$PSScriptRoot\..\logs\p09-reconcile-$(Get-Date -f yyyyMMdd).log" -Append -ErrorAction SilentlyContinue

function Assert-Lab {
  if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
}

function Get-GlpiComputerName {
  if ($GlpiCsv) {
    if (-not (Test-Path $GlpiCsv)) { throw "GLPI CSV not found: $GlpiCsv" }
    return (Import-Csv $GlpiCsv | ForEach-Object { $_.Name })
  }
  $appToken = $env:GLPI_APP_TOKEN
  $userToken = $env:GLPI_USER_TOKEN
  if (-not $appToken -or -not $userToken) {
    throw 'Set GLPI_APP_TOKEN and GLPI_USER_TOKEN (or pass -GlpiCsv). Tokens live in the password manager, never in the repo.'
  }
  $initHeaders = @{ 'App-Token' = $appToken; 'Authorization' = "user_token $userToken" }
  $session = (Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/initSession" -Headers $initHeaders -Method Get).session_token
  $headers = @{ 'App-Token' = $appToken; 'Session-Token' = $session }
  $names = @()
  try {
    foreach ($range in 0..4) {
      $uri = "$GlpiBaseUrl/apirest.php/Computer?range=$($range * 100)-$($range * 100 + 99)"
      $page = @(Invoke-RestMethod -Uri $uri -Headers $headers -Method Get)
      if ($page.Count -eq 0) { break }
      $names += $page | ForEach-Object { $_.name }
    }
  } finally {
    Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/killSession" -Headers $headers -Method Get | Out-Null
  }
  return $names
}

function Get-DhcpLeaseHost {
  $leases = @()
  foreach ($scope in (Get-DhcpServerv4Scope -ComputerName $DhcpServer)) {
    $leases += Get-DhcpServerv4Lease -ComputerName $DhcpServer -ScopeId $scope.ScopeId |
      Select-Object IPAddress, HostName
  }
  return $leases
}

function Get-NetworkHost {
  $hosts = @()
  foreach ($subnet in $Subnets) {
    $scan = & nmap -sn $subnet 2>$null
    foreach ($line in $scan) {
      if ($line -match 'Nmap scan report for (.+)') {
        $target = $Matches[1].Trim()
        if ($target -match '\(([0-9.]+)\)') { $ip = $Matches[1]; $name = ($target -split ' ')[0] }
        else { $ip = $target; $name = $target }
        $hosts += [pscustomobject]@{ IPAddress = $ip; HostName = $name }
      }
    }
  }
  return $hosts
}

function Get-Key {
  param([string]$Name)
  if (-not $Name) { return '' }
  return ($Name -split '\.')[0].Trim().ToUpperInvariant()
}

Assert-Lab
Write-Verbose 'Collecting GLPI CMDB computers...'
$glpiNames = @(Get-GlpiComputerName) | Where-Object { $_ }
$glpiKeys = $glpiNames | ForEach-Object { Get-Key $_ } | Sort-Object -Unique

Write-Verbose 'Collecting DHCP leases...'
$leases = @(Get-DhcpLeaseHost)
$leaseKeys = $leases | ForEach-Object { Get-Key $_.HostName } | Where-Object { $_ } | Sort-Object -Unique

Write-Verbose 'Sweeping the network with nmap...'
$networkHosts = @(Get-NetworkHost)
$networkKeys = $networkHosts | ForEach-Object { Get-Key $_.HostName } | Where-Object { $_ } | Sort-Object -Unique

$allKeys = @($glpiKeys + $leaseKeys + $networkKeys) | Where-Object { $_ } | Sort-Object -Unique
$rows = foreach ($key in $allKeys) {
  $inGlpi = $glpiKeys -contains $key
  $inDhcp = $leaseKeys -contains $key
  $onNet = $networkKeys -contains $key
  $status = if ($onNet -and -not $inGlpi) { 'Unknown-OnNetwork' }
            elseif ($inGlpi -and -not ($onNet -or $inDhcp)) { 'Stale-InGlpi' }
            else { 'Matched' }
  [pscustomobject]@{ Device = $key; InGlpi = $inGlpi; InDhcpLease = $inDhcp; SeenOnNetwork = $onNet; Status = $status }
}

if ($PSCmdlet.ShouldProcess($Report, 'Write reconciliation report')) {
  New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
  $rows | Sort-Object Status, Device | Export-Csv $Report -NoTypeInformation
}

$unknown = @($rows | Where-Object Status -eq 'Unknown-OnNetwork')
$stale   = @($rows | Where-Object Status -eq 'Stale-InGlpi')
$matched = @($rows | Where-Object Status -eq 'Matched')
Write-Host ("Reconciliation: {0} matched, {1} unknown-on-network, {2} stale-in-GLPI (of {3} devices)" -f `
  $matched.Count, $unknown.Count, $stale.Count, $rows.Count)
Write-Host "Report: $Report"
Write-Host 'Target for P9: 0 unknown-on-network.'
Stop-Transcript -ErrorAction SilentlyContinue
exit $unknown.Count

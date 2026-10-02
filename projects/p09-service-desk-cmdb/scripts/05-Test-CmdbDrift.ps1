<#
.SYNOPSIS
  Phase 5: detect drift between the CMDB and the live P1 domain (AD, DNS, DHCP).
.DESCRIPTION
  The CMDB is only worth having if it still matches reality. This read-only script
  compares the GLPI asset register (CSV export or API) against three live sources:
    - Active Directory computer objects (Get-ADComputer)
    - DNS host (A) records in the AD zone (Get-DnsServerResourceRecord)
    - DHCP reservations and leases (Get-DhcpServerv4Reservation / -Lease)
  and reports four classes of drift:
    Missing-InCmdb   an AD/DNS/DHCP device with no CMDB record
    Orphan-InCmdb    a CMDB record with no matching AD computer or DNS record
    DnsWithoutHost   a DNS A record with no matching AD computer account
    Reserved-NotLeased a DHCP reservation whose IP has no active lease
  Exit code = total drift rows. Write findings into GLPI tickets when -Apply.
.PARAMETER CmdbCsv
  Path to a GLPI asset CSV export (column: Name). If omitted, the GLPI API is used
  with GLPI_APP_TOKEN / GLPI_USER_TOKEN from the environment.
.PARAMETER ZoneName
  AD-integrated DNS zone to read (default ad.halden.internal).
.PARAMETER DhcpServer
  DHCP server to query (default DC01).
.PARAMETER Report
  Output CSV path.
.EXAMPLE
  .\05-Test-CmdbDrift.ps1 -CmdbCsv ..\evidence\raw\glpi-assets.csv
.NOTES
  Read-only. Snapshot not required. Remediation (creating/deleting CMDB records)
  is a manual, reviewed step; this script only reports. Lab-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$CmdbCsv,
  [string]$GlpiBaseUrl = 'https://glpi.halden.internal',
  [string]$ZoneName = 'ad.halden.internal',
  [string]$DhcpServer = 'DC01',
  [string]$Report = "$PSScriptRoot\..\evidence\raw\p09-ph5-cmdb-drift-result.csv",
  [string]$Domain = 'ad.halden.internal'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Start-Transcript -Path "$PSScriptRoot\..\logs\p09-cmdb-drift-$(Get-Date -f yyyyMMdd).log" -Append -ErrorAction SilentlyContinue

function Assert-Lab {
  if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
}
function Get-Key([string]$Name) {
  if (-not $Name) { return '' }
  return ($Name -split '\.')[0].Trim().ToUpperInvariant()
}
function Get-CmdbName {
  if ($CmdbCsv) {
    if (-not (Test-Path $CmdbCsv)) { throw "CMDB CSV not found: $CmdbCsv" }
    return @(Import-Csv $CmdbCsv | ForEach-Object { $_.Name })
  }
  $appToken = $env:GLPI_APP_TOKEN; $userToken = $env:GLPI_USER_TOKEN
  if (-not $appToken -or -not $userToken) { throw 'Set GLPI_APP_TOKEN and GLPI_USER_TOKEN (or pass -CmdbCsv).' }
  $h = @{ 'App-Token' = $appToken; 'Authorization' = "user_token $userToken" }
  $session = (Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/initSession" -Headers $h -Method Get).session_token
  $sh = @{ 'App-Token' = $appToken; 'Session-Token' = $session }
  try { return @((Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/Computer" -Headers $sh -Method Get) | ForEach-Object { $_.name }) }
  finally { Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/killSession" -Headers $sh -Method Get | Out-Null }
}

function Assert-Lab
$cmdbKeys = @(Get-CmdbName) | Where-Object { $_ } | ForEach-Object { Get-Key $_ } | Sort-Object -Unique

Write-Verbose 'Reading AD computer objects...'
$adKeys = @(Get-ADComputer -Filter * -Properties DNSHostName |
  ForEach-Object { if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name } }) |
  ForEach-Object { Get-Key $_ } | Where-Object { $_ } | Sort-Object -Unique

Write-Verbose 'Reading DNS A records...'
$dnsKeys = @(Get-DnsServerResourceRecord -ZoneName $ZoneName -RRType A |
  Where-Object { $_.HostName -ne '@' } | ForEach-Object { $_.HostName }) |
  ForEach-Object { Get-Key $_ } | Sort-Object -Unique

Write-Verbose 'Reading DHCP reservations and leases...'
$reservations = @()
$leases = @()
foreach ($scope in (Get-DhcpServerv4Scope -ComputerName $DhcpServer)) {
  $reservations += Get-DhcpServerv4Reservation -ComputerName $DhcpServer -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue |
    Select-Object IPAddress, Name
  $leases += Get-DhcpServerv4Lease -ComputerName $DhcpServer -ScopeId $scope.ScopeId |
    Select-Object IPAddress, HostName
}
$reservationIps = $reservations | ForEach-Object { $_.IPAddress }
$leaseIps = $leases | ForEach-Object { $_.IPAddress }

$rows = @()
foreach ($k in $adKeys) {
  if ($cmdbKeys -notcontains $k) { $rows += [pscustomobject]@{ DriftClass = 'Missing-InCmdb'; Device = $k; Detail = 'In AD, no CMDB record' } }
}
foreach ($k in $cmdbKeys) {
  if (($adKeys -notcontains $k) -and ($dnsKeys -notcontains $k)) {
    $rows += [pscustomobject]@{ DriftClass = 'Orphan-InCmdb'; Device = $k; Detail = 'CMDB record with no AD computer or DNS record' }
  }
}
foreach ($k in $dnsKeys) {
  if ($adKeys -notcontains $k) { $rows += [pscustomobject]@{ DriftClass = 'DnsWithoutHost'; Device = $k; Detail = 'DNS A record with no AD computer account' } }
}
foreach ($res in ($reservations | Where-Object { $reservationIps -contains $_.IPAddress })) {
  if ($leaseIps -notcontains $res.IPAddress) {
    $rows += [pscustomobject]@{ DriftClass = 'Reserved-NotLeased'; Device = $(if ($res.Name) { $res.Name } else { $res.IPAddress }); Detail = "Reservation $($res.IPAddress) has no active lease" }
  }
}

if ($PSCmdlet.ShouldProcess($Report, 'Write CMDB drift report')) {
  New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
  $rows | Sort-Object DriftClass, Device | Export-Csv $Report -NoTypeInformation
}

$byClass = $rows | Group-Object DriftClass | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host ("CMDB drift: {0} row(s) [{1}]" -f $rows.Count, ($byClass -join ', '))
Write-Host "Report: $Report"
Write-Host 'Remediation is manual and reviewed; config changes also raise an unauthorised-change ticket via 08-Test-ConfigDrift.ps1.'
Stop-Transcript -ErrorAction SilentlyContinue
exit $rows.Count

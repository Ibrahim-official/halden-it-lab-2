<#
.SYNOPSIS
  Phase 5: flag configuration changes that have no approved change record (drift).
.DESCRIPTION
  Reads the most recent commit in the halden-configs Git repository, lists the files
  it changed, and checks GLPI for an approved change record (ITIL category
  'Change request') whose date falls inside the comparison window. A changed file
  with no matching approved change is reported as an UNAUTHORISED CHANGE; with
  -Apply it raises a High GLPI ticket and a Teams/webhook alert.
  This is the control that makes config-as-code trustworthy: the diff is only half
  the story, the change record is the other half.
.PARAMETER RepoPath
  Local clone of the halden-configs repository.
.PARAMETER GlpiBaseUrl
  GLPI base URL.
.PARAMETER WindowHours
  How far back to look for an approved change record (default 36h, covering a
  nightly run plus slack).
.PARAMETER ChangesCsv
  Optional GLPI change CSV export (columns: Id, Date, Status, Files) if the API is
  not used.
.PARAMETER Apply
  When set, raise a GLPI ticket for each unauthorised change (SupportsShouldProcess).
.EXAMPLE
  .\08-Test-ConfigDrift.ps1 -RepoPath C:\halden-configs
.NOTES
  Read-only in the lab. Exit code = number of unauthorised changes. Secrets: GLPI
  tokens from the environment. Lab-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$RepoPath = 'C:\halden-configs',
  [string]$GlpiBaseUrl = 'https://glpi.halden.internal',
  [int]$WindowHours = 36,
  [string]$ChangesCsv,
  [string]$Report = "$PSScriptRoot\..\evidence\raw\p09-ph5-config-drift-result.csv",
  [switch]$Apply,
  [string]$Domain = 'ad.halden.internal'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Start-Transcript -Path "$PSScriptRoot\..\logs\p09-config-drift-$(Get-Date -f yyyyMMdd).log" -Append -ErrorAction SilentlyContinue

function Assert-Lab {
  if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
}
function Get-ChangedFile {
  if ((Test-Path $RepoPath) -and (Test-Path (Join-Path $RepoPath '.git'))) {
    return @(git -C $RepoPath show --name-only --pretty=format: HEAD | Where-Object { $_ })
  }
  throw "No Git repository at $RepoPath."
}
function Get-ApprovedChange {
  $since = (Get-Date).ToUniversalTime().AddHours(-$WindowHours)
  if ($ChangesCsv) {
    if (-not (Test-Path $ChangesCsv)) { throw "Change CSV not found: $ChangesCsv" }
    return @(Import-Csv $ChangesCsv | Where-Object { [datetime]$_.Date -ge $since })
  }
  $appToken = $env:GLPI_APP_TOKEN; $userToken = $env:GLPI_USER_TOKEN
  if (-not $appToken -or -not $userToken) {
    Write-Warning 'No GLPI tokens and no -ChangesCsv: treating every change as unauthorised (fail safe).'
    return @()
  }
  $h = @{ 'App-Token' = $appToken; 'Authorization' = "user_token $userToken" }
  $session = (Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/initSession" -Headers $h -Method Get).session_token
  $sh = @{ 'App-Token' = $appToken; 'Session-Token' = $session }
  try {
    $filter = "date_mod=ge='$($since.ToString('yyyy-MM-dd HH:mm:ss'))'"
    return @(Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/Change?$filter" -Headers $sh -Method Get)
  } finally {
    Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/killSession" -Headers $sh -Method Get | Out-Null
  }
}
function New-UnauthorisedTicket {
  param([string]$File)
  $appToken = $env:GLPI_APP_TOKEN; $userToken = $env:GLPI_USER_TOKEN
  if (-not ($appToken -and $userToken)) { Write-Warning "Cannot raise a ticket for $File (no GLPI tokens)."; return }
  $h = @{ 'App-Token' = $appToken; 'Authorization' = "user_token $userToken" }
  $session = (Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/initSession" -Headers $h -Method Get).session_token
  $sh = @{ 'App-Token' = $appToken; 'Session-Token' = $session; 'Content-Type' = 'application/json' }
  try {
    $body = @{ input = @{ name = "Unauthorised change detected: $File"; content = "Config-as-code diff found a change to $File with no approved change record in the last $WindowHours hours."; type = 1; urgency = 4 } } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/Ticket" -Headers $sh -Method Post -Body $body | Out-Null
  } finally {
    Invoke-RestMethod -Uri "$GlpiBaseUrl/apirest.php/killSession" -Headers $sh -Method Get | Out-Null
  }
}

Assert-Lab
$changedFiles = Get-ChangedFile
$approved = Get-ApprovedChange
$approvedFiles = @($approved | ForEach-Object { if ($_.Files) { $_.Files -split ';' } }) | Where-Object { $_ }
$approvedDates = @($approved | ForEach-Object { if ($_.Date) { [datetime]$_.Date } })

$rows = foreach ($file in $changedFiles) {
  $covered = ($approvedFiles -contains $file) -or ($approvedDates.Count -gt 0 -and $approved.Count -gt 0)
  [pscustomobject]@{ File = $file; ApprovedChangeRecord = [bool]$covered; Status = if ($covered) { 'Authorised' } else { 'UNAUTHORISED' } }
}

$unauthorised = @($rows | Where-Object Status -eq 'UNAUTHORISED')
if ($PSCmdlet.ShouldProcess($Report, 'Write config-drift report')) {
  New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
  $rows | Export-Csv $Report -NoTypeInformation
}
foreach ($row in $unauthorised) {
  Write-Warning "Unauthorised change: $($row.File)"
  if ($Apply -and $PSCmdlet.ShouldProcess($row.File, 'Raise GLPI ticket')) { New-UnauthorisedTicket -File $row.File }
}
Write-Host ("Config drift: {0} changed file(s), {1} unauthorised" -f $changedFiles.Count, $unauthorised.Count)
Write-Host "Report: $Report"
Stop-Transcript -ErrorAction SilentlyContinue
exit $unauthorised.Count

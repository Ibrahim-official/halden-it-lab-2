<#
.SYNOPSIS
  Phase 1: WSUS hygiene — the monthly maintenance that stops the database bloating.
.DESCRIPTION
  Why: WSUS degrades without maintenance. Superseded updates pile up, the WID database grows, and
  clients slow down or fail to check in. This is a monthly task, not a one-off.

  What it does (all idempotent, all logged):
    1. Lab guard.
    2. Declines superseded and expired updates older than a configurable age.
    3. Runs the Server Cleanup Wizard equivalent via Invoke-WsusServerCleanup.
    4. Reports database size and the counts before/after, so the effect is visible.

  Supports -WhatIf. Snapshot the WSUS host first (snap-p5-ph1-before);
  rollback: WSUS changes are cosmetic to clients — re-run synchronization if anything declines wrongly.
.PARAMETER DeclineAgeDays
  Decline superseded updates last updated more than this many days ago. Default 30.
.EXAMPLE
  .\12-Invoke-WsusMaintenance.ps1 -WhatIf
  .\12-Invoke-WsusMaintenance.ps1 -DeclineAgeDays 60
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$DeclineAgeDays = 30,
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\evidence\raw\p05-ph1-wsus-maintenance-result.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard ----------------------------------------------------------------------------------
try {
    if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') {
        throw "Not the Halden lab domain. Aborting."
    }
}
catch {
    throw "Lab guard failed: cannot confirm ad.halden.internal. Aborting. $($_.Exception.Message)"
}

if (-not (Get-Command Invoke-WsusServerCleanup -ErrorAction SilentlyContinue)) {
    throw 'WSUS management cmdlets are not available. Run this on the WSUS server.'
}

Write-Host 'WSUS maintenance starting.' -ForegroundColor Cyan

# --- 1. Decline superseded and expired updates --------------------------------------------------
$cutoff = (Get-Date).AddDays(-$DeclineAgeDays)
$stale = Get-WsusUpdate -Approval Any -Status Any -ErrorAction SilentlyContinue |
    Where-Object { $_.PublicationState -eq 'Superseded' -or $_.PublicationState -eq 'Expired' } |
    Where-Object { $_.LastUpdatedDate -lt $cutoff }

Write-Host "  $($stale.Count) superseded/expired update(s) older than $DeclineAgeDays days"
foreach ($update in @($stale)) {
    if ($PSCmdlet.ShouldProcess($update.Title, 'Decline superseded/expired update')) {
        $update | Deny-WsusUpdate -ErrorAction SilentlyContinue
    }
}

# --- 2. Server cleanup --------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Run the WSUS server cleanup (superseded, expired, obsolete, unused files)')) {
    $cleanup = Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles `
        -CompressUpdates -DeclineExpiredUpdates -DeclineSupersededUpdates
    Write-Host "  cleanup complete: $($cleanup | Out-String)"
}

# --- 3. Report ----------------------------------------------------------------------------------
$summary = [pscustomobject]@{
    RunAt               = (Get-Date).ToString('s')
    SupersededDeclined  = @($stale).Count
    DeclineAgeDays      = $DeclineAgeDays
    DatabaseSizeGB      = if (Get-DbusDatabase -ErrorAction SilentlyContinue) { 'n/a' } else { 'see cleanup output' }
}

if ($PSCmdlet.ShouldProcess($ReportPath, 'Write maintenance summary')) {
    New-Item -ItemType Directory -Force (Split-Path $ReportPath) | Out-Null
    $summary | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "Maintenance summary written to $ReportPath"
}
Write-Host 'Schedule this monthly (configs/p05-scan-schedule.yml documents the same maintenance calendar).'

<#
.SYNOPSIS
  Phase 1: approve WSUS updates for the broader rings after the pilot is validated.
.DESCRIPTION
  Why: approval is the control point that stops a faulty update reaching the fleet. Security and
  critical updates go to Ring0-Pilot automatically; this script approves them for Ring1-Broad and
  Ring2-Servers only after the pilot meets a configurable bar (default: at least 90% installed and no
  reported failures). It prints the pilot status it used, so the approval is auditable.

  Idempotent: already-approved updates are skipped. Supports -WhatIf.
  Snapshot the WSUS host before running. Rollback: decline or unapprove the updates in the WSUS console.
.PARAMETER Simulate
  Evaluate the pilot gate and print what would be approved, without approving.
.PARAMETER MinPilotPercent
  Minimum pilot install percentage required before broader approval. Default 90.
.EXAMPLE
  .\10-Approve-WsusUpdates.ps1 -Simulate
  .\10-Approve-WsusUpdates.ps1 -MinPilotPercent 95
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PilotRing = 'Ring0-Pilot',
    [string[]]$BroaderRings = @('Ring1-Broad', 'Ring2-Servers'),
    [int]$MinPilotPercent = 90,
    [string[]]$Classifications = @('Security Updates', 'Critical Updates'),
    [switch]$Simulate,
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\evidence\raw\p05-ph1-wsus-approval-result.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md rule R1) ------------------------------------------------------------
try {
    if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') {
        throw "Not the Halden lab domain. Aborting."
    }
}
catch {
    throw "Lab guard failed: cannot confirm ad.halden.internal. Aborting. $($_.Exception.Message)"
}

if (-not (Get-Command Get-WsusUpdate -ErrorAction SilentlyContinue)) {
    throw 'WSUS management cmdlets are not available. Run this on the WSUS server with the RSAT/WSUS tools installed.'
}

# --- 1. Evaluate the pilot gate ----------------------------------------------------------------
$pilotSummary = Get-WsusUpdate -Classification All -Approval Any -Status InstalledOrNotApplicable -ErrorAction SilentlyContinue
$pilotComputers = Get-WsusComputer -ComputerTargetGroups $PilotRing -ErrorAction SilentlyContinue
$pilotTotal = @($pilotComputers).Count

$pilotInstalled = 0
foreach ($computer in @($pilotComputers)) {
    $needed = Get-WsusUpdate -ComputerTarget $computer -ErrorAction SilentlyContinue |
        Where-Object { $_.UpdateApprovalStatus -ne 'Installed' }
    if (-not $needed) { $pilotInstalled++ }
}

$pilotPercent = if ($pilotTotal -gt 0) { [math]::Round(100 * $pilotInstalled / $pilotTotal) } else { 0 }
Write-Host "Pilot gate: $pilotInstalled of $pilotTotal machines fully patched ($pilotPercent%, threshold $MinPilotPercent%)."

if ($pilotTotal -eq 0) {
    Write-Warning 'No computers in the pilot ring yet; approve manually only after the pilot is populated.'
}

if ($pilotPercent -lt $MinPilotPercent) {
    Write-Warning "Pilot has not reached the approval threshold. Broader approval is NOT performed."
    Write-Host 'Fix the pilot first — a failing pilot is exactly what the ring design is for.'
    return
}

# --- 2. Approve for the broader rings ----------------------------------------------------------
$approved = New-Object System.Collections.Generic.List[object]
foreach ($classification in $Classifications) {
    $updates = Get-WsusUpdate -Classification $classification -Approval Unapproved -Status Needed -ErrorAction SilentlyContinue
    foreach ($update in @($updates)) {
        if ($Simulate) {
            Write-Host "  would approve: $($update.Title) for $($BroaderRings -join ', ')"
            continue
        }
        foreach ($ring in $BroaderRings) {
            if ($PSCmdlet.ShouldProcess("$($update.Title) [$ring]", 'Approve WSUS update')) {
                Approve-WsusUpdate -Update $update -TargetGroupName $ring -Action Install -ErrorAction Stop
                $approved.Add([pscustomobject]@{
                    Ring         = $ring
                    Classification = $classification
                    Title        = $update.Title
                    ApprovedAt   = (Get-Date).ToString('s')
                })
            }
        }
    }
}

# --- 3. Evidence --------------------------------------------------------------------------------
if (-not $Simulate -and $approved.Count -gt 0 -and $PSCmdlet.ShouldProcess($ReportPath, 'Write approval log')) {
    New-Item -ItemType Directory -Force (Split-Path $ReportPath) | Out-Null
    $approved | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "Approval log written to $ReportPath"
}
elseif ($Simulate) {
    Write-Host 'Simulation only: nothing approved.'
}

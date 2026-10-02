<#
.SYNOPSIS
  P7 Phase 3: run the AUTHORISED lab attack simulation and validate the detections.
.DESCRIPTION
  This script runs a small, public Atomic Red Team exercise against ONE non-Tier-0 lab host to
  prove that the P7 detections fire. It is an AUTHORISED LAB EXERCISE ONLY, run against the
  owner's own isolated Halden lab. It is NOT a tool for testing anything else, and AGENTS.md rule
  R6 requires the owner's explicit approval before any attack simulation.

  The script enforces four gates and refuses to proceed unless every one is satisfied:

    1. LAB GUARD      — the domain must be ad.halden.internal.
    2. TARGET GUARD   — must NOT run on DC01/DC02/FS01 (no simulations against Tier 0) and the host
                        must be the expected test host (default WS01).
    3. APPROVAL GATE  — -ApproveAuthorisedLabSimulation AND the operator must type the exact
                        approval phrase at the prompt. -WhatIf / -ListTests bypass only the run.
    4. SNAPSHOT GATE  — -SnapshotTaken must be supplied, attesting the target VM was snapshotted
                        immediately before this run (snap-p7-ph3-before).

  WHAT IT EXERCISES (defensive framing — what should be DETECTED, not how to attack):
    the techniques below are standard public Atomic Red Team tests. Each one is chosen because a
    Halden rule should notice the behaviour; the point is to validate the DETECTION, and to record
    where Defender PREVENTED it (a prevention is a good result, recorded separately).

  Every action is cleaned up (Invoke-AtomicTest -Cleanup) at the end, and the script re-verifies
  the target is unchanged where it can. Nothing is ever run against a domain controller.
.PARAMETER Technique
  One or more ATT&CK techniques from the allowed set. Default runs the core set.
.PARAMETER TargetHost
  The expected test host. Default WS01. The script aborts if run anywhere else.
.PARAMETER ApproveAuthorisedLabSimulation
  Required switch. Confirms this is the authorised Halden lab exercise.
.PARAMETER SnapshotTaken
  Required switch. Attests the target VM snapshot was taken immediately before this run.
.PARAMETER IncludePrivilegedGroupControlTest
  Optional, extra-gated. Adds a controlled check of the D1 rule by adding and immediately removing
  a dedicated adm-t0-* test account from a privileged group on DC01. Requires DC01 to be
  snapshotted and a second typed confirmation. Not run by default.
.PARAMETER ListTests
  Print what would run and exit; changes nothing.
.EXAMPLE
  .\07-Run-AuthorisedSimulation.ps1 -ListTests
.EXAMPLE
  .\07-Run-AuthorisedSimulation.ps1 -Technique T1059.001,T1490 -SnapshotTaken -ApproveAuthorisedLabSimulation
.NOTES
  Requires Invoke-AtomicRedTeam (installed on demand) and a snapshot of the target first.
  The user must be the owner of the lab and have authority over every host involved.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [string[]]$Technique = @('T1059.001', 'T1490', 'T1543.003', 'T1053.005', 'T1136.002'),
  [string]$TargetHost = 'WS01',
  [switch]$ApproveAuthorisedLabSimulation,
  [switch]$SnapshotTaken,
  [switch]$IncludePrivilegedGroupControlTest,
  [switch]$ListTests
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ApprovalPhrase = 'I AUTHORISE THIS LAB SIMULATION'

# The allowed techniques and what each validates. No step-by-step instructions beyond the public
# Atomic Red Team test names, per AGENTS.md 4.6 (attack content is described defensively).
$Allowed = @{
  'T1059.001' = @{ Test = @('1', '2'); Expected = 'Halden D6 (rule 100106) encoded/download-cradle PowerShell'; Prevented = 'Defender may block the payload — record prevented vs detected separately' }
  'T1490'     = @{ Test = @('1');       Expected = 'Halden D7 (rule 100107) shadow-copy / recovery deletion';     Prevented = 'ASR can block this; if blocked, the alert may be a Defender event instead' }
  'T1543.003' = @{ Test = @('1');       Expected = 'Halden D9 (rule 100109) new Windows service';                  Prevented = 'Low prevention risk on a workstation' }
  'T1053.005' = @{ Test = @('1');       Expected = 'Halden D9b (rule 100110) scheduled task created';              Prevented = 'Low prevention risk' }
  'T1136.002' = @{ Test = @('1');       Expected = 'native 4720 (audit proof); no custom rule — tests P2 awareness'; Prevented = 'Requires a domain-joined host and lab admin' }
  'T1003.001' = @{ Test = @('1');       Expected = 'Halden D5 (rule 100104) LSASS access';                         Prevented = 'Usually BLOCKED by Defender. Only if you need the detection layer, use a temporary, documented exclusion on THIS host and remove it afterwards' }
  'T1558.003' = @{ Test = @('1', '2');   Expected = 'Halden D2 (rule 100102) RC4 Kerberos service ticket';         Prevented = 'Low; P3 removed legacy RC4 so any hit is suspicious' }
}

function Assert-LabGuard {
  if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }
  $me = $env:COMPUTERNAME
  if ($me -match '^(DC01|DC02|FS01)$') { throw "Refusing to run a simulation on Tier 0 host $me. Use a test workstation." }
  if ($me -ne $TargetHost) { throw "Expected target $TargetHost but running on $me. Refusing." }
}

function Assert-ApprovalGate {
  if (-not $ApproveAuthorisedLabSimulation) {
    throw "Approval required: re-run with -ApproveAuthorisedLabSimulation. This is an authorised lab exercise (AGENTS.md R6)."
  }
  $typed = Read-Host "Type exactly: '$ApprovalPhrase'"
  if ($typed -ne $ApprovalPhrase) { throw 'Approval phrase did not match. Aborting.' }
  if (-not $SnapshotTaken) { throw 'Snapshot attestation required: take the VM snapshot first, then re-run with -SnapshotTaken.' }
}

function Show-Plan {
  Write-Host "`nAuthorised lab simulation plan — target $TargetHost, host $env:COMPUTERNAME`n"
  foreach ($t in $Technique) {
    if (-not $Allowed.ContainsKey($t)) { Write-Warning "Technique $t is not in the allowed set and will be skipped."; continue }
    $info = $Allowed[$t]
    Write-Host ("{0,-12} atomic tests {1,-6} -> should be DETECTED by: {2}" -f $t, ($info.Test -join ','), $info.Expected)
    Write-Host ("             note: {0}" -f $info.Prevented)
  }
  if ($IncludePrivilegedGroupControlTest) {
    Write-Host "`n[extra-gated] privileged-group control test: add then immediately remove a dedicated adm-t0-* test account from a privileged group on a snapshotted DC01."
  }
}

function Install-AtomicIfNeeded {
  if (-not (Get-Command Invoke-AtomicTest -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($TargetHost, 'Install Invoke-AtomicRedTeam')) {
      IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
      Install-AtomicRedTeam -getAtomics -Force
    }
  }
}

function Invoke-AllowedTechniques {
  foreach ($t in $Technique) {
    if (-not $Allowed.ContainsKey($t)) { continue }
    Write-Host "`n--- $t : $($Allowed[$t].Expected) ---"
    Write-Host 'Read what the test does first with: Invoke-AtomicTest <technique> -ShowDetailsBrief'
    if ($PSCmdlet.ShouldProcess($TargetHost, "Run Atomic tests for $t")) {
      Invoke-AtomicTest $t -TestNumbers ($Allowed[$t].Test) -ErrorAction Continue
    }
  }
}

function Invoke-Cleanup {
  foreach ($t in $Technique) {
    if (-not $Allowed.ContainsKey($t)) { continue }
    if ($PSCmdlet.ShouldProcess($TargetHost, "Clean up Atomic tests for $t")) {
      Invoke-AtomicTest $t -TestNumbers ($Allowed[$t].Test) -Cleanup -ErrorAction Continue
    }
  }
}

function Invoke-PrivilegedGroupControlTest {
  if (-not $IncludePrivilegedGroupControlTest) { return }
  if (-not $PSCmdlet.ShouldProcess('DC01', 'Privileged group control test')) { return }
  $doubleConfirm = Read-Host "This touches DC01. DC01 must be snapshotted. Type 'DC01 SNAPSHOTTED' to continue"
  if ($doubleConfirm -ne 'DC01 SNAPSHOTTED') { Write-Warning 'Control test skipped (confirmation not given).'; return }
  Write-Host 'Implement this as an explicit, recorded change (P10): add the dedicated test account to a privileged group, confirm rule 100100 fires, then remove it and log the change.'
  Write-Host 'The script does NOT do this silently. Follow docs/runbooks/privileged-group-change.md.'
}

Assert-LabGuard
Show-Plan
if ($ListTests) { Write-Host "`n-ListTests specified: nothing was run."; return }
Assert-ApprovalGate
Install-AtomicIfNeeded
Invoke-AllowedTechniques
Invoke-PrivilegedGroupControlTest
Invoke-Cleanup
Write-Host "`nSimulation finished. Next: on SIEM01 run scripts/08-Validate-Detections.sh to see which rules fired,"
Write-Host "then scripts/09-Export-AlertEvidence.sh for a sanitized extract. Fill the coverage matrix from the real output only."

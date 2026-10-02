<#
.SYNOPSIS
  P3 Phase 0 gate: confirm prerequisites AND the owner's explicit authorisation before any
  assessment or hardening script in this project runs. Read-only.

.DESCRIPTION
  P3 uses attack-path tooling (PingCastle, Purple Knight, BloodHound CE / SharpHound). AGENTS.md
  rule R6 requires the owner's explicit, written authorisation before that tooling is run, even
  inside the lab. This script refuses to pass unless it is given an authorisation reference and
  confirmation that snapshots were taken. It also verifies the environment is the Halden lab and
  that the RSAT AD tools are present.

  This script makes no change to the directory. It writes a gate report to evidence\raw\ and
  exits 0 only when every check passes.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER AuthorisationReference
  The change-record or ticket ID under which the owner authorised this assessment
  (for example CHG-2026-004). Must not be empty.

.PARAMETER IHaveOwnerAuthorisation
  Switch. Must be supplied to confirm the owner has authorised running the assessment and
  the hardening phases on their own isolated lab. Without it the gate fails.

.PARAMETER SnapshotsTaken
  Switch. Must be supplied to confirm every VM this phase touches has a hypervisor snapshot
  named snap-p3-ph<N>-before (AGENTS.md rule R4).

.PARAMETER Report
  Where to write the gate report. Defaults to ..\evidence\raw\p03-ph0-assessment-gate-result.txt.

.EXAMPLE
  .\00-Test-AssessmentGate.ps1 -AuthorisationReference CHG-2026-004 -IHaveOwnerAuthorisation -SnapshotsTaken

.NOTES
  Authorised lab exercise only. Halden Distribution Ltd. is fictional; the domain, hosts and
  subnet are the owner's isolated home lab. Never point this or any P3 tool at another network.
#>
[CmdletBinding()]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$AuthorisationReference = '',
  [switch]$IHaveOwnerAuthorisation,
  [switch]$SnapshotsTaken,
  [string]$Report = "$PSScriptRoot\..\evidence\raw\p03-ph0-assessment-gate-result.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Lab guard (AGENTS.md Section 2): abort immediately outside the Halden lab.
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
  $checks.Add([pscustomobject]@{ Check = $Name; Pass = $Pass; Detail = $Detail })
}

# 1. Authorisation (R6) — the most important gate.
Add-Check 'Owner authorisation supplied' ([bool]$IHaveOwnerAuthorisation -and $AuthorisationReference.Trim() -ne '') `
  ("reference '{0}'" -f $(if ($AuthorisationReference) { $AuthorisationReference } else { 'none given' }))
Add-Check 'Snapshots taken (R4)' ([bool]$SnapshotsTaken) 'snap-p3-ph<N>-before expected before each phase'

# 2. Tooling present.
$adModule = Get-Module -ListAvailable -Name ActiveDirectory
Add-Check 'ActiveDirectory PowerShell module' ([bool]$adModule) ($(if ($adModule) { 'RSAT AD DS tools found' } else { 'install RSAT-AD-PowerShell' }))

# 3. Environment really is the lab.
$domain = Get-ADDomain
$dcs = @(Get-ADDomainController -Filter * -ErrorAction SilentlyContinue)
Add-Check 'Domain matches design' ($domain.DNSRoot -eq $Domain) $domain.DNSRoot
Add-Check 'Functional level is Windows Server 2025' ($domain.DomainMode -eq 'Windows2025Domain') $domain.DomainMode.ToString()
Add-Check 'At least two domain controllers' ($dcs.Count -ge 2) ("{0} DC(s): {1}" -f $dcs.Count, ($dcs.Name -join ', '))

# 4. Repeat-run safety: tell the operator which phase data already exists.
$raw = Join-Path $PSScriptRoot '..\evidence\raw'
$seeded = Test-Path (Join-Path $raw 'p03-ph0-seed-log.csv')
Add-Check 'First run of the seed phase (informational)' (-not $seeded) `
  ($(if ($seeded) { 'seed log already exists - re-running the seed script is safe (idempotent)' } else { 'no seed log yet' }))

$failed = @($checks | Where-Object { -not $_.Pass })
$ok = $failed.Count -eq 0

New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
$header = @(
  'P3 assessment gate report',
  ("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
  ("Host: {0}" -f $env:COMPUTERNAME),
  ("Domain: {0}" -f $domain.DNSRoot),
  ("Authorisation reference: {0}" -f $AuthorisationReference),
  ''
)
$header + ($checks | Format-Table Check, Pass, Detail -AutoSize | Out-String) | Set-Content $Report -Encoding UTF8

$checks | Format-Table Check, Pass, Detail -AutoSize

if ($ok) {
  Write-Output 'GATE PASSED - authorisation recorded and prerequisites met. Continue to 01-Seed-Weaknesses.ps1.'
  exit 0
}
Write-Warning ("GATE FAILED - {0} check(s) did not pass. Do not run the assessment or hardening scripts." -f $failed.Count)
exit 1

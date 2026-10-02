<#
.SYNOPSIS
  Phase 3: run CISA ScubaGear against the tenant, before and after the controls are enforced.

.DESCRIPTION
  ScubaGear is CISA's free tool that assesses a Microsoft 365 tenant against the SCuBA secure
  configuration baselines and produces a report per product. Running it before and after the identity
  work is what turns "we deployed Conditional Access" into a number: the pass/fail/warning counts for
  each product, with the finding detail behind them.

  The GETTING-STARTED preamble (module install + Initialize-SCuBA) is separate on purpose: it installs
  PowerShell modules from the internet, so it is an explicit one-off step rather than something this
  script does silently on every run.

      Install-Module ScubaGear -Scope CurrentUser     # once
      Initialize-SCuBA                                # once, creates the ScubaGear working folder
      .\09-Invoke-ScubaGear.ps1 -Stage before -ProductNames aad, exo, teams
      # ... deploy CA001-CA005 and enforce them ...
      .\09-Invoke-ScubaGear.ps1 -Stage after  -ProductNames aad, exo, teams

  The summary counts are written to a small JSON file per stage so the README's before/after row can
  be filled from a real artifact, not from memory.

.PARAMETER Stage
  before or after. Only controls the output folder and the summary file name.

.PARAMETER ProductNames
  Which SCuBA products to assess. Defaults to aad (Entra ID), the product this project actually changes.

.PARAMETER OutPath
  Root folder for ScubaGear output. Defaults to..\evidence\raw\scuba-<stage>.

.EXAMPLE
  .\09-Invoke-ScubaGear.ps1 -Stage before -ProductNames aad,exo,teams
  Run the baseline assessment before the identity changes.

.EXAMPLE
  .\09-Invoke-ScubaGear.ps1 -Stage after
  Re-run it after the controls are enforced and write a comparable summary.

.NOTES
  Requires ScubaGear installed and initialised, plus the roles ScubaGear needs to read tenant
  configuration. Reports can contain tenant identifiers: sanitize before publishing (AGENTS.md 4.6).
  This is a read-only assessment; it changes nothing in the tenant.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('before', 'after')] [string] $Stage,
    [string[]] $ProductNames = @('aad'),
    [string] $OutPath,
    [string] $SummaryDir = "$PSScriptRoot\..\evidence\public"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md Section 2) ------------------------------------------------------------
$markerFile = 'C:\halden-lab-marker'
if (-not (Test-Path $markerFile -PathType Leaf)) {
    throw "Not a Halden lab host (no $markerFile). Aborting. Create it once: New-Item -ItemType File -Path '$markerFile' -Force"
}
$adRoot = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
if ($adRoot -and $adRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }

if (-not (Get-Command Invoke-SCuBA -ErrorAction SilentlyContinue)) {
    throw @'
ScubaGear is not installed. Run these once, then try again:
    Install-Module ScubaGear -Scope CurrentUser
    Initialize-SCuBA
See https://github.com/cisagov/ScubaGear for the current requirements (PowerShell 7, the roles it needs).
'@
}

if (-not $OutPath) { $OutPath = Join-Path "$PSScriptRoot\..\evidence\raw" "scuba-$Stage" }
New-Item -ItemType Directory -Force -Path $OutPath | Out-Null

Write-Host "ScubaGear assessment: stage '$Stage', products: $($ProductNames -join ', ')" -ForegroundColor Cyan
Write-Host "Output: $OutPath"
Write-Host ''
Write-Host 'Note: this assesses the LAB trial tenant only. Do not point it at any other tenant (AGENTS.md rule R1).' -ForegroundColor DarkYellow

Invoke-SCuBA -ProductNames $ProductNames -OutPath $OutPath -Quiet

# --- Summarise the results into a small, comparable artifact ------------------------------------
# ScubaGear writes one Results JSON per product plus an HTML report. The summary here is counts only,
# so the before/after row in the README can be sourced from a machine-readable file.
$results = Get-ChildItem -Path $OutPath -Recurse -Filter '*Results*.json' -ErrorAction SilentlyContinue
if (-not $results) {
    Write-Warning "No Results JSON found under $OutPath. ScubaGear's output layout changes between versions - read the HTML report and record the counts by hand."
    return
}

$summary = foreach ($r in $results) {
    try {
        $json = Get-Content $r.FullName -Raw | ConvertFrom-Json
        $controls = @($json.Results)
        if ($controls.Count -eq 0) { continue }
        [pscustomobject] @{
            Product      = ($r.BaseName -replace '.*?-', '') -replace 'Results', ''
            Pass         = @($controls | Where-Object { $_.Result -match 'Pass' }).Count
            Fail         = @($controls | Where-Object { $_.Result -match 'Fail' }).Count
            Warning      = @($controls | Where-Object { $_.Result -match 'Warning' }).Count
            NotApplicable = @($controls | Where-Object { $_.Result -match 'Not Applicable|NotImplemented|Not Implemented' }).Count
            Total        = $controls.Count
        }
    } catch {
        Write-Warning "Could not parse $($r.Name): $($_.Exception.Message)"
    }
}

if (-not $summary) {
    Write-Warning 'Could not summarise the results automatically. Read the HTML report and record the counts manually - do not estimate them.'
    return
}

$outFile = Join-Path $SummaryDir "p02-ph3-scubagear-$Stage.json"
New-Item -ItemType Directory -Force -Path $SummaryDir | Out-Null
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path $outFile -Encoding UTF8

Write-Host ''
$summary | Format-Table -AutoSize
Write-Host "Summary written: $outFile" -ForegroundColor Cyan
Write-Host 'These are the real counts for the README before/after row. Do not round or adjust them.' -ForegroundColor Cyan
Write-Host 'If a count looks wrong, re-run and read the HTML report - never edit the summary by hand.' -ForegroundColor DarkYellow

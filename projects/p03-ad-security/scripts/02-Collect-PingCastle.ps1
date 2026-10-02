<#
.SYNOPSIS
  P3 Phase 1: run a PingCastle healthcheck against the lab domain and capture the BEFORE
  (or AFTER) risk score for the before/after table. Read-only against AD.

.DESCRIPTION
  PingCastle is a free, well-known Active Directory risk assessment tool (the free basic edition
  audits your own domain). This script runs it unattended, keeps the raw report in
  evidence\raw\ (git-ignored) and extracts the global score into a small CSV so the register and
  the README can cite a real number later.

  Run it twice: once after seeding (Phase 1, -Phase before) and once after remediation
  (Phase 7, -Phase after). Nothing is measured until this has actually run.

.PARAMETER Domain
  Domain to assess. Default ad.halden.internal.

.PARAMETER PingCastlePath
  Folder that contains PingCastle.exe. PingCastle is not downloaded by this script: obtain the
  free basic edition from https://www.pingcastle.com and place it in the lab, for example
  C:\Tools\PingCastle.

.PARAMETER Phase
  before or after. Controls the output file names (p03-ph1-*-before / p03-ph7-*-after).

.PARAMETER OutDir
  Where the raw HTML, XML and summary CSV are written. Defaults to ..\evidence\raw.

.PARAMETER AuthorisationReference
  The change-record ID under which the owner authorised this assessment (AGENTS.md rule R6).

.PARAMETER IHaveOwnerAuthorisation
  Must be supplied. The script refuses to run the assessment tooling otherwise.

.EXAMPLE
  .\02-Collect-PingCastle.ps1 -PingCastlePath C:\Tools\PingCastle -Phase before `
    -AuthorisationReference CHG-2026-004 -IHaveOwnerAuthorisation

.NOTES
  Authorised isolated-lab exercise only. The HTML report names internal accounts and groups:
  it stays in evidence\raw and is never published raw (AGENTS.md 4.6). Publish a sanitized
  summary or screenshot instead.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [Parameter(Mandatory)]
  [string]$PingCastlePath,
  [ValidateSet('before', 'after')]
  [string]$Phase = 'before',
  [string]$OutDir = "$PSScriptRoot\..\evidence\raw",
  [string]$AuthorisationReference = '',
  [switch]$IHaveOwnerAuthorisation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
if (-not ($IHaveOwnerAuthorisation -and $AuthorisationReference.Trim() -ne '')) {
  throw 'Refusing to run assessment tooling without explicit owner authorisation. Pass -IHaveOwnerAuthorisation and -AuthorisationReference.'
}

$exe = Join-Path $PingCastlePath 'PingCastle.exe'
if (-not (Test-Path $exe)) { throw "PingCastle.exe not found at $exe. Download the free basic edition and retry." }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$phaseTag = if ($Phase -eq 'before') { 'ph1' } else { 'ph7' }
$htmlName = "p03-$phaseTag-pingcastle-$Phase.html"
$xmlName = "p03-$phaseTag-pingcastle-$Phase.xml"
$sumName = "p03-$phaseTag-pingcastle-$Phase-summary.csv"

if ($PSCmdlet.ShouldProcess($Domain, "Run PingCastle healthcheck ($Phase)")) {
  Push-Location $OutDir
  try {
    # The trailing switches keep the run non-interactive. No write is made to AD.
    & $exe --healthcheck --server $Domain --noenumshare --noreportpage
    if ($LASTEXITCODE -ne 0) { throw "PingCastle exited with code $LASTEXITCODE." }
  } finally {
    Pop-Location
  }

  # PingCastle writes ad_hc_<domain>.html / .xml into the working directory.
  $html = Get-ChildItem $OutDir -Filter 'ad_hc_*.html' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $xml = Get-ChildItem $OutDir -Filter 'ad_hc_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $html) { throw 'PingCastle produced no HTML report; check the tool output above.' }
  Copy-Item $html.FullName (Join-Path $OutDir $htmlName) -Force
  if ($xml) { Copy-Item $xml.FullName (Join-Path $OutDir $xmlName) -Force }

  # Extract the global score defensively; the exact element name varies by PingCastle version.
  $globalScore = 'not parsed'
  $details = @()
  if ($xml) {
    [xml]$doc = Get-Content $xml.FullName -Raw
    $nodes = $doc.SelectNodes('//*[local-name()="GlobalScore"]')
    if ($nodes.Count -gt 0) { $globalScore = $nodes[0].InnerText }
    $details = @($doc.SelectNodes('//*[local-name()="Score"]') | ForEach-Object { $_.InnerText })
  }

  [pscustomobject]@{
    Date                = (Get-Date -Format s)
    Phase               = $Phase
    Domain              = $Domain
    GlobalScore         = $globalScore
    CategoryScores      = ($details -join '|')
    AuthorisationRef    = $AuthorisationReference
    HtmlReport          = $htmlName
    XmlReport           = $(if ($xml) { $xmlName } else { '' })
  } | Export-Csv (Join-Path $OutDir $sumName) -NoTypeInformation
}

Write-Output "PingCastle $Phase report captured in $OutDir ($htmlName)."
Write-Warning 'The raw HTML/XML names internal accounts and groups: keep it in evidence\raw and publish only a sanitized summary.'

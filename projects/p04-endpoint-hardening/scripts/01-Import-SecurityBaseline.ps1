<#
.SYNOPSIS
  Phase 1 - import the Microsoft Security Baseline into new GPOs and link them to the pilot OU.
.DESCRIPTION
  Imports the Windows 11 security baseline (from an unzipped Microsoft Security Compliance
  Toolkit backup folder) into a NEW GPO, creates a separate Halden overrides GPO for documented
  deviations, links both to the pilot OU with the overrides GPO at higher precedence, backs up
  both GPOs, and exports GPO reports (XML + HTML) so Policy Analyzer can be used to compare the
  baseline with the existing P1-P3 GPOs.

  The script never edits the original Microsoft GPO backups, so the next baseline release can be
  imported and compared later. It is idempotent: existing GPOs and links are left alone.

  Run Policy Analyzer (free, from the Security Compliance Toolkit) afterwards and save its
  comparison under evidence/public (sanitized) - no conflict should be resolved silently.
.PARAMETER BackupPath
  Folder containing the unzipped GPO backups from the Security Compliance Toolkit.
.PARAMETER BaselineBackupName
  Name of the baseline backup to import (as it appears in the toolkit folder).
.PARAMETER ComputerGpoName
  Name of the new GPO that receives the imported baseline.
.PARAMETER OverridesGpoName
  Name of the new GPO that carries Halden-specific deviations (higher precedence).
.PARAMETER PilotOu
  Distinguished name of the pilot OU to link the GPOs to. Default: Workstations\Pilot.
.PARAMETER OutputPath
  Folder for the GPO report and backup evidence. Defaults to evidence\raw.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\01-Import-SecurityBaseline.ps1 -BackupPath C:\Tools\SCT\Baseline\GPOs -WhatIf
.EXAMPLE
  .\01-Import-SecurityBaseline.ps1 -BackupPath C:\Tools\SCT\Baseline\GPOs
.NOTES
  Snapshot DC01 (and any DC you touch) first: snap-p4-ph1-before. Rollback = unlink the GPOs,
  then delete them (Remove-GPLink / Remove-GPO) and re-run the previous phase. The baseline is
  applied to the pilot OU (WS02) for at least 3 days before it goes to all workstations.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BackupPath = (Join-Path $PSScriptRoot '..\configs\baseline'),
    [string]$BaselineBackupName = 'MSFT Windows 11 24H2 - Computer',
    [string]$ComputerGpoName = 'WKS - MSFT Baseline Computer - v1',
    [string]$OverridesGpoName = 'WKS - Halden Overrides - v1',
    [string]$PilotOu = 'OU=Pilot,OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
Import-Module GroupPolicy -ErrorAction Stop

if (-not (Test-Path -Path $BackupPath)) {
    throw "Baseline backup folder not found: $BackupPath. Unzip the Security Compliance Toolkit baseline here first."
}

if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

function Ensure-Gpo {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Comment)

    if (Get-GPO -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "GPO '$Name' already exists - skipping create (idempotent)."
        return
    }
    if ($PSCmdlet.ShouldProcess($Name, 'Create GPO')) {
        New-GPO -Name $Name -Comment $Comment | Out-Null
        Write-Host "Created GPO '$Name'."
    }
}

function Ensure-GpoLink {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Target, [int]$Order)

    $linked = Get-GPInheritance -Target $Target -ErrorAction Stop |
        Select-Object -ExpandProperty GpoLinks |
        Where-Object { $_.DisplayName -eq $Name }
    if ($linked) {
        Write-Host "GPO '$Name' already linked to $Target - skipping link (idempotent)."
        return
    }
    if ($PSCmdlet.ShouldProcess($Target, "Link GPO '$Name' at order $Order")) {
        New-GPLink -Name $Name -Target $Target -Order $Order -LinkEnabled Yes | Out-Null
        Write-Host "Linked '$Name' to $Target (order $Order)."
    }
}

# 1. Import Microsoft's baseline into a new GPO (never edit the original backup).
if (-not (Get-GPO -Name $ComputerGpoName -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($ComputerGpoName, 'Import Microsoft Security Baseline GPO')) {
        Import-GPO -BackupGpoName $BaselineBackupName -Path $BackupPath -TargetName $ComputerGpoName -CreateIfNeeded | Out-Null
        Write-Host "Imported '$BaselineBackupName' into GPO '$ComputerGpoName'."
    }
}
else {
    Write-Host "GPO '$ComputerGpoName' already exists - skipping import (idempotent)."
}

# 2. A separate overrides GPO for documented deviations (see business/p04-baseline-exceptions.md).
Ensure-Gpo -Name $OverridesGpoName -Comment 'Halden documented deviations from the Microsoft baseline (P4).'

# 3. Link to the pilot OU: overrides at order 1 (wins), baseline at order 2.
Ensure-GpoLink -Name $OverridesGpoName -Target $PilotOu -Order 1
Ensure-GpoLink -Name $ComputerGpoName -Target $PilotOu -Order 2

# 4. Back up both GPOs and export reports for the Policy Analyzer comparison.
try {
    Backup-GPO -Name $ComputerGpoName -Path (Join-Path $PSScriptRoot '..\configs\gpo-backup') | Out-Null
    Backup-GPO -Name $OverridesGpoName -Path (Join-Path $PSScriptRoot '..\configs\gpo-backup') | Out-Null
    Get-GPOReport -Name $ComputerGpoName -ReportType Xml  -Path (Join-Path $OutputPath 'p04-ph1-baseline-gpo-export.xml')
    Get-GPOReport -Name $ComputerGpoName -ReportType Html -Path (Join-Path $OutputPath 'p04-ph1-baseline-gpo-export.html')
    Write-Host 'GPO reports exported. Open them in Policy Analyzer to list conflicts with the P1-P3 GPOs.'
}
catch {
    Write-Warning ("GPO reports or backups partly failed: {0}" -f $_.Exception.Message)
}

Write-Host 'Pilot ring active. Apply to all workstations only after 3 days with no business impact.'

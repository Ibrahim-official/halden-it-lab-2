<#
.SYNOPSIS  Phase 1: VM-level backup of the Halden VMs to the staging area that BKP01 pulls from.
.DESCRIPTION  Runs on HOST01 (Hyper-V host). For each in-scope VM it takes an application-consistent
  production checkpoint, exports the VM (config + disks) to a dated folder with Export-VM, then removes
  the checkpoint. The staging folder is collected by BKP01 (restic/PBS). Idempotent: skips a VM whose
  export for today already exists unless -Force is given. Supports -WhatIf.
  Snapshot first: snap-p8-ph1-before. Rollback: Remove-Item the dated export folder.
  Lab guard: the Halden-LAN private switch must exist (this is a Halden lab host).
.NOTES  Hyper-V module required. Run elevated.
.EXAMPLE
  .\02-Backup-HyperVVMs.ps1 -WhatIf
  .\02-Backup-HyperVVMs.ps1 -Tier 0,1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string[]]$Tier = @(0,1,2),
  [string]$VmRoot = 'D:\HaldenLab',
  [string]$StageRoot = 'D:\HaldenBackup\stage',
  [string[]]$Name,
  [int]$RetentionDays = 14,
  [string]$LogPath = "$PSScriptRoot\..\evidence\raw\p08-ph1-vmbackup-result.csv",
  [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Lab guard: this only ever runs against the Halden lab.
if (-not (Get-VMSwitch -Name 'Halden-LAN' -ErrorAction SilentlyContinue)) {
  throw 'Not a Halden lab host. Aborting.'
}

# Tier map (design: docs/00-design.md §4). Workstations are not backed up by design (re-imaged).
$tierMap = @{ DC01 = 0; DC02 = 0; FS01 = 1; LNX01 = 1; OPS01 = 2; SIEM01 = 2 }
$today = Get-Date -Format 'yyyyMMdd'

function Get-InScopeVm {
  $vms = if ($Name) { $Name } else { $tierMap.Keys | Sort-Object }
  $vms | Where-Object { $tierMap.ContainsKey($_) -and ($Tier -contains $tierMap[$_]) }
}

function Export-OneVm {
  param([string]$VmName)
  $dest = Join-Path $StageRoot (Join-Path $VmName $today)
  if ((Test-Path $dest) -and -not $Force) {
    Write-Verbose "$VmName already exported for $today; skipping"
    return [pscustomobject]@{ Vm=$VmName; Tier=$tierMap[$VmName]; Status='exists-skip'; Path=$dest; Started=$null; Ended=$null; Seconds=$null }
  }
  if (-not $PSCmdlet.ShouldProcess($VmName, 'Export VM to staging for backup')) {
    return [pscustomobject]@{ Vm=$VmName; Tier=$tierMap[$VmName]; Status='whatif'; Path=$dest; Started=$null; Ended=$null; Seconds=$null }
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  $start = Get-Date
  $checkpoint = "p8-backup-$today"
  $hadCheckpoint = $false
  try {
    if ((Get-VM -Name $VmName).State -eq 'Running') {
      # Application-consistent production checkpoint so the guest freezes its filesystem first.
      Checkpoint-VM -Name $VmName -SnapshotName $checkpoint -ErrorAction Stop
      $hadCheckpoint = $true
    }
    Export-VM -Name $VmName -Path $dest -ErrorAction Stop
  }
  finally {
    if ($hadCheckpoint) { Remove-VMSnapshot -VMName $VmName -Name $checkpoint -ErrorAction SilentlyContinue }
  }
  $end = Get-Date
  [pscustomobject]@{ Vm=$VmName; Tier=$tierMap[$VmName]; Status='exported'; Path=$dest;
    Started=$start.ToString('s'); Ended=$end.ToString('s'); Seconds=[math]::Round(($end-$start).TotalSeconds,1) }
}

function Remove-OldExports {
  if (-not (Test-Path $StageRoot)) { return }
  $cutoff = (Get-Date).AddDays(-$RetentionDays)
  Get-ChildItem $StageRoot -Directory | ForEach-Object {
    $vmDir = $_
    Get-ChildItem $vmDir.FullName -Directory | Where-Object {
      $_.Name -match '^\d{8}$' -and [datetime]::ParseExact($_.Name, 'yyyyMMdd', $null) -lt $cutoff
    } | ForEach-Object {
      if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove expired staging export')) {
        Remove-Item $_.FullName -Recurse -Force
      }
    }
  }
}

# --- run ---
New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
$results = foreach ($vm in Get-InScopeVm) { Export-OneVm -VmName $vm }
Remove-OldExports
if ($results) {
  $results | Export-Csv -Path $LogPath -NoTypeInformation -Append
  $results | Format-Table Vm, Tier, Status, Seconds -AutoSize
} else {
  Write-Warning 'No in-scope VMs matched the requested tiers.'
}
Write-Output 'Next: BKP01 collects this staging folder into the repository (see 04-Backup-OffsiteCopy.sh).'

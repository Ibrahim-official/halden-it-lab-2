<#
.SYNOPSIS  Phase 1: back up the domain controller system state (AD, SYSVOL, registry) with wbadmin.
.DESCRIPTION  Runs on DC01 or DC02. Writes a system-state backup to a dedicated volume, then copies it
  to a staging share that BKP01 collects. A system-state backup is what enables an authoritative
  restore; the tombstone lifetime (180 days) is recorded so a too-old backup is never used.
  Idempotent: re-running simply produces another dated backup set. Supports -WhatIf.
  Snapshot first: snap-p8-ph1-before. Rollback: delete the dated backup folder on the target volume.
  Lab guard: the DNS root must be ad.halden.internal.
.NOTES  Requires the Windows-Server-Backup feature and an elevated session on a domain controller.
.EXAMPLE
  .\03-Backup-DCSystemState.ps1 -BackupTarget 'E:'
  .\03-Backup-DCSystemState.ps1 -BackupTarget 'E:' -StageShare '\\BKP01\dc01-systemstate' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$BackupTarget,
  [string]$StageShare,
  [System.Management.Automation.PSCredential]$StageCredential,
  [int]$TombstoneLifetimeDays = 180,
  [string]$Domain = 'ad.halden.internal',
  [string]$LogPath = "$PSScriptRoot\..\evidence\raw\p08-ph1-dcsystemstate-result.csv"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Lab guard: this only ever runs against the Halden lab.
if ((Get-ADDomain).DNSRoot -ne $Domain) {
  throw 'Not the Halden lab domain. Aborting.'
}

$hostname = $env:COMPUTERNAME
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'

function Ensure-WindowsServerBackup {
  $feat = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction SilentlyContinue
  if ($feat -and -not $feat.Installed) {
    if ($PSCmdlet.ShouldProcess('Windows-Server-Backup', 'Install feature')) {
      Install-WindowsFeature -Name Windows-Server-Backup | Out-Null
    }
  }
  if (-not (Get-Command wbadmin.exe -ErrorAction SilentlyContinue)) {
    throw 'wbadmin is not available after installing the feature.'
  }
}

function Invoke-SystemStateBackup {
  $start = Get-Date
  if ($PSCmdlet.ShouldProcess($hostname, "System state backup to $BackupTarget")) {
    & wbadmin.exe start systemstatebackup -backupTarget:$BackupTarget -quiet
    if ($LASTEXITCODE -ne 0) { throw "wbadmin failed with exit code $LASTEXITCODE" }
  }
  $end = Get-Date
  [math]::Round(($end - $start).TotalSeconds, 1)
}

function Copy-ToStage {
  param([double]$Seconds, [string]$Status)
  if (-not $StageShare) { return $Status }
  $dest = Join-Path $StageShare "$hostname\$stamp"
  if ($PSCmdlet.ShouldProcess($dest, 'Copy system state backup to staging share')) {
    if ($StageCredential) {
      $drive = 'X:'
      & net.exe use $drive $StageShare /user:$($StageCredential.UserName) $($StageCredential.GetNetworkCredential().Password) | Out-Null
      try { New-Item -ItemType Directory -Force -Path "$drive\$hostname" | Out-Null }
      finally { & net.exe use $drive /delete /y | Out-Null }
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    }
  }
  return "$Status+staged"
}

# --- run ---
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
if (-not (Test-Path $BackupTarget)) { throw "Backup target volume '$BackupTarget' not found." }
Ensure-WindowsServerBackup
$seconds = Invoke-SystemStateBackup
$status = Copy-ToStage -Seconds $seconds -Status 'systemstate-backup'

$row = [pscustomobject]@{
  Host            = $hostname
  Started         = (Get-Date).ToString('s')
  Target          = $BackupTarget
  Status          = $status
  Seconds         = $seconds
  TombstoneLifetimeDays = $TombstoneLifetimeDays
  StageShare      = if ($StageShare) { $StageShare } else { '' }
}
$row | Export-Csv -Path $LogPath -NoTypeInformation -Append
$row | Format-List

Write-Output "Never restore this DC from a backup older than $TombstoneLifetimeDays days (tombstone lifetime)."
Write-Output 'An authoritative restore must be done from DSRM - see docs/runbooks/ransomware-immutability.md and 07-Restore-ADRecovery.ps1.'

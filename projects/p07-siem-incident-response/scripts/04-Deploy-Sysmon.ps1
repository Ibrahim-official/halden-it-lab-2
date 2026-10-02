<#
.SYNOPSIS
  P7 Phase 1: deploy Sysmon with the Halden config and keep it current.
.DESCRIPTION
  Installs Sysmon (if missing) with configs/sysmonconfig-halden.xml, or updates an existing
  installation with `sysmon64 -c` when the config file hash has changed. Idempotent: running it a
  second time with no config change does nothing.
  The config is expected in the NETLOGON share so a GPO startup script can run this with no
  arguments on every Windows host. Lab-guarded. Supports -WhatIf.
.PARAMETER ConfigPath
  Path to the Sysmon config XML. Default: the NETLOGON copy deployed from configs/.
.PARAMETER SysmonExe
  Path to Sysmon64.exe. Default: alongside the script, or downloaded from Sysinternals.
.EXAMPLE
  .\04-Deploy-Sysmon.ps1
.EXAMPLE
  .\04-Deploy-Sysmon.ps1 -ConfigPath .\..\configs\sysmonconfig-halden.xml
.NOTES
  Run from an elevated prompt. Snapshot the host first: snap-p7-ph1-before.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ConfigPath = '\\ad.halden.internal\NETLOGON\sysmon\sysmonconfig-halden.xml',
  [string]$SysmonExe = "$PSScriptRoot\sysmon64.exe",
  [string]$SysmonUrl = 'https://live.sysinternals.com/Sysmon64.exe',
  [string]$HashFile = "$env:ProgramData\halden-sysmon-config.hash"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run from an elevated PowerShell prompt.'
}
if (-not (Test-Path $ConfigPath)) { throw "Sysmon config not found: $ConfigPath" }

$configHash = (Get-FileHash -Path $ConfigPath -Algorithm SHA256).Hash
$installed = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue

function Get-SysmonExe {
  if (Test-Path $SysmonExe) { return }
  Write-Host "Downloading Sysmon to $SysmonExe"
  Invoke-WebRequest -Uri $SysmonUrl -OutFile $SysmonExe -UseBasicParsing
}

if (-not $installed) {
  Get-SysmonExe
  if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install Sysmon with $ConfigPath")) {
    Start-Process $SysmonExe -ArgumentList "-accepteula -i `"$ConfigPath`"" -Wait -NoNewWindow
    Set-Content -Path $HashFile -Value $configHash
    Write-Host "Sysmon installed with the Halden config."
  }
}
elseif (-not (Test-Path $HashFile) -or (Get-Content $HashFile -Raw).Trim() -ne $configHash) {
  Get-SysmonExe
  if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Update Sysmon config from $ConfigPath")) {
    Start-Process $SysmonExe -ArgumentList "-accepteula -c `"$ConfigPath`"" -Wait -NoNewWindow
    Set-Content -Path $HashFile -Value $configHash
    Write-Host "Sysmon config updated."
  }
}
else {
  Write-Host "Sysmon already running with the current config (hash unchanged)."
}

Write-Host "Verify: Get-Service Sysmon64 ; Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 5"

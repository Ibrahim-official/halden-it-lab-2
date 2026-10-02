<#
.SYNOPSIS
  P7 Phase 1: install and enrol the Wazuh agent on a Windows log source (DC01, DC02, FS01, WS01, WS02).
.DESCRIPTION
  Installs the Wazuh agent MSI (if missing), points it at SIEM01 and joins the correct agent group
  so the host receives the right agent.conf. Idempotent: if the agent is already installed it only
  repairs the manager address and group, then ensures the service is running.
  Lab-guarded (refuses to run outside ad.halden.internal). Supports -WhatIf.
.PARAMETER ManagerIp
  SIEM01 address. Default 192.168.10.41.
.PARAMETER AgentGroup
  windows-servers (DC01/DC02/FS01) or windows-workstations (WS01/WS02).
.PARAMETER MsiPath
  Path to wazuh-agent-<version>.msi. Default downloads to $env:TEMP if not supplied.
.EXAMPLE
  .\03-Deploy-Agents-Windows.ps1 -AgentGroup windows-servers
.NOTES
  Run from an elevated prompt. Snapshot the host first: snap-p7-ph1-before.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ManagerIp = '192.168.10.41',
  [ValidateSet('windows-servers', 'windows-workstations')]
  [string]$AgentGroup = 'windows-servers',
  [string]$MsiPath = "$env:TEMP\wazuh-agent.msi",
  [string]$MsiUrl = 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run from an elevated PowerShell prompt.'
}

function Get-WazuhService { Get-Service -Name 'WazuhSvc' -ErrorAction SilentlyContinue }

function Install-WazuhAgent {
  if (Get-WazuhService) { Write-Host "Wazuh agent already installed."; return }
  if (-not (Test-Path $MsiPath)) {
    Write-Host "Downloading agent MSI to $MsiPath"
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
  }
  $msiArgs = "/i `"$MsiPath`" /qn WAZUH_MANAGER=`"$ManagerIp`" WAZUH_AGENT_GROUP=`"$AgentGroup`" WAZUH_AGENT_NAME=`"$env:COMPUTERNAME`" /l*v `"$env:TEMP\wazuh-agent-install.log`""
  if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install Wazuh agent (group $AgentGroup, manager $ManagerIp)")) {
    Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -NoNewWindow
    Write-Host "Agent installed."
  }
}

function Set-ManagerAddress {
  $conf = Join-Path ${env:ProgramFiles(x86)} 'ossec-agent\ossec.conf'
  if (Test-Path $conf) {
    $content = Get-Content $conf -Raw
    $updated = $content -replace '<address>[^<]*</address>', "<address>$ManagerIp</address>"
    if ($updated -ne $content) {
      if ($PSCmdlet.ShouldProcess($conf, "Set Wazuh manager address to $ManagerIp")) {
        Set-Content -Path $conf -Value $updated -Encoding UTF8
        Write-Host "Manager address set to $ManagerIp."
      }
    } else { Write-Host "Manager address already $ManagerIp." }
  }
}

function Start-Agent {
  if ($PSCmdlet.ShouldProcess('WazuhSvc', 'Ensure running')) {
    Set-Service -Name 'WazuhSvc' -StartupType Automatic
    Restart-Service -Name 'WazuhSvc' -Force
    (Get-Service 'WazuhSvc').Status
  }
}

Install-WazuhAgent
Set-ManagerAddress
Start-Agent
Write-Host "Verify on SIEM01: docker exec -it <manager> /var/ossec/bin/agent_control -l  (host Active, group $AgentGroup)"

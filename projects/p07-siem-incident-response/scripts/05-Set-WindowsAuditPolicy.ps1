<#
.SYNOPSIS
  P7 Phase 1: apply the Halden Windows advanced audit policy required by the detections.
.DESCRIPTION
  Enables the audit subcategories from configs/windows-audit-policy.csv, turns on command-line
  process auditing and PowerShell script-block logging, and enlarges the Security log so evidence
  survives long enough to investigate. Idempotent: auditpol and the registry writes are safe to
  repeat. Lab-guarded. Supports -WhatIf.
.PARAMETER Profile
  SERVER (DCs, FS01) or WORKSTATION (WS01, WS02). Chooses the log size and the subcategory set.
.PARAMETER SecurityLogBytes
  Security log maximum size. Default 1 GB (servers) / 512 MB (workstations).
.EXAMPLE
  .\05-Set-WindowsAuditPolicy.ps1 -Profile SERVER
.EXAMPLE
  .\05-Set-WindowsAuditPolicy.ps1 -Profile WORKSTATION -WhatIf
.NOTES
  Run from an elevated prompt. Snapshot the host first: snap-p7-ph1-before.
  At scale this becomes a GPO ("DC - Audit Policy - v1" / "WKS - Audit Policy - v1"); this script is
  the equivalent applied directly, and the two must agree.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('SERVER', 'WORKSTATION')]
  [string]$Profile = 'SERVER',
  [int]$SecurityLogBytes = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run from an elevated PowerShell prompt.'
}
if ($SecurityLogBytes -eq 0) { $SecurityLogBytes = if ($Profile -eq 'SERVER') { 1073741824 } else { 536870912 } }

# subcategory = 'Success' | 'Failure' | 'Success and Failure'  (names, portable across builds)
$common = @{
  'Credential Validation'            = 'Success and Failure'
  'User Account Management'          = 'Success and Failure'
  'Logon'                            = 'Success and Failure'
  'Other Logon/Logoff Events'        = 'Success and Failure'
  'Account Lockout'                  = 'Failure'
  'Process Creation'                 = 'Success'
  'Process Termination'              = 'Success'
  'Sensitive Privilege Use'          = 'Success'
  'Filtering Platform Connection'    = 'Success'
}
$serverOnly = @{
  'Kerberos Authentication Service'      = 'Success and Failure'
  'Kerberos Service Ticket Operations'   = 'Success and Failure'
  'Security Group Management'            = 'Success'
  'Computer Account Management'          = 'Success'
  'Directory Service Access'             = 'Success'
  'Directory Service Changes'            = 'Success'
  'Special Logon'                        = 'Success'
  'Audit Policy Change'                  = 'Success'
  'Authentication Policy Change'         = 'Success'
  'Authorization Policy Change'          = 'Success'
  'Audit System Integrity'               = 'Success'
  'Other System Events'                  = 'Success'
  'File Share'                           = 'Success'
}
$set = if ($Profile -eq 'SERVER') { $common + $serverOnly } else { $common }

function Set-Subcategory {
  param([string]$Name, [string]$Setting)
  $success = 'disable'; $failure = 'disable'
  if ($Setting -in @('Success', 'Success and Failure')) { $success = 'enable' }
  if ($Setting -in @('Failure', 'Success and Failure')) { $failure = 'enable' }
  if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "auditpol: '$Name' success=$success failure=$failure")) {
    $null = auditpol.exe /set /subcategory:"$Name" /success:$success /failure:$failure
  }
}

function Set-RegistryPolicy {
  param([string]$Path, [string]$Name, [int]$Value)
  if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value")) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
  }
}

foreach ($k in $set.Keys) { Set-Subcategory -Name $k -Setting $set[$k] }

# Command-line process auditing and PowerShell logging — without these most detections see nothing.
Set-RegistryPolicy -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1
Set-RegistryPolicy -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name 'EnableScriptBlockLogging' -Value 1
Set-RegistryPolicy -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' -Name 'EnableModuleLogging' -Value 1

# Enlarge the Security log so a busy DC does not roll over before an analyst looks.
if ($PSCmdlet.ShouldProcess('Security log', "Set maximum size to $SecurityLogBytes bytes")) {
  $null = wevtutil.exe sl Security /ms:$SecurityLogBytes
}

Write-Host "Audit policy applied for profile $Profile."
Write-Host "Verify: auditpol /get /category:* | Select-String 'Process Creation|Kerberos|Logon'"
Write-Host "        (Get-WinEvent -ListLog Security).MaximumSizeInBytes"

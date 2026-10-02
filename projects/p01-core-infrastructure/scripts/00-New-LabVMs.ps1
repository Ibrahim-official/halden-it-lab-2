<#
.SYNOPSIS  Create the minimal-spec P1 lab VMs on a Hyper-V host (Hyper-V on Windows 11 Pro).
.DESCRIPTION Run on HOST01 in an elevated PowerShell. Creates a private switch (Halden-LAN) and
  Gen2 VMs with dynamic memory. FW01 WAN uses the built-in 'Default Switch' (NAT), so the lab never
  touches the home LAN. Does not download ISOs: pass local paths. Use -WhatIf to preview.
  Rollback: Remove-VM <name> -Force; delete the VHDX folder.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$VmRoot = 'D:\HaldenLab',
  [Parameter(Mandatory)][string]$ServerIso, [Parameter(Mandatory)][string]$Win11Iso,
  [Parameter(Mandatory)][string]$UbuntuIso, [Parameter(Mandatory)][string]$OpnsenseIso
)
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
# name, vCPU, startup RAM, max RAM, disk GB, ISO, windows11?
$vms = @(
 @('FW01', 1, 512MB, 1GB, 8,  $OpnsenseIso, $false),
 @('DC01', 2, 1GB,   2GB, 40, $ServerIso,   $false),
 @('DC02', 2, 1GB,   2GB, 40, $ServerIso,   $false),
 @('FS01', 2, 1GB,   2GB, 60, $ServerIso,   $false),
 @('LNX01',1, 512MB, 1GB, 20, $UbuntuIso,   $false),
 @('WS01', 2, 2GB,   4GB, 64, $Win11Iso,    $true))
if (-not (Get-VMSwitch Halden-LAN -ErrorAction SilentlyContinue)) {
  if ($PSCmdlet.ShouldProcess('Halden-LAN','Create private switch')) { New-VMSwitch -Name Halden-LAN -SwitchType Private | Out-Null } }
foreach ($v in $vms) {
  $n,$cpu,$ram,$max,$gb,$iso,$w11 = $v
  if (Get-VM $n -ErrorAction SilentlyContinue) { Write-Verbose "$n exists, skipping"; continue }
  if (-not $PSCmdlet.ShouldProcess($n,'Create VM')) { continue }
  $vhd = Join-Path $VmRoot "$n\$n.vhdx"; New-Item -ItemType Directory -Force (Split-Path $vhd) | Out-Null
  New-VHD -Path $vhd -SizeBytes ($gb*1GB) -Dynamic | Out-Null
  New-VM -Name $n -Generation 2 -MemoryStartupBytes $ram -VHDPath $vhd -SwitchName Halden-LAN -Path $VmRoot | Out-Null
  Set-VMProcessor $n -Count $cpu
  Set-VMMemory $n -DynamicMemoryEnabled $true -MinimumBytes 512MB -MaximumBytes $max
  Add-VMDvdDrive $n -Path $iso
  Set-VMFirmware $n -FirstBootDevice (Get-VMDvdDrive $n)
  if ($n -eq 'FW01') { Add-VMNetworkAdapter $n -SwitchName 'Default Switch'; Set-VMFirmware $n -EnableSecureBoot Off }
  elseif ($n -eq 'LNX01') { Set-VMFirmware $n -SecureBootTemplate MicrosoftUEFICertificateAuthority }
  if ($w11) { Set-VMKeyProtector $n -NewLocalKeyProtector; Enable-VMTPM $n }
  Set-VM $n -AutomaticCheckpointsEnabled $false
  Write-Output "Created $n ($cpu vCPU, $($ram/1MB)-$($max/1MB) MB, $gb GB)"
}

<#
.SYNOPSIS
  Phase 6 - Windows 11 readiness inventory.
.DESCRIPTION
  Two modes:

    Live (default)  collects the real hardware facts (TPM, Secure Boot, UEFI, CPU, RAM, disk,
                    BIOS age, model) from the lab clients and classifies each one. Run this on
                    the few lab VMs; it is real evidence.

    Fleet           classifies every row of a device CSV with the same rules - for example the
                    SYNTHETIC fleet in data/synthetic-fleet.csv. The synthetic fleet is an
                    invented inventory for the fictional company Halden Distribution Ltd. and
                    every figure from it must be labelled synthetic. This mode contacts no host
                    and needs no domain.

  Classification: a device fails (replace) if it lacks TPM 2.0, Secure Boot, UEFI, a supported
  CPU generation (Intel 8th gen / AMD Zen+ or newer), 4 GB RAM or a 64 GB disk. A capable device
  already on Windows 11 is ready; a capable device on Windows 10 is an in-place upgrade.
.PARAMETER ComputerName
  Lab clients to inspect (Live mode). Defaults to WS01,WS02.
.PARAMETER FleetCsv
  Path to a device CSV (Fleet mode), for example ..\data\synthetic-fleet.csv.
.PARAMETER OutputPath
  Folder for the result CSV. Defaults to evidence\raw for Live, data\ for Fleet.
.PARAMETER Domain
  Lab domain DNS name (Live mode only). The script refuses to run outside it.
.EXAMPLE
  .\07-Get-Win11Readiness.ps1 -ComputerName WS01,WS02 -WhatIf
.EXAMPLE
  .\07-Get-Win11Readiness.ps1 -FleetCsv ..\data\synthetic-fleet.csv
.NOTES
  Live mode is read-only. Fleet mode is pure arithmetic over the CSV: the counts are a plain
  count of the synthetic file and are never presented as a measurement of real hardware.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Live')]
param(
    [Parameter(ParameterSetName = 'Live')]
    [string[]]$ComputerName = @('WS01', 'WS02'),

    [Parameter(ParameterSetName = 'Fleet', Mandatory = $true)]
    [string]$FleetCsv,

    [Parameter(ParameterSetName = 'Live')]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),

    [Parameter(ParameterSetName = 'Fleet')]
    [string]$FleetOutputPath = (Join-Path $PSScriptRoot '..\data'),

    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CpuGeneration {
    <# Best-effort mapping of a CPU model name to an Intel Core generation. Returns 0 when it
       cannot be determined, which the caller treats as "not supported" and the operator then
       checks against Microsoft's supported CPU list. AMD Ryzen 2000-series and newer are
       treated as generation 10 (supported); older AMD is 0. #>
    param([Parameter(Mandatory)][string]$Model)

    if ($Model -match '(?i)ryzen|epyc') {
        if ($Model -match '(?i)\b[3579]\s?(2|3|4|5|6|7|8|9)\d{3}') { return 10 }
        return 0
    }
    if ($Model -match '(?i)i[3579]-(\d+)') {
        $digits = $Matches[1]
        if ($digits.Length -ge 5) { return [int]$digits.Substring(0, 2) }
        if ($digits.Length -ge 4) {
            $two = [int]$digits.Substring(0, 2)
            if ($two -ge 10 -and $two -le 14) { return $two }
            return [int]$digits.Substring(0, 1)
        }
    }
    return 0
}

function Get-ReadinessStatus {
    param(
        [Parameter(Mandatory)][string]$OperatingSystem,
        [Parameter(Mandatory)][int]$CpuGeneration,
        [Parameter(Mandatory)][int]$RamGb,
        [Parameter(Mandatory)][int]$DiskGb,
        [Parameter(Mandatory)][double]$TpmVersion,
        [Parameter(Mandatory)][bool]$SecureBoot,
        [Parameter(Mandatory)][bool]$Uefi
    )

    $capable = ($TpmVersion -ge 2.0) -and $SecureBoot -and $Uefi -and ($CpuGeneration -ge 8) -and ($RamGb -ge 4) -and ($DiskGb -ge 64)
    if (-not $capable) { return 'replace' }
    if ($OperatingSystem -like 'Windows 11*') { return 'ready' }
    return 'upgrade'
}

function ConvertTo-IntSafe {
    param([string]$Value)
    $parsed = 0
    if ([int]::TryParse(($Value -replace '[^0-9]', ''), [ref]$parsed)) { return $parsed }
    return 0
}

if ($PSCmdlet.ParameterSetName -eq 'Live') {
    if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

    if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $rows = @()

    foreach ($computer in $ComputerName) {
        if (-not $PSCmdlet.ShouldProcess($computer, 'Collect Windows 11 readiness facts (read-only)')) { continue }
        try {
            $row = Invoke-Command -ComputerName $computer -ScriptBlock {
                $os    = Get-CimInstance -ClassName Win32_OperatingSystem
                $cpu   = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
                $sys   = Get-CimInstance -ClassName Win32_ComputerSystem
                $bios  = Get-CimInstance -ClassName Win32_BIOS
                $disk  = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -First 1
                $tpm   = Get-Tpm -ErrorAction SilentlyContinue
                $secureBoot = $false
                try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { $secureBoot = $false }
                $firmware = if ($null -ne $env:firmware_type) { $env:firmware_type } else { 'Unknown' }
                $ageMonths = if ($bios.ReleaseDate) { [int]((Get-Date) - $bios.ReleaseDate).TotalDays / 30 } else { -1 }

                [pscustomobject]@{
                    ComputerName     = $env:COMPUTERNAME
                    Model            = $sys.Model
                    OSCaption        = $os.Caption
                    OSBuild          = [int]$os.BuildNumber
                    CPU              = $cpu.Name
                    RAM_GB           = [int][math]::Round($sys.TotalPhysicalMemory / 1GB)
                    Disk_GB          = if ($disk) { [int][math]::Round($disk.Size / 1GB) } else { 0 }
                    TPMVersion       = if ($tpm -and $tpm.SpecVersion) { [double]($tpm.SpecVersion -replace '^2\.0.*', '2.0' -replace '^1\.2.*', '1.2') } else { 0.0 }
                    TPMReady         = if ($tpm) { [bool]$tpm.TpmReady } else { $false }
                    SecureBoot       = $secureBoot
                    FirmwareMode     = $firmware
                    DeviceAgeMonths  = $ageMonths
                    CapturedUtc      = (Get-Date).ToUniversalTime().ToString('s')
                }
            }
            $generation = Get-CpuGeneration -Model $row.CPU
            $row | Add-Member -NotePropertyName CPUGeneration -NotePropertyValue $generation
            $row | Add-Member -NotePropertyName Status -NotePropertyValue (Get-ReadinessStatus -OperatingSystem $row.OSCaption `
                -CpuGeneration $generation -RamGb $row.RAM_GB -DiskGb $row.Disk_GB -TpmVersion $row.TPMVersion `
                -SecureBoot $row.SecureBoot -Uefi ($row.FirmwareMode -eq 'UEFI'))
            $rows += $row
        }
        catch {
            Write-Warning ("Failed to inspect {0}: {1}" -f $computer, $_.Exception.Message)
        }
    }

    if ($rows.Count -eq 0) { throw 'No readiness data collected.' }
    $report = Join-Path $OutputPath ('p04-ph6-win11-readiness-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $rows | Export-Csv -Path $report -NoTypeInformation
    $rows | Format-Table ComputerName, Model, CPU, CPUGeneration, TPMVersion, SecureBoot, Status -AutoSize
    Write-Host "Live readiness written to $report"
    return
}

# ---- Fleet mode: classify a device CSV (for example the synthetic fleet) ----
if (-not (Test-Path -Path $FleetCsv)) { throw "Fleet CSV not found: $FleetCsv" }

$lines = Get-Content -Path $FleetCsv | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
$devices = @($lines | ConvertFrom-Csv)
if ($devices.Count -eq 0) { throw "No device rows found in $FleetCsv" }

$classified = foreach ($device in $devices) {
    $status = Get-ReadinessStatus -OperatingSystem ([string]$device.OS) `
        -CpuGeneration (ConvertTo-IntSafe $device.CPUGeneration) `
        -RamGb (ConvertTo-IntSafe $device.RAM_GB) `
        -DiskGb (ConvertTo-IntSafe $device.Disk_GB) `
        -TpmVersion ([double]($device.TPMVersion -as [double])) `
        -SecureBoot ("$($device.SecureBoot)" -in @('Yes', 'True', '1')) `
        -Uefi ("$($device.UEFI)" -in @('Yes', 'True', '1'))
    [pscustomobject]@{
        AssetID      = $device.AssetID
        Department   = $device.Department
        Model        = $device.Model
        OS           = $device.OS
        CPU          = $device.CPU
        CPUGeneration = ConvertTo-IntSafe $device.CPUGeneration
        TPMVersion   = $device.TPMVersion
        Status       = $status
    }
}

$summary = $classified | Group-Object Status | ForEach-Object {
    [pscustomobject]@{ Status = $_.Name; Devices = $_.Count }
}

Write-Host ''
Write-Host ("SYNTHETIC FLEET (invented inventory for the fictional Halden Distribution Ltd.) - {0} devices" -f $devices.Count)
$summary | Sort-Object Status | Format-Table -AutoSize
Write-Host 'These figures are a plain count of the synthetic CSV. They are not a measurement of real hardware.'

if ($PSCmdlet.ShouldProcess($FleetOutputPath, 'Write classified fleet CSV')) {
    if (-not (Test-Path -Path $FleetOutputPath)) { New-Item -ItemType Directory -Path $FleetOutputPath -Force | Out-Null }
    $classified | Export-Csv -Path (Join-Path $FleetOutputPath 'synthetic-fleet-classified.csv') -NoTypeInformation
    Write-Host ("Classified fleet written to {0}" -f (Join-Path $FleetOutputPath 'synthetic-fleet-classified.csv'))
}

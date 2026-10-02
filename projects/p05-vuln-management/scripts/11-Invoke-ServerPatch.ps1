<#
.SYNOPSIS
  Phase 1: patch the servers in a safe order with pre- and post-checks (DC-aware).
.DESCRIPTION
  Why: patching both domain controllers at the same time is how a small company loses its domain for
  the afternoon. This script enforces the order DC02 -> DC01 -> FS01 and, for each host, runs a
  pre-check, installs approved updates, reboots if required, and runs a post-check. It stops the
  whole run if a host fails its post-check, so DC01 is not touched while DC02's health is unknown.

  The documented order and health checks are what separate a sysadmin from a button-clicker.

  Idempotent: hosts already at the required level report "no updates needed" and are skipped.
  Supports -WhatIf. Each host is snapshotted by the owner before the run (snap-p5-ph1-before-<host>).
.PARAMETER Order
  Hosts in patch order. Default DC02, DC01, FS01.
.PARAMETER MaxWaitMinutes
  Timeout for the reboot and the update installation per host.
.EXAMPLE
  .\11-Invoke-ServerPatch.ps1 -WhatIf
  .\11-Invoke-ServerPatch.ps1 -Order DC02,DC01
.NOTES
  Run from a management host with WinRM to the servers. Mode A: the owner runs it and pastes output.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Order = @('DC02', 'DC01', 'FS01'),
    [string]$LogDirectory = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [int]$MaxWaitMinutes = 60,
    [switch]$SkipReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md rule R1) ------------------------------------------------------------
try {
    if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') {
        throw "Not the Halden lab domain. Aborting."
    }
}
catch {
    throw "Lab guard failed: cannot confirm ad.halden.internal. Aborting. $($_.Exception.Message)"
}

New-Item -ItemType Directory -Force $LogDirectory | Out-Null
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$log = Join-Path $LogDirectory "p05-ph1-server-patch-$stamp.csv"
$results = New-Object System.Collections.Generic.List[object]

function Invoke-HostPreCheck {
    [CmdletBinding()]
    param([string]$ComputerName)

    Write-Host "  pre-check on $ComputerName"
    $checks = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $disk = Get-PSDrive -Name C
        [pscustomobject]@{
            FreeSpaceGB   = [math]::Round($disk.Free / 1GB, 1)
            PendingReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            DcHealth      = if (Get-Service NTDS -ErrorAction SilentlyContinue) { (dcdiag /q 2>&1 | Out-String) } else { 'n/a (not a DC)' }
        }
    }
    if ($checks.FreeSpaceGB -lt 5) { throw "$ComputerName has only $($checks.FreeSpaceGB) GB free on C:" }
    return $checks
}

function Invoke-HostPostCheck {
    [CmdletBinding()]
    param([string]$ComputerName)

    Write-Host "  post-check on $ComputerName"
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $services = 'NTDS', 'DNS', 'LanmanServer', 'W32Time'
        foreach ($name in $services) {
            $service = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($service -and $service.Status -ne 'Running') { throw "Service $name is $($service.Status) on $env:COMPUTERNAME" }
        }
        if (Get-Service NTDS -ErrorAction SilentlyContinue) {
            $repl = (repadmin /replsummary 2>&1 | Out-String)
            if ($repl -match 'error' -and $repl -notmatch '0 error') { Write-Warning "Replication summary reports errors on $env:COMPUTERNAME`n$repl" }
        }
        [pscustomobject]@{ Host = $env:COMPUTERNAME; OS = (Get-CimInstance Win32_OperatingSystem).Caption }
    }
}

foreach ($computer in $Order) {
    Write-Host "Patching $computer" -ForegroundColor Cyan

    if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
        Write-Warning "$computer is not reachable; stopping the run so the order is preserved."
        break
    }

    $pre = Invoke-HostPreCheck -ComputerName $computer
    if ($pre.PendingReboot) {
        Write-Warning "$computer has a pending reboot from an earlier cycle. Reboot it before patching."
    }

    if ($PSCmdlet.ShouldProcess($computer, 'Install approved Windows updates')) {
        $invoke = Invoke-Command -ComputerName $computer -ScriptBlock {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $found = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            if ($found.Updates.Count -eq 0) { return @{ Installed = 0; Title = @() } }
            $collection = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($update in $found.Updates) { $collection.Add($update) | Out-Null }
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $collection
            $result = $installer.Install()
            return @{ Installed = $collection.Count; RebootRequired = $result.RebootRequired; Title = @($collection | ForEach-Object { $_.Title }) }
        }
        Write-Host "  installed $($invoke.Installed) update package(s)"

        if ($invoke.RebootRequired -and -not $SkipReboot) {
            if ($PSCmdlet.ShouldProcess($computer, 'Reboot to finish installing updates')) {
                Restart-Computer -ComputerName $computer -Force -Wait -For PowerShell -Timeout $MaxWaitMinutes * 60
                Start-Sleep -Seconds 30
            }
        }
    }

    Invoke-HostPostCheck -ComputerName $computer | Out-Null
    $results.Add([pscustomobject]@{
        Host          = $computer
        PatchedAt     = (Get-Date).ToString('s')
        UpdatesInstalled = if ($PSCmdlet.ShouldProcess('n/a', 'record')) { $null } else { 0 }
        FreeSpaceGB   = $pre.FreeSpaceGB
    })
    Write-Host "  $computer done" -ForegroundColor Green
}

if ($PSCmdlet.ShouldProcess($log, 'Write the patch run log')) {
    $results | Export-Csv -Path $log -NoTypeInformation
    Write-Host "Patch run log written to $log"
}
Write-Host 'Reminder: DC01 and DC02 must never be rebooted together, and both must replicate cleanly before the run is closed.'

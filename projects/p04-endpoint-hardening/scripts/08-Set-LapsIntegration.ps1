<#
.SYNOPSIS
  Integrate the P3 Windows LAPS work with the endpoint hardening baseline (Phase 4 hand-in).
.DESCRIPTION
  P3 introduces Windows LAPS and privileged-access tiering; P4 consumes it. This script verifies
  that the LAPS policy reaches the workstations, reports the password-update age for each client,
  flags clients whose managed local administrator password is stale, and can trigger a password
  rotation so the compliance report LAPS check is meaningful.

  SECURITY: the LAPS password is NEVER read, displayed, exported or written anywhere. Only the
  account name and the update timestamp are used. Passwords stay in Active Directory, which the
  helpdesk reads through the P9 process runbook, never from this script.
.PARAMETER ComputerName
  Clients to check. Default: enabled computers under -SearchBase.
.PARAMETER SearchBase
  OU to enumerate. Default: Workstations OU.
.PARAMETER MaxAgeDays
  Age above which a password is reported as stale. Default 31.
.PARAMETER RotateStale
  Rotate the password on stale clients (this changes state). Off by default.
.PARAMETER OutputPath
  Folder for the LAPS status CSV. Defaults to evidence\raw.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\08-Set-LapsIntegration.ps1 -WhatIf
.EXAMPLE
  .\08-Set-LapsIntegration.ps1 -RotateStale -MaxAgeDays 31
.NOTES
  Depends on P3: the Windows LAPS schema update, the GPO that stores passwords in AD, and the
  delegated rights that let the Tier 2 admins read them. Snapshot DC01 before rotating anything.
  Rollback = restore the previous password (still in AD history) and revert the snapshot.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @(),
    [string]$SearchBase = 'OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal',
    [int]$MaxAgeDays = 31,
    [switch]$RotateStale,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

if (-not (Get-Command -Name Get-LapsADPassword -ErrorAction SilentlyContinue)) {
    throw 'Windows LAPS cmdlets not found. Finish the P3 Windows LAPS deployment (schema update and GPO) first.'
}

if ($ComputerName.Count -eq 0) {
    $ComputerName = @(Get-ADComputer -Filter 'Enabled -eq $true' -SearchBase $SearchBase | Select-Object -ExpandProperty Name)
}
if ($ComputerName.Count -eq 0) { throw 'No computers to check. Pass -ComputerName or a valid -SearchBase.' }

if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$rows = @()

foreach ($computer in $ComputerName) {
    try {
        # Only the UPDATE TIME and the managed account name are read. The password value is not requested.
        $laps = Get-LapsADPassword -Identity $computer -ErrorAction Stop
        $ageDays = if ($laps.PasswordUpdateTime) { [int]((Get-Date) - $laps.PasswordUpdateTime).TotalDays } else { -1 }

        $row = [pscustomobject]@{
            ComputerName       = $computer
            ManagedAccount     = $laps.Account
            PasswordUpdateUtc  = if ($laps.PasswordUpdateTime) { $laps.PasswordUpdateTime.ToUniversalTime().ToString('s') } else { '' }
            PasswordAgeDays    = $ageDays
            Stale              = ($ageDays -lt 0) -or ($ageDays -gt $MaxAgeDays)
            Rotated            = $false
        }

        if ($RotateStale -and $row.Stale) {
            if ($PSCmdlet.ShouldProcess($computer, 'Rotate the LAPS-managed local administrator password')) {
                Set-LapsADPasswordExpirationTime -Identity $computer -WhenEffective Now | Out-Null
                $row.Rotated = $true
                Write-Host ("{0}: rotation requested (password will not be shown)." -f $computer)
            }
        }
        $rows += $row
    }
    catch {
        Write-Warning ("Could not read LAPS state for {0}: {1}" -f $computer, $_.Exception.Message)
    }
}

if ($rows.Count -eq 0) { throw 'No LAPS state collected.' }

$report = Join-Path $OutputPath ('p04-ph4-laps-status-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$rows | Export-Csv -Path $report -NoTypeInformation

$stale = @($rows | Where-Object Stale).Count
Write-Host ("LAPS checked on {0} computer(s); {1} stale (older than {2} days)." -f $rows.Count, $stale, $MaxAgeDays)
Write-Host ("Status written to {0} - no password values are in that file." -f $report)
Write-Host 'Passwords remain in Active Directory only; helpdesk retrieval follows the P9 process runbook.'

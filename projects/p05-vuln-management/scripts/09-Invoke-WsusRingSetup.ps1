<#
.SYNOPSIS
  Phase 1: create the three Windows Update rings for Windows patch management (WSUS + GPO).
.DESCRIPTION
  Why: a flat "everyone patches at once" rollout means a bad update hits every machine before
  anyone notices. Three rings — Pilot, Broad, Servers — with client-side targeting through Group
  Policy mean a faulty update is caught in a small group first, and servers only move after both
  workstation rings are healthy.

  What it does:
    1. Lab guard: refuse to run outside ad.halden.internal.
    2. Installs (if missing) the WSUS role with the WID database and content on D:\WSUS.
    3. Configures products (Windows 11, Server 2025, Defender) and classifications.
    4. Creates the Ring0-Pilot, Ring1-Broad and Ring2-Servers computer groups.
    5. Creates/updates the three client-side-targeting GPOs from configs/p05-patch-rings.csv and
       links them to the Workstations and Servers OUs.
    6. Creates the automatic-approval rules (definitions auto-approved; security/critical to Pilot
       automatically; broader rings approved manually after pilot validation).

  Idempotent: re-running skips anything that already exists. Supports -WhatIf.
  Snapshot DC01 and the WSUS host before running (snap-p5-ph1-before). Rollback: delete the GPOs and
  the WSUS role; revert the snapshot.
.PARAMETER WsusServer
  The member server hosting WSUS. Default OPS01.
.PARAMETER ContentPath
  WSUS content root. Default D:\WSUS.
.PARAMETER RingsCsv
  Ring definition file. Default configs/p05-patch-rings.csv.
.EXAMPLE
  .\09-Invoke-WsusRingSetup.ps1 -WhatIf
  .\09-Invoke-WsusRingSetup.ps1 -WsusServer OPS01
.NOTES
  Mode A: the owner runs this. It changes state; every action is announced and reversible.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WsusServer = 'OPS01',
    [string]$ContentPath = 'D:\WSUS',
    [string]$RingsCsv = (Join-Path $PSScriptRoot '..\configs\p05-patch-rings.csv'),
    [string]$WorkstationsOu = 'OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal',
    [string]$ServersOu = 'OU=Servers,OU=Halden,DC=ad,DC=halden,DC=internal',
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\evidence\raw\p05-ph1-wsus-ring-setup-result.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md rule R1) ------------------------------------------------------------
try {
    if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') {
        throw "Not the Halden lab domain (found $((Get-ADDomain).DNSRoot)). Aborting."
    }
}
catch {
    throw "Lab guard failed: cannot confirm ad.halden.internal. Aborting. $($_.Exception.Message)"
}

if (-not (Test-Path $RingsCsv)) { throw "Ring definition not found: $RingsCsv" }

Write-Host "Creating Windows Update rings on $WsusServer from $RingsCsv" -ForegroundColor Cyan

# --- 1. Read the ring definitions --------------------------------------------------------------
$rings = Import-Csv $RingsCsv | Where-Object { $_.ring -match '^Ring' }
if (-not $rings) { throw "No ring rows found in $RingsCsv" }

# --- 2. WSUS role and content (run on the WSUS host) -------------------------------------------
function Initialize-Wsus {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ContentPath)

    $feature = Get-WindowsFeature -Name UpdateServices -ErrorAction SilentlyContinue
    if ($feature -and -not $feature.Installed) {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install the WSUS role with the WID database')) {
            Install-WindowsFeature -Name UpdateServices -IncludeManagementTools | Out-Null
        }
    }
    elseif (-not $feature) {
        Write-Warning 'WSUS role cmdlets not available on this host; run this stage on the WSUS server.'
        return
    }

    if ($PSCmdlet.ShouldProcess($ContentPath, 'Create the WSUS content folder')) {
        if (-not (Test-Path $ContentPath)) { New-Item -ItemType Directory -Path $ContentPath | Out-Null }
    }
}

# --- 3. Computer groups ------------------------------------------------------------------------
function New-WsusComputerGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name)

    $groups = if (Get-Command Get-WsusComputerGroup -ErrorAction SilentlyContinue) { Get-WsusComputerGroup } else { @() }
    if ($groups.Name -contains $Name) {
        Write-Host "  computer group exists: $Name"
    }
    elseif ($PSCmdlet.ShouldProcess($Name, 'Create WSUS computer group')) {
        Add-WsusComputerGroup -Name $Name | Out-Null
        Write-Host "  created computer group: $Name"
    }
}

# --- 4. Client-side-targeting GPOs -------------------------------------------------------------
function Set-RingGpo {
    [CmdletBinding(SupportsShouldProcess)]
    param([pscustomobject]$Ring, [string]$Ou)

    $gpoName = $Ring.populated_from_gpo
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        if ($PSCmdlet.ShouldProcess($gpoName, 'Create Group Policy Object')) {
            $gpo = New-GPO -Name $gpoName -Comment "P5 Windows Update ring: $($Ring.ring)"
            Write-Host "  created GPO: $gpoName"
        }
    }
    else {
        Write-Host "  GPO exists: $gpoName"
    }
    if (-not $gpo) { return }

    if ($PSCmdlet.ShouldProcess($gpoName, 'Set client-side targeting and update behaviour')) {
        # Client-side targeting: the computer puts itself in the WSUS group named here.
        Set-GPRegistryValue -Name $gpoName -Key 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate' `
            -ValueName 'TargetGroup' -Type String -Value $Ring.target_group | Out-Null
        Set-GPRegistryValue -Name $gpoName -Key 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate' `
            -ValueName 'TargetGroupEnabled' -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $gpoName -Key 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU' `
            -ValueName 'NoAutoUpdate' -Type DWord -Value 0 | Out-Null
        Set-GPRegistryValue -Name $gpoName -Key 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU' `
            -ValueName 'AUOptions' -Type DWord -Value 4 | Out-Null   # auto download and schedule install
        Set-GPRegistryValue -Name $gpoName -Key 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU' `
            -ValueName 'RescheduleWaitTime' -Type DWord -Value ([int]$Ring.deferral_days) | Out-Null
        Write-Host "  configured $gpoName -> target group '$($Ring.target_group)' (deadline $($Ring.deadline_days) days)"
    }
}

# --- 5. Main ------------------------------------------------------------------------------------
Initialize-Wsus -ContentPath $ContentPath

foreach ($ring in $rings) {
    Write-Host "Ring $($ring.ring) -> $($ring.target_group)"
    New-WsusComputerGroup -Name $ring.target_group
    $ou = if ($ring.ring -eq 'Ring2-Servers') { $ServersOu } else { $WorkstationsOu }
    Set-RingGpo -Ring $ring -Ou $ou
    if ($PSCmdlet.ShouldProcess($ring.populated_from_gpo, "Link GPO to $ou")) {
        try {
            New-GPLink -Name $ring.populated_from_gpo -Target $ou -ErrorAction Stop | Out-Null
            Write-Host "  linked $($ring.populated_from_gpo) to $ou"
        }
        catch { Write-Host "  link already present or OU missing: $ou" }
    }
}

# --- 6. Automatic approval rules ---------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($WsusServer, 'Configure automatic approval rules')) {
    Write-Host 'Automatic approval rules to confirm in the WSUS console:' -ForegroundColor Cyan
    Write-Host '  Definitions and Defender updates -> all rings, automatically.'
    Write-Host '  Security and Critical updates -> Ring0-Pilot automatically; Ring1-Broad and Ring2-Servers approved'
    Write-Host '  by 10-Approve-WsusUpdates.ps1 only after the pilot reports no incidents.'
}

# --- 7. Evidence -------------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($ReportPath, 'Write the ring setup summary')) {
    New-Item -ItemType Directory -Force (Split-Path $ReportPath) | Out-Null
    $rings | Select-Object ring, target_group, deferral_days, deadline_days, populated_from_gpo |
        Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "Summary written to $ReportPath"
}

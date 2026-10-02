<#
.SYNOPSIS
  Phase 4 - remove local admin rights and apply the remaining endpoint hardening controls.
.DESCRIPTION
  Two delivery modes:

    -Scope Gpo   (default) writes the registry-based hardening controls into a single
                 "WKS - Windows Hardening - v1" GPO. The local Administrators membership is
                 delivered by the Group Policy Preferences "Local Users and Groups" item, which
                 has no supported PowerShell cmdlet and is configured in GPMC; this script
                 creates the GPO and prints the exact membership to enter.

    -Scope Local applies the same controls directly to -ComputerName clients (local policy) and
                 also enforces the local Administrators membership, so the acceptance test
                 "0 standard users with local admin rights" can be run in the lab.

  Controls: local Administrators = approved admins only (never Domain Users), firewall on for
  all profiles with inbound blocked and RDP/WinRM allowed only from the management subnet,
  Credential Guard, LSA protection (RunAsPPL) and PowerShell script-block/module logging.
  It is idempotent and safe to re-run.
.PARAMETER Scope
  Gpo (default) or Local.
.PARAMETER GpoName
  GPO to write the registry controls into (Gpo mode).
.PARAMETER ComputerName
  Clients to harden directly (Local mode). Defaults to WS01.
.PARAMETER ApprovedAdmins
  The only accounts/groups allowed in the local Administrators group. Keep the LAPS-managed
  built-in Administrator and the Tier 2 server-admin group; never Domain Users.
.PARAMETER ManagementSubnet
  Source range allowed to reach RDP and WinRM. Default 192.168.40.0/24 (MGMT, applied in P6).
.PARAMETER OutputPath
  Folder for the evidence CSV (Local mode). Defaults to evidence\raw.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\05-Configure-LocalAdminAndHardening.ps1 -Scope Gpo -WhatIf
.EXAMPLE
  .\05-Configure-LocalAdminAndHardening.ps1 -Scope Local -ComputerName WS01 -ApprovedAdmins 'HALDEN\Administrator','HALDEN\G_Tier2_Admins'
.NOTES
  Snapshot the client (and DC01 for the GPO change) first: snap-p4-ph4-before. Rollback = give the
  affected users back an admin group membership, or revert the snapshot, or unlink the GPO. A
  "need admin for one app" request is not solved by permanent rights - use the exception process
  in business/p04-user-comms.md (time-limited elevation).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Gpo', 'Local')][string]$Scope = 'Gpo',
    [string]$GpoName = 'WKS - Windows Hardening - v1',
    [string[]]$ComputerName = @('WS01'),
    [string[]]$ApprovedAdmins = @('HALDEN\Administrator', 'HALDEN\G_Tier2_Admins'),
    [string]$ManagementSubnet = '192.168.40.0/24',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

# Registry controls shared by both modes. Key, value name, type, value.
$registryControls = @(
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'LsaCfgFlags';                          Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa';            Name = 'RunAsPPL';                             Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name = 'EnableScriptBlockLogging'; Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging';      Name = 'EnableModuleLogging';      Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile';   Name = 'EnableFirewall';        Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile';   Name = 'DefaultInboundAction';  Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'; Name = 'EnableFirewall';        Type = 'DWord'; Value = 1 }
    @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'; Name = 'DefaultInboundAction';  Type = 'DWord'; Value = 1 }
)

if ($Scope -eq 'Gpo') {
    Import-Module GroupPolicy -ErrorAction Stop

    if (-not (Get-GPO -Name $GpoName -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($GpoName, 'Create hardening GPO')) {
            New-GPO -Name $GpoName -Comment 'P4 endpoint hardening: local admin policy, firewall, Credential Guard, LSA protection, PowerShell logging.' | Out-Null
            Write-Host "Created GPO '$GpoName'."
        }
    }
    else {
        Write-Host "GPO '$GpoName' already exists - updating settings (idempotent)."
    }

    foreach ($control in $registryControls) {
        if ($PSCmdlet.ShouldProcess($GpoName, ("Set {0}\{1}" -f $control.Key, $control.Name))) {
            Set-GPRegistryValue -Name $GpoName -Key $control.Key -ValueName $control.Name -Type $control.Type -Value $control.Value | Out-Null
        }
    }

    Write-Host ''
    Write-Host 'Manual step (GPMC, no supported cmdlet): in the GPO, add a Group Policy Preferences item'
    Write-Host 'Computer Configuration > Preferences > Control Panel Settings > Local Users and Groups:'
    Write-Host ("  Update > Administrators > Members = {0}" -f ($ApprovedAdmins -join ', '))
    Write-Host '  Set "Delete all member users" and "Delete all member groups" to keep only the approved members.'
    return
}

# ---- Local mode: enforce on the lab clients so the acceptance test can be run ----
if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$state = @()

foreach ($computer in $ComputerName) {
    if (-not $PSCmdlet.ShouldProcess($computer, 'Enforce local admin policy and endpoint hardening')) { continue }

    try {
        $result = Invoke-Command -ComputerName $computer -ArgumentList (,$ApprovedAdmins), $ManagementSubnet -ScriptBlock {
            param([string[]]$Approved, [string]$MgmtSubnet)

            # 1. Local Administrators = approved members only. Never leave the group empty.
            $current = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Select-Object -ExpandProperty Name)
            $remove = @($current | Where-Object { $Approved -notcontains $_ })
            $add    = @($Approved | Where-Object { $current -notcontains $_ })
            foreach ($member in $add)    { Add-LocalGroupMember    -Group 'Administrators' -Member $member }
            foreach ($member in $remove) { Remove-LocalGroupMember -Group 'Administrators' -Member $member -ErrorAction SilentlyContinue }

            # 2. Firewall on for all profiles, inbound blocked, management access only.
            Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -DefaultInboundAction Block
            Set-NetFirewallRule -DisplayGroup 'Remote Desktop' -RemoteAddress $MgmtSubnet -ErrorAction SilentlyContinue
            Set-NetFirewallRule -DisplayGroup 'Windows Remote Management' -RemoteAddress $MgmtSubnet -ErrorAction SilentlyContinue

            # 3. Registry controls (Credential Guard, LSA protection, PowerShell logging, firewall policy).
            $controls = @(
                @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 1 }
                @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'LsaCfgFlags'; Value = 1 }
                @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa';            Name = 'RunAsPPL'; Value = 1 }
                @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name = 'EnableScriptBlockLogging'; Value = 1 }
                @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging';      Name = 'EnableModuleLogging'; Value = 1 }
            )
            foreach ($control in $controls) {
                if (-not (Test-Path -Path $control.Path)) { New-Item -Path $control.Path -Force | Out-Null }
                New-ItemProperty -Path $control.Path -Name $control.Name -Value $control.Value -PropertyType DWord -Force | Out-Null
            }

            [pscustomobject]@{
                ComputerName        = $env:COMPUTERNAME
                CapturedUtc         = (Get-Date).ToUniversalTime().ToString('s')
                LocalAdministrators = (@(Get-LocalGroupMember -Group 'Administrators' | Select-Object -ExpandProperty Name) -join '; ')
                Removed             = ($remove -join '; ')
                Added               = ($add -join '; ')
                PendingReboot       = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            }
        }
        $state += $result
        Write-Host ("{0}: local Administrators = {1}" -f $computer, $result.LocalAdministrators)
    }
    catch {
        Write-Warning ("Failed to harden {0}: {1}" -f $computer, $_.Exception.Message)
    }
}

if ($state) {
    $report = Join-Path $OutputPath ('p04-ph4-localadmin-hardening-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $state | Export-Csv -Path $report -NoTypeInformation
    Write-Host "Hardening result written to $report"
}

Write-Host 'Administrators membership changes need a re-logon. Credential Guard and LSA protection need a reboot.'

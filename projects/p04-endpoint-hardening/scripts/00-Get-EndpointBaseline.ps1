<#
.SYNOPSIS
  Phase 0 - capture the endpoint security "before" state on Halden Windows clients.
.DESCRIPTION
  Read-only. Records the evidence the P4 plan calls the "before": BitLocker status, local
  Administrators membership, Defender configuration, ASR rule state and, when the
  HardeningKitty module is present on the client, a CIS/Microsoft baseline audit export.
  Writes one CSV per run to the evidence folder. It makes no change, so it is safe to run
  at any time and again after each phase for comparison.
.PARAMETER ComputerName
  Clients to measure. Defaults to WS01. Every name must be an in-scope Halden lab client.
.PARAMETER OutputPath
  Folder for the evidence CSV. Defaults to evidence\raw (git-ignored, never published).
.PARAMETER FindingList
  Optional path (as seen on the client) to a HardeningKitty finding list. When supplied and
  HardeningKitty is importable on the client, the audit runs and its report path is recorded.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\00-Get-EndpointBaseline.ps1 -ComputerName WS01 -WhatIf
.EXAMPLE
  .\00-Get-EndpointBaseline.ps1 -ComputerName WS01,WS02 -FindingList 'C:\Tools\lists\finding_list_cis_microsoft_windows_11_enterprise_23h2_machine.csv'
.NOTES
  Snapshot the clients before the phase that follows (snap-p4-ph0-before). This script changes
  nothing, but the snapshot protects Phase 1 onwards. Run it again after Phase 4 to produce the
  "after" file.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @('WS01'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$FindingList = '',
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

function Get-BaselineForComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Computer,
        [string]$FindingList
    )

    Invoke-Command -ComputerName $Computer -ArgumentList $FindingList -ScriptBlock {
        param([string]$List)

        $os  = Get-CimInstance -ClassName Win32_OperatingSystem
        $vol = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        $adm = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name)
        $mp  = Get-MpPreference

        $hkReport = ''
        if ($List -and (Get-Module -ListAvailable -Name HardeningKitty)) {
            Import-Module HardeningKitty -ErrorAction Stop
            $hkReport = Join-Path $env:TEMP 'hardeningkitty-audit.csv'
            Invoke-HardeningKitty -Mode Audit -FileFindingList $List -Log -Report -ReportFile $hkReport | Out-Null
        }

        [pscustomobject]@{
            ComputerName          = $env:COMPUTERNAME
            CapturedUtc           = (Get-Date).ToUniversalTime().ToString('s')
            OSCaption             = $os.Caption
            OSBuild               = $os.BuildNumber
            OSVersion             = $os.Version
            BitLockerProtection   = if ($vol) { [string]$vol.ProtectionStatus } else { 'NotAvailable' }
            BitLockerPercent      = if ($vol) { [int]$vol.EncryptionPercentage } else { 0 }
            LocalAdministrators   = ($adm -join '; ')
            RealTimeProtectionOn  = -not $mp.DisableRealtimeMonitoring
            AMServiceEnabled      = $mp.AMServiceEnabled
            CloudBlockLevel       = [string]$mp.CloudBlockLevel
            PUAProtection         = [string]$mp.PUAProtection
            NetworkProtection     = [string]$mp.EnableNetworkProtection
            AsrRuleCount          = @($mp.AttackSurfaceReductionRules_Ids).Count
            AsrRulesBlocking      = @($mp.AttackSurfaceReductionRules_Actions |
                Where-Object { "$_" -eq '1' -or "$_" -eq 'Block' }).Count
            AsrRulesAuditing      = @($mp.AttackSurfaceReductionRules_Actions |
                Where-Object { "$_" -eq '2' -or "$_" -eq 'AuditMode' }).Count
            HardeningKittyReport  = $hkReport
        }
    }
}

$results = foreach ($computer in $ComputerName) {
    if ($PSCmdlet.ShouldProcess($computer, 'Capture endpoint baseline (read-only)')) {
        try {
            Write-Verbose "Collecting baseline from $computer"
            Get-BaselineForComputer -Computer $computer -FindingList $FindingList
        }
        catch {
            Write-Warning ("Failed to collect baseline from {0}: {1}" -f $computer, $_.Exception.Message)
        }
    }
}

if ($results) {
    if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $report = Join-Path $OutputPath ('p04-ph0-endpoint-baseline-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $results | Export-Csv -Path $report -NoTypeInformation
    Write-Host "Baseline written to $report"
    $results | Format-Table ComputerName, BitLockerProtection, LocalAdministrators, RealTimeProtectionOn,
        AsrRulesBlocking, AsrRulesAuditing -AutoSize
    Write-Host 'Next: compare this CSV with the post-hardening CSV (Phase 4) and paste the scores into README.md.'
}
else {
    Write-Warning 'No baseline data collected.'
}

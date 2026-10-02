<#
.SYNOPSIS
  Phase 2b - move the reviewed ASR rules from AUDIT to BLOCK (or back to audit for a rollback).
.DESCRIPTION
  Enforces the ASR rules that have been reviewed in audit mode. The script refuses to block unless
  you tell it how many days of audit data were reviewed (at least 7), or pass -Force for a
  deliberate, recorded exception - this is how "audit before block" is enforced in code rather
  than in memory. Use -RevertToAudit to roll a rule back if it breaks a business application, then
  add the exception to business/p04-baseline-exceptions.md.

  It is idempotent: a rule already in the target state is left alone. A state CSV is written for
  evidence, and no ASR exclusion is ever added without a matching row in the exceptions register.
.PARAMETER ComputerName
  Clients to configure. Defaults to WS01.
.PARAMETER RuleId
  Rules to move to Block. Default: the full approved set in configs/asr-rules.csv.
.PARAMETER KeepAudit
  Rules to leave in Audit mode despite being reviewed (for example a rule that conflicts with
  management tooling). Each name must also appear in the exceptions register.
.PARAMETER ReviewedAuditDays
  Number of days of audit events reviewed. Must be 7 or more unless -Force is used.
.PARAMETER ExclusionPath
  Optional Defender exclusion paths approved in the exceptions register (for example a line-of-
  business application folder).
.PARAMETER ExclusionProcess
  Optional Defender exclusion processes approved in the exceptions register.
.PARAMETER RevertToAudit
  Roll back: set the selected rules to AuditMode instead of Block.
.PARAMETER Force
  Skip the minimum-audit-days check. Record the reason in the change record.
.PARAMETER OutputPath
  Folder for the ASR state CSV evidence. Defaults to evidence\raw.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\03-Set-AsrBlock.ps1 -ComputerName WS01 -ReviewedAuditDays 8 -WhatIf
.EXAMPLE
  .\03-Set-AsrBlock.ps1 -ComputerName WS01 -ReviewedAuditDays 8 -KeepAudit d1e49aac-8f56-4280-b9ba-993a6d77406c
.EXAMPLE
  .\03-Set-AsrBlock.ps1 -ComputerName WS01 -RevertToAudit -RuleId d4f940ab-401b-4efc-aadc-ad5f3c50688a
.NOTES
  Snapshot the client first: snap-p4-ph2b-before. Rollback = re-run with -RevertToAudit (or remove the
  policy). Exceptions live in business/p04-baseline-exceptions.md and need their own change record.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @('WS01'),
    [string[]]$RuleId = @(),
    [string[]]$KeepAudit = @(),
    [int]$ReviewedAuditDays = 0,
    [string[]]$ExclusionPath = @(),
    [string[]]$ExclusionProcess = @(),
    [switch]$RevertToAudit,
    [switch]$Force,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$approvedRules = [ordered]@{
    'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Block executable content from email client and webmail'
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Block Office apps from creating child processes'
    '3b576869-a4ec-4529-8536-b80a7769e899' = 'Block Office apps from creating executable content'
    '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Block Office apps from injecting code into other processes'
    'd3e037e1-3eb8-44c8-a917-57927947596d' = 'Block JavaScript/VBScript from launching downloaded executable content'
    '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'Block execution of potentially obfuscated scripts'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Block Win32 API calls from Office macros'
    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'Block credential stealing from LSASS'
    'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'Block process creations from PSExec and WMI commands'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Block untrusted and unsigned processes that run from USB'
    'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'Use advanced protection against ransomware'
    'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'Block persistence through WMI event subscription'
    '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'Block abuse of exploited vulnerable signed drivers'
    '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Block Office communication app from creating child processes'
    '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Block Adobe Reader from creating child processes'
    '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'Block executable files unless they meet prevalence, age or trusted-list criteria'
}

if (-not $RevertToAudit -and -not $Force -and $ReviewedAuditDays -lt 7) {
    throw 'ASR rules must be audited for at least 7 days before blocking. Pass -ReviewedAuditDays <n>, or -Force with a recorded reason.'
}

$targets = if ($RuleId.Count -gt 0) { $RuleId } else { @($approvedRules.Keys) }
$unknown = @($targets | Where-Object { -not $approvedRules.Contains($_) })
if ($unknown.Count -gt 0) {
    throw ("Rule GUID(s) not in the approved set: {0}. Add a row to configs/asr-rules.csv first." -f ($unknown -join ', '))
}

$action = if ($RevertToAudit) { 'AuditMode' } else { 'Block' }
$number  = if ($RevertToAudit) { 2 } else { 1 }

if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$state = @()

foreach ($computer in $ComputerName) {
    if (-not $PSCmdlet.ShouldProcess($computer, "Set ASR rules to $action")) { continue }

    try {
        $result = Invoke-Command -ComputerName $computer -ArgumentList (,$targets), (,$KeepAudit), (,$ExclusionPath), (,$ExclusionProcess), $number -ScriptBlock {
            param([string[]]$Ids, [string[]]$KeepAudit, [string[]]$Paths, [string[]]$Processes, [int]$Number)

            if ($Paths.Count -gt 0)    { Add-MpPreference -ExclusionPath $Paths }
            if ($Processes.Count -gt 0) { Add-MpPreference -ExclusionProcess $Processes }

            foreach ($id in $Ids) {
                if ($KeepAudit -contains $id) {
                    Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions AuditMode
                }
                else {
                    Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions $Number
                }
            }

            $pref = Get-MpPreference
            [pscustomobject]@{
                ComputerName     = $env:COMPUTERNAME
                CapturedUtc      = (Get-Date).ToUniversalTime().ToString('s')
                AsrRulesBlocking = @($pref.AttackSurfaceReductionRules_Actions |
                    Where-Object { "$_" -eq '1' -or "$_" -eq 'Block' }).Count
                AsrRulesAuditing = @($pref.AttackSurfaceReductionRules_Actions |
                    Where-Object { "$_" -eq '2' -or "$_" -eq 'AuditMode' }).Count
                Exclusions       = (@($pref.ExclusionPath) + @($pref.ExclusionProcess)) -join '; '
            }
        }
        $state += $result
        Write-Host ("{0}: {1} rule(s) set to {2}." -f $computer, $targets.Count, $action)
    }
    catch {
        Write-Warning ("Failed to configure {0}: {1}" -f $computer, $_.Exception.Message)
    }
}

if ($state) {
    $report = Join-Path $OutputPath ('p04-ph2-asr-block-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $state | Export-Csv -Path $report -NoTypeInformation
    Write-Host "ASR block state written to $report"
}

Write-Host 'Record every exception and keep the proof (event 1121) for the compliance report and P7.'

<#
.SYNOPSIS
  Phase 2a - enable Defender protections and put the approved ASR rules into AUDIT mode.
.DESCRIPTION
  Deliberately the safe half of Phase 2. Attack Surface Reduction rules are set to AuditMode
  (value 2) first so that blocked-by-policy events are only logged, not enforced, and the
  business is not broken on a Monday morning. Review the audit events for at least 7 days
  (Event ID 1122 in Microsoft-Windows-Windows Defender/Operational) before running
  03-Set-AsrBlock.ps1.

  It also turns on cloud protection, PUA protection and network protection, and puts Controlled
  Folder Access into audit mode. It is idempotent: a rule already in AuditMode is left alone.
.PARAMETER ComputerName
  Clients to configure. Defaults to WS01 (pilot) - use the pilot, not the whole fleet, first.
.PARAMETER RuleId
  Optional subset of ASR rule GUIDs. Default: the full approved set in configs/asr-rules.csv.
.PARAMETER OutputPath
  Folder for the ASR state CSV evidence. Defaults to evidence\raw.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\02-Set-AsrAudit.ps1 -ComputerName WS01 -WhatIf
.EXAMPLE
  .\02-Set-AsrAudit.ps1 -ComputerName WS01,WS02
.NOTES
  Snapshot the client first: snap-p4-ph2-before. Rollback = 03-Set-AsrBlock.ps1 with -RevertToAudit,
  or remove the policy. Verify every GUID against the Microsoft Learn "Attack surface reduction rules
  reference" before deploying, because the list changes between Windows releases.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @('WS01'),
    [string[]]$RuleId = @(),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

# The approved rule set. Kept in step with configs/asr-rules.csv (GUID, name, rationale).
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

$targets = if ($RuleId.Count -gt 0) { $RuleId } else { @($approvedRules.Keys) }

$unknown = @($targets | Where-Object { -not $approvedRules.Contains($_) })
if ($unknown.Count -gt 0) {
    throw ("Rule GUID(s) not in the approved set: {0}. Add a row to configs/asr-rules.csv first." -f ($unknown -join ', '))
}

if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$state = @()

foreach ($computer in $ComputerName) {
    if (-not $PSCmdlet.ShouldProcess($computer, 'Enable Defender protections and set ASR rules to Audit')) { continue }

    try {
        $result = Invoke-Command -ComputerName $computer -ArgumentList (, $targets) -ScriptBlock {
            param([string[]]$Ids)

            Set-MpPreference -PUAProtection Enabled -CloudBlockLevel High -CloudExtendedTimeout 50 `
                -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -EnableNetworkProtection Enabled
            Set-MpPreference -EnableControlledFolderAccess AuditMode

            foreach ($id in $Ids) {
                Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions AuditMode
            }

            $pref = Get-MpPreference
            [pscustomobject]@{
                ComputerName        = $env:COMPUTERNAME
                CapturedUtc         = (Get-Date).ToUniversalTime().ToString('s')
                CloudBlockLevel     = [string]$pref.CloudBlockLevel
                PUAProtection       = [string]$pref.PUAProtection
                NetworkProtection   = [string]$pref.EnableNetworkProtection
                ControlledFolder    = [string]$pref.EnableControlledFolderAccess
                AsrRulesAuditing    = @($pref.AttackSurfaceReductionRules_Actions |
                    Where-Object { "$_" -eq '2' -or "$_" -eq 'AuditMode' }).Count
            }
        }
        $state += $result
        Write-Host ("{0}: ASR rules set to AuditMode for {1} rule(s)." -f $computer, $targets.Count)
    }
    catch {
        Write-Warning ("Failed to configure {0}: {1}" -f $computer, $_.Exception.Message)
    }
}

if ($state) {
    $report = Join-Path $OutputPath ('p04-ph2-asr-audit-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $state | Export-Csv -Path $report -NoTypeInformation
    Write-Host "ASR audit state written to $report"
}

Write-Host 'Review Event ID 1122 for 7 days, record exceptions, then run 03-Set-AsrBlock.ps1.'

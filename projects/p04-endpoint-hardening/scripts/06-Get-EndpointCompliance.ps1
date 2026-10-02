<#
.SYNOPSIS
  Phase 5 - run the nine endpoint compliance checks and produce an HTML + CSV report.
.DESCRIPTION
  Runs the P4 control set against the workstations (or an explicit list) using remote
  PowerShell, evaluates each control against a pass condition, and writes a traffic-light HTML
  report plus a CSV for Power BI and the P10 monthly report. The overall figure is the plain
  percentage of checks passed - it is a measured result, never an estimate.

  Checks: OS build, BitLocker, Defender (real-time, signature age, quick-scan age), ASR rules
  all blocking, firewall profiles, local Administrators membership, LAPS password age, pending
  reboot, and days since the last patch.

  SECURITY: the LAPS check reads only the password-update timestamp. The LAPS password and any
  BitLocker recovery key are never read, printed or written to the report.
.PARAMETER ComputerName
  Computers to check. Default: every enabled computer account under -SearchBase.
.PARAMETER SearchBase
  OU to enumerate (used when -ComputerName is not given). Default: Workstations OU.
.PARAMETER ApprovedAdmins
  The only members allowed in local Administrators. Anything else fails the check.
.PARAMETER ApprovedAsrCount
  Number of ASR rules that must be blocking. Default 16.
.PARAMETER MinimumBuild
  Lowest supported Windows 11 build number. Default 22631 (Windows 11 23H2).
.PARAMETER MaxSignatureAgeHours
  Maximum Defender signature age in hours. Default 24.
.PARAMETER MaxPatchAgeDays
  Maximum days since the last patch was installed. Default 35.
.PARAMETER MaxLapsAgeDays
  Maximum LAPS password age in days. Default 31.
.PARAMETER OutputPath
  Folder for the HTML and CSV reports. Default: reports/ under the project folder.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\06-Get-EndpointCompliance.ps1 -ComputerName WS01,WS02 -WhatIf
.EXAMPLE
  .\06-Get-EndpointCompliance.ps1
.NOTES
  Read-only. Snapshot nothing for this phase; it measures. Run it after Phase 4 and schedule it
  daily on a management server. The trend over time feeds the P10 management report.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @(),
    [string]$SearchBase = 'OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal',
    [string[]]$ApprovedAdmins = @('HALDEN\Administrator', 'HALDEN\G_Tier2_Admins'),
    [int]$ApprovedAsrCount = 16,
    [int]$MinimumBuild = 22631,
    [int]$MaxSignatureAgeHours = 24,
    [int]$MaxPatchAgeDays = 35,
    [int]$MaxLapsAgeDays = 31,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\reports'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

if ($ComputerName.Count -eq 0) {
    $ComputerName = @(Get-ADComputer -Filter 'Enabled -eq $true' -SearchBase $SearchBase | Select-Object -ExpandProperty Name)
}
if ($ComputerName.Count -eq 0) { throw 'No computers to check. Pass -ComputerName or a -SearchBase that contains enabled computer accounts.' }

function Get-LapsPasswordAgeDays {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Computer)

    # Only the update time is read. The password value is never requested or returned.
    if (-not (Get-Command -Name Get-LapsADPassword -ErrorAction SilentlyContinue)) { return $null }
    try {
        $laps = Get-LapsADPassword -Identity $Computer -ErrorAction Stop
        if ($null -eq $laps -or $null -eq $laps.PasswordUpdateTime) { return $null }
        return [int]((Get-Date) - $laps.PasswordUpdateTime).TotalDays
    }
    catch {
        return $null
    }
}

function Get-CheckStatus {
    param([bool]$Pass, [string]$Detail)
    [pscustomobject]@{ Status = if ($Pass) { 'pass' } else { 'fail' }; Detail = $Detail }
}

function Invoke-ComplianceCheck {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Computer)

    try {
        $facts = Invoke-Command -ComputerName $Computer -ScriptBlock {
            $os   = Get-CimInstance -ClassName Win32_OperatingSystem
            $bl   = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
            $ms   = Get-MpComputerStatus
            $pref = Get-MpPreference
            $fw   = Get-NetFirewallProfile | Select-Object Name, Enabled
            $adm  = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            $patch = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
            $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                       (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

            [pscustomobject]@{
                OSBuild            = [int]$os.BuildNumber
                BitLockerStatus    = if ($bl) { [string]$bl.ProtectionStatus } else { 'NotAvailable' }
                BitLockerPercent   = if ($bl) { [int]$bl.EncryptionPercentage } else { 0 }
                RealTimeOn         = -not $pref.DisableRealtimeMonitoring
                SignatureAgeDays   = [int]$ms.AntivirusSignatureAge
                QuickScanAgeDays   = [int]$ms.QuickScanAge
                AsrBlocking        = @($pref.AttackSurfaceReductionRules_Actions | Where-Object { "$_" -eq '1' -or "$_" -eq 'Block' }).Count
                AsrAuditing        = @($pref.AttackSurfaceReductionRules_Actions | Where-Object { "$_" -eq '2' -or "$_" -eq 'AuditMode' }).Count
                FirewallProfiles   = (@($fw | Where-Object { $_.Enabled }).Name -join ',')
                LocalAdministrators = ($adm -join '; ')
                LastPatchDays      = if ($patch) { [int]((Get-Date) - $patch.InstalledOn).TotalDays } else { -1 }
                PendingReboot      = $pending
            }
        }
    }
    catch {
        Write-Warning ("Could not reach {0}: {1}" -f $Computer, $_.Exception.Message)
        return $null
    }

    $lapsAge = Get-LapsPasswordAgeDays -Computer $Computer
    $extraAdmins = @(($facts.LocalAdministrators -split '; ') | Where-Object { $_ -and ($ApprovedAdmins -notcontains $_) })

    $checks = [ordered]@{
        'OS build'          = Get-CheckStatus ([int]$facts.OSBuild -ge $MinimumBuild) ("build {0}" -f $facts.OSBuild)
        'BitLocker'         = Get-CheckStatus (($facts.BitLockerStatus -eq 'On') -and ($facts.BitLockerPercent -eq 100)) ("{0}, {1}% encrypted" -f $facts.BitLockerStatus, $facts.BitLockerPercent)
        'Defender'          = Get-CheckStatus ($facts.RealTimeOn -and ($facts.SignatureAgeDays * 24 -lt $MaxSignatureAgeHours) -and ($facts.QuickScanAgeDays -lt 7)) ("real-time={0}, signatures {1}d old, quick scan {2}d ago" -f $facts.RealTimeOn, $facts.SignatureAgeDays, $facts.QuickScanAgeDays)
        'ASR rules'         = Get-CheckStatus (($facts.AsrAuditing -eq 0) -and ($facts.AsrBlocking -ge $ApprovedAsrCount)) ("{0} blocking, {1} auditing" -f $facts.AsrBlocking, $facts.AsrAuditing)
        'Firewall'          = Get-CheckStatus ((@($facts.FirewallProfiles -split ',') | Where-Object { $_ }).Count -eq 3) ("enabled: {0}" -f $facts.FirewallProfiles)
        'Local admins'      = Get-CheckStatus ($extraAdmins.Count -eq 0) (if ($extraAdmins.Count -eq 0) { 'approved members only' } else { 'unapproved: {0}' -f ($extraAdmins -join ', ') })
        'LAPS'              = if ($null -eq $lapsAge) { [pscustomobject]@{ Status = 'notchecked'; Detail = 'LAPS cmdlet unavailable' } } else { Get-CheckStatus ($lapsAge -lt $MaxLapsAgeDays) ("password {0}d old" -f $lapsAge) }
        'Pending reboot'    = Get-CheckStatus (-not $facts.PendingReboot) ("pending={0}" -f $facts.PendingReboot)
        'Last patch'        = Get-CheckStatus (($facts.LastPatchDays -ge 0) -and ($facts.LastPatchDays -lt $MaxPatchAgeDays)) ("{0}d ago" -f $facts.LastPatchDays)
    }

    [pscustomobject]@{
        ComputerName = $Computer
        CheckedUtc   = (Get-Date).ToUniversalTime().ToString('s')
        Checks       = $checks
    }
}

$results = foreach ($computer in $ComputerName) {
    if ($PSCmdlet.ShouldProcess($computer, 'Run endpoint compliance checks (read-only)')) {
        Invoke-ComplianceCheck -Computer $computer
    }
}
$results = @($results | Where-Object { $_ })

if ($results.Count -eq 0) { throw 'No compliance results were collected.' }
if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$checkNames  = @($results[0].Checks.Keys)
$totalChecks = 0
$passed      = 0
$csvRows     = @()
foreach ($result in $results) {
    foreach ($name in $checkNames) {
        $check = $result.Checks[$name]
        if ($check.Status -ne 'notchecked') {
            $totalChecks++
            if ($check.Status -eq 'pass') { $passed++ }
        }
        $csvRows += [pscustomobject]@{
            ComputerName = $result.ComputerName
            CheckedUtc   = $result.CheckedUtc
            Check        = $name
            Status       = $check.Status
            Detail       = $check.Detail
        }
    }
}
$percent = if ($totalChecks -gt 0) { [math]::Round($passed / $totalChecks * 100, 1) } else { 0 }

$stamp = Get-Date -Format 'yyyyMMdd'
$csvPath  = Join-Path $OutputPath ("endpoint-compliance-$stamp.csv")
$htmlPath = Join-Path $OutputPath ("endpoint-compliance-$stamp.html")
$csvRows | Export-Csv -Path $csvPath -NoTypeInformation

$colour = @{ pass = '#15803d'; fail = '#b91c1c'; notchecked = '#b45309' }
$rowsHtml = foreach ($result in $results) {
    $cells = foreach ($name in $checkNames) {
        $check = $result.Checks[$name]
        '<td style="background:{0};color:#fff">&#9679; {1}</td>' -f $colour[$check.Status], ($check.Detail -replace '&', '&amp;' -replace '<', '&lt;')
    }
    '      <tr><th scope="row">{0}</th>{1}</tr>' -f $result.ComputerName, ($cells -join '')
}
$headerHtml = ($checkNames | ForEach-Object { '<th>{0}</th>' -f $_ }) -join ''

$html = @(
    '<!doctype html><html lang="en"><head><meta charset="utf-8">'
    '<title>Halden endpoint compliance</title>'
    '<style>body{font-family:system-ui,sans-serif;margin:2rem;color:#0f172a}table{border-collapse:collapse}th,td{border:1px solid #cbd5e1;padding:.35rem .5rem;font-size:.85rem;text-align:left}</style>'
    '</head><body>'
    ('<h1>Halden endpoint compliance &mdash; {0}</h1>' -f (Get-Date -Format 'yyyy-MM-dd'))
    ('<p><strong>{0}% compliant</strong> across {1} checks on {2} computer(s).</p>' -f $percent, $totalChecks, $results.Count)
    '<p>Traffic lights: green = pass, red = fail, amber = not checked. Generated by Get-EndpointCompliance.ps1.</p>'
    '<table><thead><tr><th>Computer</th>'
    $headerHtml
    '</tr></thead><tbody>'
    $rowsHtml
    '</tbody></table>'
    '<p style="color:#64748b;font-size:.8rem">Home-lab report for the fictional Halden Distribution Ltd. Figures come from a real run; no estimate is shown.</p>'
    '</body></html>'
) -join "`n"
Set-Content -Path $htmlPath -Value $html -Encoding UTF8

Write-Host ("Compliance: {0}% ({1}/{2} checks passed) across {3} computer(s)." -f $percent, $passed, $totalChecks, $results.Count)
Write-Host ("HTML: {0}" -f $htmlPath)
Write-Host ("CSV : {0}" -f $csvPath)

<#
.SYNOPSIS
  Phase 2: stale and privileged account hygiene report (read-only).

.DESCRIPTION
  Produces the monthly identity hygiene report as a styled HTML file plus a CSV of the raw findings:

    - enabled users with no logon in the stale window (default 90 days)
    - enabled users whose password never expires
    - users whose password is not required
    - disabled accounts still present (candidates for the 90-day deletion step)
    - who is in the privileged groups (recursive membership)
    - accounts with no HR record at all (orphans)

  This script changes nothing. It is read-only by design: an account review is a decision, and the
  decision belongs to a human with the evidence in front of them.

  The stale check uses lastLogonTimestamp, which replicates between domain controllers with an
  accuracy of roughly 14 days. That is accurate enough for a 90-day rule and is stated in the report
  so the figure is not over-trusted.

.PARAMETER StaleDays
  Days with no logon before an account counts as stale. Default 90.

.PARAMETER SearchBase
  OU to scan. Defaults to OU=Halden in the current domain.

.PARAMETER ReportPath
  Where to write the HTML report. The CSV is written beside it.

.EXAMPLE
  .\02-Get-IdentityHygieneReport.ps1
  Write the report to reports\identity-hygiene-<yyyyMMdd>.html

.EXAMPLE
  .\02-Get-IdentityHygieneReport.ps1 -StaleDays 60 -ReportPath .\reports\hygiene-test.html
  Use a 60-day stale window and a specific output file.

.NOTES
  Read-only: no snapshot required, but take one anyway if a previous phase's snapshot has expired.
  To make the "before" report find something, run 11-New-TestBadAccounts.ps1 first, then remove the
  test accounts with -Rollback when the evidence has been captured.
#>
[CmdletBinding()]
param(
    [int] $StaleDays = 90,
    [string] $SearchBase,
    [string] $ReportPath,
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop

$root = (Get-ADDomain).DistinguishedName
if (-not $SearchBase) { $SearchBase = "OU=Halden,$root" }
if (-not $ReportPath) {
    $ReportPath = Join-Path "$PSScriptRoot\..\reports" ("identity-hygiene-{0}.html" -f (Get-Date -Format 'yyyyMMdd'))
}
New-Item -ItemType Directory -Force -Path (Split-Path $ReportPath) | Out-Null
$csvPath = [IO.Path]::ChangeExtension($ReportPath, '.csv')

$cutoff = (Get-Date).AddDays(-$StaleDays)
$operator = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "Collecting identity hygiene facts (stale window ${StaleDays}d)..." -ForegroundColor Cyan

# --- Stale accounts ----------------------------------------------------------------------------
$stale = @(Search-ADAccount -AccountInactive -TimeSpan ([TimeSpan]::FromDays($StaleDays)) -UsersOnly -SearchBase $SearchBase |
    Where-Object Enabled |
    ForEach-Object {
        $detail = Get-ADUser $_.DistinguishedName -Properties LastLogonDate, Department, Title, EmployeeID, PasswordLastSet
        [pscustomobject] @{
            Finding     = 'Stale account'
            Sam         = $_.SamAccountName
            Name        = $_.Name
            Department  = $detail.Department
            Title       = $detail.Title
            EmployeeID  = $detail.EmployeeID
            Detail      = "last logon $(if ($detail.LastLogonDate) { $detail.LastLogonDate.ToString('yyyy-MM-dd') } else { 'never recorded' })"
        }
    })

# --- Password hygiene --------------------------------------------------------------------------
$pwNeverExpires = @(Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } -SearchBase $SearchBase `
        -Properties Department, Title, EmployeeID |
    ForEach-Object {
        [pscustomobject] @{
            Finding = 'Password never expires'; Sam = $_.SamAccountName; Name = $_.Name
            Department = $_.Department; Title = $_.Title; EmployeeID = $_.EmployeeID
            Detail = 'PasswordNeverExpires = true'
        }
    })

$pwNotRequired = @(Get-ADUser -Filter { PasswordNotRequired -eq $true } -SearchBase $SearchBase `
        -Properties Department, Title, EmployeeID, Enabled |
    ForEach-Object {
        [pscustomobject] @{
            Finding = 'Password not required'; Sam = $_.SamAccountName; Name = $_.Name
            Department = $_.Department; Title = $_.Title; EmployeeID = $_.EmployeeID
            Detail = "enabled=$($_.Enabled)"
        }
    })

# --- Disabled accounts awaiting deletion -------------------------------------------------------
$disabled = @(Get-ADUser -Filter { Enabled -eq $false } -SearchBase $SearchBase `
        -Properties Description, WhenChanged |
    ForEach-Object {
        [pscustomobject] @{
            Finding = 'Disabled account retained'; Sam = $_.SamAccountName; Name = $_.Name
            Department = ''; Title = ''; EmployeeID = ''
            Detail = "last changed $($_.WhenChanged.ToString('yyyy-MM-dd')); $($_.Description)"
        }
    })

# --- Privileged group membership (recursive) ---------------------------------------------------
$privilegedGroups = 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators',
                    'Account Operators', 'Backup Operators', 'Server Operators', 'Group Policy Creator Owners'
$privileged = foreach ($g in $privilegedGroups) {
    $group = Get-ADGroup -Filter "SamAccountName -eq '$g'" -ErrorAction SilentlyContinue
    if (-not $group) { continue }
    foreach ($m in (Get-ADGroupMember -Identity $g -Recursive -ErrorAction SilentlyContinue)) {
        [pscustomobject] @{
            Finding = 'Privileged membership'; Sam = $m.SamAccountName; Name = $m.Name
            Department = ''; Title = ''; EmployeeID = ''
            Detail = "member of $g as $($m.objectClass)"
        }
    }
}

# --- Orphans: enabled accounts with no HR record (Phase 1 convention: extensionAttribute1) ------
$orphans = @(Get-ADUser -Filter { Enabled -eq $true } -SearchBase $SearchBase -Properties EmployeeID, Department, extensionAttribute1 |
    Where-Object { -not $_.EmployeeID } |
    ForEach-Object {
        [pscustomobject] @{
            Finding = 'No HR record'; Sam = $_.SamAccountName; Name = $_.Name
            Department = $_.Department; Title = ''; EmployeeID = ''
            Detail = "created by $(if ($_.extensionAttribute1) { $_.extensionAttribute1 } else { 'unknown' })"
        }
    })

$findings  = @($stale) + @($pwNeverExpires) + @($pwNotRequired) + @($disabled) + @($privileged) + @($orphans)
$findings | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$summary = $findings | Group-Object Finding | Sort-Object Name |
    ForEach-Object {
        [pscustomobject] @{ Finding = $_.Name; Count = $_.Count }
    }

# --- HTML report -------------------------------------------------------------------------------
$style = @'
body { font-family: "Segoe UI", system-ui, sans-serif; margin: 32px; color: #0f172a; }
h1 { font-size: 22px; } h2 { font-size: 16px; margin-top: 28px; color: #0f766e; }
table { border-collapse: collapse; width: 100%; margin-top: 8px; font-size: 13px; }
th, td { border: 1px solid #cbd5e1; padding: 6px 8px; text-align: left; }
th { background: #f1f5f9; }
tr:nth-child(even) td { background: #f8fafc; }
.note { background: #f0fdfa; border: 1px solid #0f766e; padding: 10px 12px; font-size: 13px; }
.warn { background: #fffbeb; border: 1px solid #d97706; padding: 10px 12px; font-size: 13px; }
'@

$html = @()
$html += '<!DOCTYPE html><html lang="en-GB"><head><meta charset="utf-8">'
$html += '<title>Halden identity hygiene report</title>'
$html += "<style>$style</style></head><body>"
$html += '<h1>Halden Distribution Ltd. - identity hygiene report</h1>'
$html += "<p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by $operator on $(hostname) - domain $Domain - stale window ${StaleDays} days</p>"
$html += '<div class="note"><strong>Lab note:</strong> Halden Distribution Ltd. is a fictional company and every account in this report is synthetic. This report is read-only: nothing in it has been changed by IT.</div>'
$html += '<h2>Summary</h2>'
$html += ($summary | ConvertTo-Html -Fragment)
$html += '<h2>Findings</h2>'
$html += ($findings | ConvertTo-Html -Fragment)
$html += '<div class="warn"><strong>Accuracy note:</strong> the stale check uses <code>lastLogonTimestamp</code>, which replicates between domain controllers within about 14 days. A 90-day rule is safe; a 7-day rule would not be.</div>'
$html += '</body></html>'
$html | Set-Content -Path $ReportPath -Encoding UTF8

Write-Host ''
Write-Host "Report written: $ReportPath" -ForegroundColor Cyan
Write-Host "Raw findings:   $csvPath"
$summary | Format-Table -AutoSize
Write-Host 'Review the findings and decide the actions - this script changes nothing by design.' -ForegroundColor Cyan

<#
.SYNOPSIS
  Phase 4: produce the quarterly access-review pack, one sheet per department, ready for sign-off.

.DESCRIPTION
  For each department the script lists every user with:

    user -> role groups -> the resources those groups actually reach -> last logon -> manager
    -> an empty Keep / Remove / Change column for the reviewer

  The resource column is the important one for a non-technical reviewer: it answers "can this person
  read the Finance folder?" instead of presenting a group name they cannot interpret. The mapping
  comes from configs\role-matrix.csv, which records the resource groups each role reaches.

  The output is CSV (opens in Excel or LibreOffice) or xlsx if the ImportExcel module is present. The
  script changes nothing: it prepares the evidence for a decision the business owns.

.PARAMETER Department
  Limit the export to one department. Without it, every department gets its own file.

.PARAMETER OutDir
  Where to write the pack. Defaults to..\reports\access-review-<yyyyMMdd>\.

.PARAMETER OnlyFindings
  Include only rows that need attention (mismatch between current and desired groups, stale logon, or
  an unmanaged group). Useful for the second pass after a review.

.EXAMPLE
  .\10-Export-AccessReview.ps1
  Full pack for every department.

.EXAMPLE
  .\10-Export-AccessReview.ps1 -Department Finance
  Just the Finance sheet, for the Finance Director's review.

.NOTES
  Run on DC01. Read-only: no snapshot needed. The class of data here (names, usernames, last logon)
  is exactly what a reviewer needs, so the pack is an internal working document: sanitize it before
  anything goes into evidence/public, and never commit a returned sheet with a real signature
  (there are none in this lab - the sign-off is role-played and recorded as such).
#>
[CmdletBinding()]
param(
    [string] $Department,
    [string] $OutDir,
    [string] $RoleMatrix = "$PSScriptRoot\..\configs\role-matrix.csv",
    [switch] $OnlyFindings,
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop
$hasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel)

$root = (Get-ADDomain).DistinguishedName
$usersOu = "OU=Users,OU=Halden,$root"
if (-not $OutDir) { $OutDir = Join-Path "$PSScriptRoot\..\reports" ("access-review-{0}" -f (Get-Date -Format 'yyyyMMdd')) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Read-DataCsv {
    param([Parameter(Mandatory)][string] $Path)
    (Get-Content -Path $Path | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }) -join "`n" | ConvertFrom-Csv
}

$matrix = @(Read-DataCsv -Path $RoleMatrix)
$managedPool = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rule in $matrix) {
    foreach ($g in ($rule.RoleGroups -split ';')) { $t = $g.Trim(); if ($t) { [void]$managedPool.Add($t) } }
}

function Resolve-DesiredGroups {
    param([string] $Dept, [string] $Title)
    $rules = @($matrix | Where-Object { $_.Department -ieq $Dept })
    $rule = $rules | Where-Object { $_.Title -and $_.Title -notmatch '\*' -and $_.Title -ieq $Title } | Select-Object -First 1
    if (-not $rule) { $rule = $rules | Where-Object { $_.Title -match '\*' -and $_.Title -ne '*' -and $Title -like ('*' + $_.Title.Trim('*') + '*') } | Select-Object -First 1 }
    if (-not $rule) { $rule = $rules | Where-Object { $_.Title -eq '*' } | Select-Object -First 1 }
    if (-not $rule) { return @() }
    @($rule.RoleGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Resolve-Resources {
    <# Turn the desired role groups into a plain-English list of what they reach, for the reviewer. #>
    param([string[]] $Groups)
    $resources = New-Object System.Collections.Generic.List[string]
    foreach ($g in $Groups) {
        $rule = $matrix | Where-Object { $_.RoleGroups -split ';' -contains $g } | Select-Object -First 1
        if ($rule -and $rule.ResourceGroups) {
            foreach ($r in ($rule.ResourceGroups -split ';')) { $t = $r.Trim(); if ($t) { $resources.Add($t) } }
        }
    }
    @($resources | Sort-Object -Unique)
}

$departments = if ($Department) { @($Department) } else {
    @(Get-ADOrganizationalUnit -Filter * -SearchBase $usersOu -SearchScope OneLevel | ForEach-Object { $_.Name } | Sort-Object)
}

$grandTotal = 0
foreach ($dept in $departments) {
    $ou = "OU=$dept,$usersOu"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $usersOu -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        Write-Warning "No OU for department '$dept' - skipping."
        continue
    }

    $users = @(Get-ADUser -Filter * -SearchBase $ou -SearchScope OneLevel `
        -Properties EmployeeID, Department, Title, Manager, MemberOf, Enabled, LastLogonDate, PasswordLastSet)

    $rows = foreach ($u in $users) {
        $current  = @($u.MemberOf | ForEach-Object { (Get-ADGroup $_).SamAccountName })
        $desired  = Resolve-DesiredGroups -Dept $dept -Title $u.Title
        $extra    = @($current | Where-Object { $managedPool.Contains($_) -and $desired -notcontains $_ })
        $missing  = @($desired | Where-Object { $current -notcontains $_ })
        $stale    = ($u.LastLogonDate -and $u.LastLogonDate -lt (Get-Date).AddDays(-90))
        $mgr      = if ($u.Manager) { (Get-ADUser $u.Manager -ErrorAction SilentlyContinue).SamAccountName } else { '' }

        [pscustomobject] @{
            EmployeeID      = $u.EmployeeID
            SamAccountName  = $u.SamAccountName
            DisplayName     = $u.Name
            Department      = $u.Department
            Title           = $u.Title
            ManagerID       = $mgr
            CurrentRoleGroups = ($current -join '; ')
            DesiredRoleGroups = ($desired -join '; ')
            ResourcesReached  = ((Resolve-Resources -Groups $desired) -join '; ')
            ExtraGroups       = ($extra -join '; ')
            MissingGroups     = ($missing -join '; ')
            LastLogonDate   = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('yyyy-MM-dd') } else { 'never recorded' }
            Stale90d        = $stale
            Issue           = (@(
                if ($extra.Count)   { "extra managed group(s): $($extra -join ', ')" }
                if ($missing.Count) { "missing group(s): $($missing -join ', ')" }
                if ($stale)         { 'no logon in 90+ days' }
            ) -join ' | ')
            ReviewDecision  = ''   # Keep / Remove / Change - the department head fills this in
        }
    }

    if ($OnlyFindings) { $rows = @($rows | Where-Object { $_.Issue -ne '' }) }

    $safeName = ($dept -replace '[^\w\-]', '')
    if ($hasImportExcel) {
        $xlsx = Join-Path $OutDir "p02-ph4-access-review-$safeName.xlsx"
        $rows | Export-Excel -Path $xlsx -WorksheetName $dept -AutoSize -FreezeTopRow -TableStyle Medium2
        Write-Host "  $dept : $($rows.Count) row(s) -> $xlsx" -ForegroundColor Cyan
    } else {
        $csv = Join-Path $OutDir "p02-ph4-access-review-$safeName.csv"
        $rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
        Write-Host "  $dept : $($rows.Count) row(s) -> $csv (ImportExcel not installed; CSV instead)" -ForegroundColor Cyan
    }
    $grandTotal += $rows.Count
}

Write-Host ''
Write-Host "Access-review pack written to $OutDir ($grandTotal row(s))." -ForegroundColor Cyan
Write-Host 'Next: send each head only their own department sheet, with the covering note in docs\runbooks\run-the-access-review.md.' -ForegroundColor Cyan
Write-Host 'Anything not marked Keep is treated as Remove. Track every decision in business\p2-access-review-pack.md.' -ForegroundColor Cyan

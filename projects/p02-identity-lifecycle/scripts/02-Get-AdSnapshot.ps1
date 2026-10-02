<#
.SYNOPSIS
  Phase 5 helper: capture the AD state the offline Python planner needs, so a plan can be reviewed without touching AD.

.DESCRIPTION
  Exports the fields jml-plan.py needs (EmployeeID, Sam, Department, Title, Enabled, Groups) to a CSV.
  Combined with a copied HR export, this lets the whole joiner-mover-leaver decision be reproduced,
  reviewed and unit-tested offline - which is how the logic is verified here, since the agent has no
  access to the lab.

  Read-only. The output lives in evidence/raw/ (git-ignored): it is an internal working file, not
  published evidence.

.EXAMPLE
  .\02-Get-AdSnapshot.ps1
  Write evidence\raw\p02-ad-snapshot.csv

.EXAMPLE
  .\02-Get-AdSnapshot.ps1 -Out 'C:\temp\snap.csv' -OnlyManaged
  Snapshot only the accounts the JML engine owns.

.NOTES
  Run on DC01.
#>
[CmdletBinding()]
param(
    [string] $Out = "$PSScriptRoot\..\evidence\raw\p02-ad-snapshot.csv",
    [switch] $OnlyManaged,
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop
$root = (Get-ADDomain).DistinguishedName

$filter = if ($OnlyManaged) { { extensionAttribute1 -eq 'JML-Managed' } } else { { Enabled -eq $true } }
$users = @(Get-ADUser -Filter $filter -SearchBase "OU=Users,OU=Halden,$root" -SearchScope Subtree `
    -Properties EmployeeID, Department, Title, MemberOf, Enabled)

$rows = foreach ($u in $users) {
    [pscustomobject] @{
        EmployeeID = $u.EmployeeID
        Sam        = $u.SamAccountName
        Department = $u.Department
        Title      = $u.Title
        Enabled    = $u.Enabled
        Groups     = (@($u.MemberOf | ForEach-Object { (Get-ADGroup $_).SamAccountName }) -join ';')
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
$rows | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $Out ($($rows.Count) account(s))" -ForegroundColor Cyan
Write-Host 'Then review a plan offline (fill in today''s date):'
Write-Host '  python3 ../scripts/jml-plan.py --ad-snapshot <this file> --hr ../data/hr-export.csv --today 2026-10-02'
Write-Host 'This file is in evidence/raw/ (git-ignored) and is not published as evidence.' -ForegroundColor DarkYellow

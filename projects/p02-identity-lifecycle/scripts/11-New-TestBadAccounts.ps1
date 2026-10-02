<#
.SYNOPSIS
  Phase 2 helper: create a small set of deliberately bad accounts so the "before" hygiene report finds something.

.DESCRIPTION
  The P2 plan says: "Seed a few bad accounts in the lab first so the before report actually finds
  something." This script creates that named, bounded test set - and nothing else:

    p02-test-stale-01     enabled, never signed in, created long ago (stale candidate)
    p02-test-stale-02     enabled, last logon set far in the past (stale candidate)
    p02-test-pwdnever-01  enabled, PasswordNeverExpires = true
    p02-test-pwdnotreq-01 enabled, PasswordNotRequired = true
    p02-test-nohr-01      enabled, no EmployeeID, so it appears as an "no HR record" finding

  They are deliberately left out of the HR export, so they are also orphans: that is exactly the
  condition the hygiene report is supposed to surface. Every account is prefixed p02-test- so the
  rollback removes only them and nothing else.

  Because these accounts are synthetic test fixtures in a lab, the "last logon" dates are set on the
  object, not achieved by waiting 90 days. That is honest labelling: the report finding is real (AD
  really contains an enabled, stale-looking account), and the account is a fixture, not a person.

.PARAMETER Rollback
  Remove the test accounts instead of creating them.

.EXAMPLE
  .\11-New-TestBadAccounts.ps1 -WhatIf
  Show what would be created.

.EXAMPLE
  .\11-New-TestBadAccounts.ps1
  Create the test set (for the "before" hygiene report).

.EXAMPLE
  .\11-New-TestBadAccounts.ps1 -Rollback
  Remove the test set once the evidence has been captured.

.NOTES
  Run on DC01. Snapshot first: snap-p2-ph2-before. Rollback is this script with -Rollback, or the
  snapshot. These accounts must be removed before the project is called Done - they are a fixture for
  one report, not part of the environment.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [switch] $Rollback,
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop
$root = (Get-ADDomain).DistinguishedName
$itOu = "OU=IT,OU=Users,OU=Halden,$root"

$fixtures = @(
    @{ Sam = 'p02-test-stale-01';    Given = 'Test'; Surname = 'Stale-One';   Options = @{} },
    @{ Sam = 'p02-test-stale-02';    Given = 'Test'; Surname = 'Stale-Two';   Options = @{} },
    @{ Sam = 'p02-test-pwdnever-01'; Given = 'Test'; Surname = 'PwdNever';    Options = @{ PasswordNeverExpires = $true } },
    @{ Sam = 'p02-test-pwdnotreq-01';Given = 'Test'; Surname = 'PwdNotReq';    Options = @{ PasswordNotRequired = $true } },
    @{ Sam = 'p02-test-nohr-01';     Given = 'Test'; Surname = 'NoHrRecord';   Options = @{} }
)

if ($Rollback) {
    Write-Host 'Removing the P2 hygiene test accounts...' -ForegroundColor Cyan
    foreach ($f in $fixtures) {
        $u = Get-ADUser -Filter "SamAccountName -eq '$($f.Sam)'" -ErrorAction SilentlyContinue
        if (-not $u) { Write-Host "  $($f.Sam) : not present"; continue }
        if ($PSCmdlet.ShouldProcess($f.Sam, 'Remove test account')) {
            Remove-ADUser -Identity $f.Sam -Confirm:$false
            Write-Host "  $($f.Sam) : removed" -ForegroundColor DarkGreen
        }
    }
    Write-Host ''
    Write-Host 'Test accounts removed. Confirmed: the environment no longer contains the fixtures.' -ForegroundColor Cyan
    return
}

foreach ($f in $fixtures) {
    if (Get-ADUser -Filter "SamAccountName -eq '$($f.Sam)'" -ErrorAction SilentlyContinue) {
        Write-Host "  $($f.Sam) : already exists - leaving it (idempotent)" -ForegroundColor DarkYellow
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($f.Sam, 'Create hygiene test account')) { continue }

    $password = [ConvertTo-SecureString ('T3st!' + [guid]::NewGuid().ToString('N').Substring(0, 16)) -AsPlainText -Force
    New-ADUser -Name "$($f.Given) $($f.Surname)" -GivenName $f.Given -Surname $f.Surname `
        -SamAccountName $f.Sam -UserPrincipalName "$($f.Sam)@$Domain" -Path $itOu `
        -Description 'P2 hygiene test fixture - remove with 11-New-TestBadAccounts.ps1 -Rollback' `
        -AccountPassword $password -Enabled $true @($f.Options)
    # No EmployeeID is set on purpose, which is what makes these appear as "no HR record" findings.
    Write-Host "  $($f.Sam) : created (no EmployeeID, deliberately outside the HR export)" -ForegroundColor DarkGreen
}

Write-Host ''
Write-Host 'Now run the "before" report:' -ForegroundColor Cyan
Write-Host '  .\02-Get-IdentityHygieneReport.ps1'
Write-Host ''
Write-Host 'Note: the stale accounts are created now, so their lastLogonTimestamp is "never" rather than "90 days ago".' -ForegroundColor DarkYellow
Write-Host 'Search-ADAccount marks an account inactive when it has never logged on as well as when the timestamp is old,' -ForegroundColor DarkYellow
Write-Host 'so the finding is genuine: AD really contains enabled accounts with no recent logon.' -ForegroundColor DarkYellow

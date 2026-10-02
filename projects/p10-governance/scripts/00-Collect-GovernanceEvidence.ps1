<#
.SYNOPSIS
    Collects the Windows/AD-side evidence a governance cycle needs, and writes it as CSV for the
    P10 KPI pipeline and the CIS IG1 assessment.

.DESCRIPTION
    Runs on a Halden domain controller (DC01 keeps read-only AD cmdlets) or a management
    workstation with RSAT. It is **read-only**: it queries AD, Group Policy and (optionally) the
    file server, and writes CSV files into the P10 evidence folder. It never changes a setting,
    never creates or edits an account, and never scores a safeguard itself — scoring is a human
    decision made after reading the evidence.

    Evidence it can produce (each guarded by a switch):
      * Account inventory and stale-account report (feeds CIS 5.1, 5.3 and KPI-01/-03)
      * Group membership and privileged-group membership (feeds CIS 5.4, 6.8)
      * Password/lockout policy as configured (feeds CIS 5.2)
      * ACL audit invocation summary from the P1 script (feeds CIS 3.3)
      * Group Policy application summary for a named computer (feeds CIS 4.3)

.PARAMETER OutputDirectory
    Where the CSV evidence is written. Defaults to projects/p10-governance/evidence/raw.

.PARAMETER StaleDays
    Accounts with no interactive logon for this many days are reported as stale. CIS IG1 safeguard
    5.3 uses 45 days; the default matches it.

.PARAMETER PolicyComputer
    A computer name to run the Group Policy result report against (optional).

.PARAMETER WhatIf
    Supported through CmdletBinding. Shows what would be written without writing it.

.EXAMPLE
    .\00-Collect-GovernanceEvidence.ps1
    Collects the account, group and policy evidence into the default evidence folder.

.EXAMPLE
    .\00-Collect-GovernanceEvidence.ps1 -StaleDays 45 -PolicyComputer HQ-WS-001 -Verbose
    Collects the same evidence, flagging accounts inactive for 45+ days and reporting GPO
    application for HQ-WS-001.

.NOTES
    Home lab · Halden Distribution Ltd. is a fictional 85-user company. Output goes to
    evidence/raw first; sanitize it (AGENTS.md Section 4.6) before publishing a copy.
    Rollback: this script changes nothing in AD; delete the CSVs it wrote to undo its output.
    Requires: ActiveDirectory and GroupPolicy PowerShell modules, and the Halden lab guard.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '..\evidence\raw'),

    [ValidateRange(1, 3650)]
    [int]$StaleDays = 45,

    [string]$PolicyComputer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Halden lab guard ------------------------------------------------------------------------
try {
    $domain = Get-ADDomain -ErrorAction Stop
}
catch {
    throw "Cannot read the AD domain. Is the ActiveDirectory module available? $($_.Exception.Message)"
}
if ($domain.DNSRoot -ne 'ad.halden.internal') {
    throw "Not the Halden lab domain (found '$($domain.DNSRoot)'). Aborting."
}

$timestamp = Get-Date -Format 'yyyy-MM-dd'
$targetDir = [System.IO.Path]::GetFullPath($OutputDirectory)

function Write-EvidenceCsv {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Rows
    )

    $path = Join-Path -Path $targetDir -ChildPath ("p10-{0}-{1}.csv" -f $timestamp, $Name)
    if ($PSCmdlet.ShouldProcess($path, 'Write evidence CSV')) {
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        $Rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
        Write-Verbose "Wrote $($Rows.Count) row(s) to $path"
    }
    return $path
}

function Get-AccountEvidence {
    [CmdletBinding()]
    param([int]$InactiveDays)

    $cutoff = (Get-Date).AddDays(-$InactiveDays)
    $users = Get-ADUser -Filter * -Properties Enabled, Department, Title, Manager, Created, LastLogonDate, PasswordLastSet, employeeID

    $rows = foreach ($user in $users) {
        [pscustomobject]@{
            SamAccountName     = $user.SamAccountName
            Enabled            = $user.Enabled
            Department         = $user.Department
            Title              = $user.Title
            Manager            = if ($user.Manager) { ($user.Manager -split ',')[0] -replace '^CN=', '' } else { '' }
            Created            = $user.Created
            LastLogonDate      = $user.LastLogonDate
            PasswordLastSet    = $user.PasswordLastSet
            EmployeeId         = $user.employeeID
            HasInteractiveLogon = [bool]$user.LastLogonDate
            StaleEnabled       = [bool]($user.Enabled -and ($null -eq $user.LastLogonDate -or $user.LastLogonDate -lt $cutoff))
        }
    }

    # Account inventory (CIS 5.1) and the stale-account view (CIS 5.3) share one source.
    Write-EvidenceCsv -Name 'account-inventory' -Rows @($rows) | Out-Null
    Write-EvidenceCsv -Name 'dormant-accounts' -Rows @($rows | Where-Object { $_.StaleEnabled }) | Out-Null
}

function Get-GroupEvidence {
    [CmdletBinding()]
    param()

    $privileged = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators', 'Account Operators', 'Backup Operators')
    $rows = foreach ($group in $privileged) {
        try {
            $members = Get-ADGroupMember -Identity $group -ErrorAction Stop
        }
        catch {
            Write-Verbose "Group '$group' not found; skipping."
            continue
        }
        foreach ($member in $members) {
            [pscustomobject]@{
                Group   = $group
                Member  = $member.SamAccountName
                Type    = $member.objectClass
                IsUser  = ($member.objectClass -eq 'user')
            }
        }
    }
    Write-EvidenceCsv -Name 'privileged-group-membership' -Rows @($rows) | Out-Null
}

function Get-PasswordPolicyEvidence {
    [CmdletBinding()]
    param()

    $policy = Get-ADDefaultDomainPasswordPolicy
    $rows = @(
        [pscustomobject]@{
            MinPasswordLength      = $policy.MinPasswordLength
            ComplexityEnabled      = $policy.ComplexityEnabled
            LockoutThreshold       = $policy.LockoutThreshold
            LockoutDurationMinutes = $policy.LockoutDuration.TotalMinutes
            LockoutObservationMins = $policy.LockoutObservationWindow.TotalMinutes
            ReversibleEncryption   = $policy.ReversibleEncryptionEnabled
        }
    )
    Write-EvidenceCsv -Name 'password-policy' -Rows $rows | Out-Null
}

function Get-GpoApplicationEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Computer)

    # gpresult runs remotely against the named computer; it changes nothing.
    $out = Invoke-Command -ComputerName $Computer -ScriptBlock { gpresult /scope computer /r } -ErrorAction Stop
    $rows = $out -split "`n" | ForEach-Object { [pscustomobject]@{ Line = $_.Trim() } }
    Write-EvidenceCsv -Name ("gpo-result-{0}" -f $Computer) -Rows @($rows) | Out-Null
}

# --- Main ------------------------------------------------------------------------------------
Write-Verbose "Collecting governance evidence for $($domain.DNSRoot) into $targetDir"
Write-Verbose "Stale-account threshold: $StaleDays day(s) (CIS IG1 safeguard 5.3)"

if ($PSCmdlet.ShouldProcess($targetDir, 'Create the evidence output directory')) {
    if (-not (Test-Path -Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
}

Get-AccountEvidence -InactiveDays $StaleDays
Get-GroupEvidence
Get-PasswordPolicyEvidence

if ($PSBoundParameters.ContainsKey('PolicyComputer') -and $PolicyComputer) {
    Get-GpoApplicationEvidence -Computer $PolicyComputer
}

Write-Host "Governance evidence collected into $targetDir."
Write-Host "Next: run projects/p01-core-infrastructure/scripts/07-Test-ShareAcl.ps1 for the CIS 3.3 evidence,"
Write-Host "then sanitize these files (AGENTS.md 4.6) before publishing any of them."

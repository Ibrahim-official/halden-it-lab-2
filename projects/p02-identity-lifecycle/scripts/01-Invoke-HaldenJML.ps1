<#
.SYNOPSIS
  Phase 1: the Halden joiner-mover-leaver engine. Reconciles AD to the HR source-of-truth export.

.DESCRIPTION
  Reads the synthetic HR export (keyed on EmployeeID), compares the desired state it describes with
  the current state in Active Directory, and applies the difference:

    Joiner  - account + role groups + home folder, before the start date
    Mover   - old-department role groups removed and new ones added in the SAME run
    Leaver  - groups snapshotted, account disabled, groups stripped, moved to OU=Disabled

  Safety features (see ..\docs\00-design.md section 5.4):
    - -WhatIf dry run: prints the full plan and changes nothing (SupportsShouldProcess)
    - Circuit breaker: aborts the whole run if more than -CircuitBreakerPercent of the accounts in
      the export would be disabled in one run (default 10%)
    - Protected accounts (data\protected-accounts.txt) are never modified or disabled
    - Append-only audit log: logs\jml-audit.csv (timestamp, action, target, before, after, operator)
    - Idempotent: a second run with the same export makes no changes

  The script must run as an account with delegated rights over OU=Users and OU=Disabled - not
  Domain Admin. 03-New-JmlServiceAccount.ps1 creates the gMSA and the delegation.

.PARAMETER HrFile
  Path to the HR export CSV. Required columns:
  EmployeeID,First,Last,Department,Title,ManagerID,Status,StartDate,EndDate[,Office]

.PARAMETER RoleMatrix
  Path to configs\role-matrix.csv, which defines the desired role groups per department and title.
  This is the only pool of groups the mover path is allowed to remove.

.PARAMETER EmployeeID
  Process a single person instead of the whole file.

.PARAMETER Urgent
  With -EmployeeID, process a leaver immediately without waiting for the end date. Used for the
  emergency leaver path in docs\runbooks\process-a-leaver.md.

.PARAMETER JoinerLeadDays
  How many days ahead of the start date a joiner is created. Default 7.

.PARAMETER CircuitBreakerPercent
  Abort when this run would disable more than this percentage of the accounts in the export.

.PARAMETER HomeDriveRoot
  UNC root of the home folders on the file server (P1 FS01).

.EXAMPLE
  .\01-Invoke-HaldenJML.ps1 -WhatIf
  Show the full plan for the whole export and change nothing.

.EXAMPLE
  .\01-Invoke-HaldenJML.ps1
  Apply the plan.

.EXAMPLE
  .\01-Invoke-HaldenJML.ps1 -EmployeeID '1086' -WhatIf
  Show what would happen to one new starter.

.EXAMPLE
  .\01-Invoke-HaldenJML.ps1 -EmployeeID '1042' -Urgent
  Immediately disable a leaver (emergency offboarding).

.NOTES
  Run on DC01. Snapshot first: snap-p2-ph1-before. Lab guard below refuses to run outside the
  Halden lab domain. Initial passwords are written only to a git-ignored file and must be handed
  over through the agreed secure channel - never by clear-text email.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $HrFile = "$PSScriptRoot\..\data\hr-export.csv",
    [string] $RoleMatrix = "$PSScriptRoot\..\configs\role-matrix.csv",
    [string] $ProtectedFile = "$PSScriptRoot\..\data\protected-accounts.txt",
    [string] $LogDir = "$PSScriptRoot\..\logs",
    [string] $ReportDir = "$PSScriptRoot\..\reports",
    [string] $HomeDriveRoot = '\\fs01.ad.halden.internal\Users$',
    [string] $Domain = 'ad.halden.internal',
    [string[]] $EmployeeID,
    [switch] $Urgent,
    [int]    $JoinerLeadDays = 7,
    [double] $CircuitBreakerPercent = 10,
    [switch] $SkipHomeFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Lab guard (AGENTS.md Section 2): refuse to run anywhere but the Halden lab -----------------
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop

$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$today    = (Get-Date).Date
$operator = "$env:USERDOMAIN\$env:USERNAME"
$root     = (Get-ADDomain).DistinguishedName
$usersOu  = "OU=Users,OU=Halden,$root"
$disabledOu = "OU=Disabled,$root"

New-Item -ItemType Directory -Force -Path $LogDir, "$LogDir\leavers", $ReportDir | Out-Null
$auditPath = Join-Path $LogDir 'jml-audit.csv'
$pwPath    = Join-Path $LogDir "initial-passwords-$stamp.csv"

# ----------------------------------------------------------------------------------- helpers

function Read-DataCsv {
    <# Import-Csv but skipping '#' comment lines and blank lines, which the config files use. #>
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path $Path)) { throw "Input file not found: $Path" }
    $lines = Get-Content -Path $Path |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }
    if ($lines.Count -lt 2) { throw "Input file has no data rows: $Path" }
    $lines -join "`n" | ConvertFrom-Csv
}

function New-RandomPassword {
    <# Cryptographically random password; never logged, never written anywhere but the protected file. #>
    param([int] $Length = 24)
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%+='.ToCharArray()
    $bytes = New-Object byte[] $Length
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Write-Audit {
    <# Append one audit row. This file is the answer to "who changed what, when". #>
    param(
        [string] $Action,
        [string] $Target,
        [string] $Before = '',
        [string] $After  = ''
    )
    [pscustomobject] @{
        Timestamp = (Get-Date).ToString('s')
        Action    = $Action
        Target    = $Target
        Before    = $Before
        After     = $After
        Operator  = $operator
    } | Export-Csv -Path $auditPath -NoTypeInformation -Append -Encoding UTF8
}

function Get-ManagedGroupPool {
    <# Every role group named anywhere in the role matrix. The mover may only remove from this pool. #>
    param([Parameter(Mandatory)] $Matrix)
    $pool = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in $Matrix) {
        foreach ($g in ($rule.RoleGroups -split ';')) {
            $t = $g.Trim(); if ($t) { [void]$pool.Add($t) }
        }
    }
    $pool
}

function Resolve-DesiredGroups {
    <#
      First matching matrix row wins: exact title match first, then the first '*' contains match,
      then the department-wide '*' row. Returns an ordered array of group names.
    #>
    param(
        [Parameter(Mandatory)] [string] $Department,
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] $Matrix
    )
    $rules = @($Matrix | Where-Object { $_.Department -ieq $Department })
    $rule = $rules | Where-Object { $_.Title -and $_.Title -notmatch '\*' -and $_.Title -ieq $Title } | Select-Object -First 1
    if (-not $rule) {
        $rule = $rules |
            Where-Object { $_.Title -match '\*' -and $_.Title -ne '*' -and $Title -like ('*' + $_.Title.Trim('*') + '*') } |
            Select-Object -First 1
    }
    if (-not $rule) { $rule = $rules | Where-Object { $_.Title -eq '*' } | Select-Object -First 1 }
    if (-not $rule) { return @() }
    @($rule.RoleGroups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-HaldenAdUser {
    <# The engine only manages accounts in the Halden Users/Disabled OUs that it owns. #>
    param([string] $EmployeeId)
    $filter = { (extensionAttribute1 -eq 'JML-Managed') -or (extensionAttribute9 -eq 'JML-Managed') }
    $all = Get-ADUser -Filter $filter -SearchBase "OU=Halden,$root" -SearchScope Subtree `
        -Properties EmployeeID, Department, Title, Manager, MemberOf, Enabled, Description,
                    extensionAttribute1, extensionAttribute9, DistinguishedName
    if ($EmployeeId) { $all | Where-Object { $_.EmployeeID -eq $EmployeeId } }
    else { $all }
}

function Get-DisplayName { param($Row) "$($Row.First) $($Row.Last)".Trim() }
function Get-SamForRow   { param($Row) "$($Row.First).$($Row.Last)".ToLower() }

function New-HomeFolder {
    <# Create the user's home folder and grant them access to their own folder only (P1 model). #>
    param([string] $Sam)
    if ($SkipHomeFolder) { return 'skipped by request' }
    $path = Join-Path $HomeDriveRoot $Sam
    if (Test-Path $path) { return 'already present' }
    if (-not (Test-Path $HomeDriveRoot)) { return "not created - share root unreachable ($HomeDriveRoot)" }
    if ($PSCmdlet.ShouldProcess($path, 'Create home folder')) {
        New-Item -ItemType Directory -Path $path | Out-Null
        $acl = Get-Acl $path
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Sam, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.SetAccessRuleProtection($true, $false)   # stop inheriting the share root's permissions
        $acl.AddAccessRule($rule)
        Set-Acl -Path $path -AclObject $acl
        return 'created'
    }
    return 'planned'
}

# ------------------------------------------------------------------------------ plan building

$hr = @(Read-DataCsv -Path $HrFile)
if ($EmployeeID) {
    $hr = @($hr | Where-Object { $EmployeeID -contains $_.EmployeeID })
    if ($hr.Count -eq 0) { throw "No row in $HrFile matches -EmployeeID '$($EmployeeID -join ',')'" }
}
if ($hr.Count -eq 0) { throw "The HR export $HrFile has no usable rows." }

$matrix = @(Read-DataCsv -Path $RoleMatrix)
$managedGroups = Get-ManagedGroupPool -Matrix $matrix
$protected = @()
if (Test-Path $ProtectedFile) {
    $protected = @(Get-Content $ProtectedFile | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
        ForEach-Object { $_.Trim() })
}
$adUsers = @(Get-HaldenAdUser)

$plan = New-Object System.Collections.Generic.List[object]

foreach ($row in $hr) {
    $sam = Get-SamForRow -Row $row
    $u   = $adUsers | Where-Object { $_.EmployeeID -eq $row.EmployeeID } | Select-Object -First 1

    if ($protected -contains $sam) {
        $plan.Add([pscustomobject]@{ Kind = 'Protected'; Row = $row; Sam = $sam; User = $u })
        continue
    }

    $isLeaver = ($row.Status -eq 'Leaver')
    $endDate  = if ($row.EndDate) { [datetime]::Parse($row.EndDate, [Globalization.CultureInfo]::InvariantCulture) } else { $null }
    $startDate = if ($row.StartDate) { [datetime]::Parse($row.StartDate, [Globalization.CultureInfo]::InvariantCulture) } else { $null }

    if (-not $u) {
        # No account yet. Create one if HR says Active and the start date is inside the window.
        if (-not $isLeaver -and $startDate -and ($startDate -le $today.AddDays($JoinerLeadDays))) {
            $plan.Add([pscustomobject]@{ Kind = 'Joiner'; Row = $row; Sam = $sam; User = $null })
        }
        continue
    }

    if ($isLeaver) {
        if (-not $u.Enabled) { continue }   # already offboarded - idempotent
        if ($Urgent -or -not $endDate -or $endDate -le $today) {
            $plan.Add([pscustomobject]@{ Kind = 'Leaver'; Row = $row; Sam = $sam; User = $u })
        }
        continue
    }

    # Active, account exists: is this a mover? Compare identity attributes and managed groups.
    $desired = Resolve-DesiredGroups -Department $row.Department -Title $row.Title -Matrix $matrix
    $current = @($u.MemberOf | ForEach-Object { (Get-ADGroup $_).SamAccountName })
    $add    = @($desired | Where-Object { $current -notcontains $_ })
    $remove = @($current | Where-Object { $managedGroups.Contains($_) -and $desired -notcontains $_ })

    $identityChanged = ($u.Department -ne $row.Department) -or ($u.Title -ne $row.Title)
    if ($identityChanged -or $add.Count -gt 0 -or $remove.Count -gt 0) {
        $plan.Add([pscustomobject]@{
            Kind = 'Mover'; Row = $row; Sam = $sam; User = $u
            Add = $add; Remove = $remove; IdentityChanged = $identityChanged
        })
    }
}

# --- Circuit breaker ---------------------------------------------------------------------------
$leaverCount = @($plan | Where-Object Kind -eq 'Leaver').Count
$threshold   = $hr.Count * $CircuitBreakerPercent / 100
$tripped     = ($hr.Count -gt 0) -and ($leaverCount -gt $threshold)

Write-Host ''
Write-Host "Halden JML plan  $(Get-Date -Format 'yyyy-MM-dd HH:mm')  operator $operator" -ForegroundColor Cyan
Write-Host ("Export: {0}  ({1} row(s), {2} managed AD account(s) in scope)" -f $HrFile, $hr.Count, $adUsers.Count)
Write-Host ("Plan:   {0} joiner(s), {1} mover(s), {2} leaver(s), {3} protected, rest already in the desired state" -f `
    @($plan | Where-Object Kind -eq 'Joiner').Count,
    @($plan | Where-Object Kind -eq 'Mover').Count,
    $leaverCount,
    @($plan | Where-Object Kind -eq 'Protected').Count)
Write-Host ("Circuit breaker: {0} leaver(s) of {1} row(s) = {2:N2}% (limit {3:N0}%, threshold {4:N2})" -f `
    $leaverCount, $hr.Count, (($leaverCount / [Math]::Max($hr.Count,1)) * 100), $CircuitBreakerPercent, $threshold)

foreach ($p in $plan) {
    switch ($p.Kind) {
        'Joiner' { Write-Host ("  JOINER  {0,-24} {1}/{2}" -f $p.Sam, $p.Row.Department, $p.Row.Title) }
        'Mover'  {
            Write-Host ("  MOVER   {0,-24} {1} -> {2}" -f $p.Sam, $p.User.Department, $p.Row.Department)
            if ($p.Remove.Count) { Write-Host ("          -{0}" -f ($p.Remove -join ', ')) -ForegroundColor DarkYellow }
            if ($p.Add.Count)    { Write-Host ("          +{0}" -f ($p.Add    -join ', ')) -ForegroundColor DarkGreen }
        }
        'Leaver' { Write-Host ("  LEAVER  {0,-24} end {1}" -f $p.Sam, $p.Row.EndDate) -ForegroundColor Yellow }
        'Protected' { Write-Host ("  PROTECTED {0,-22} left untouched by design" -f $p.Sam) -ForegroundColor DarkGray }
    }
}

if ($tripped) {
    $msg = "CIRCUIT BREAKER TRIPPED: $leaverCount of $($hr.Count) row(s) would be disabled " +
           "(>$CircuitBreakerPercent%). Nothing has been changed. Check the HR export's Status and EndDate columns."
    Write-Warning $msg
    Set-Content -Path (Join-Path $ReportDir "circuit-breaker-$stamp.txt") -Value $msg -Encoding UTF8
    Write-Audit -Action 'CircuitBreakerTripped' -Target $HrFile -Before '' -After $msg
    exit 3
}

if (-not $PSCmdlet.ShouldProcess("$($plan.Count) change(s) in $Domain", 'Apply the JML plan')) {
    Write-Host ''
    Write-Host 'Dry run complete - nothing was changed. Re-run without -WhatIf to apply.' -ForegroundColor Cyan
    exit 0
}

# --------------------------------------------------------------------------------- applying

$initialPasswords = New-Object System.Collections.Generic.List[object]
$applied = 0

foreach ($p in $plan) {
    $row = $p.Row
    switch ($p.Kind) {

        'Joiner' {
            $desired = Resolve-DesiredGroups -Department $row.Department -Title $row.Title -Matrix $matrix
            $target  = "OU=$($row.Department),$usersOu"
            $password = New-RandomPassword
            New-ADUser -Name (Get-DisplayName -Row $row) -GivenName $row.First -Surname $row.Last `
                -SamAccountName $p.Sam -UserPrincipalName "$($p.Sam)@$Domain" -Path $target `
                -Department $row.Department -Title $row.Title -EmployeeID $row.EmployeeID `
                -Company 'Halden Distribution Ltd.' -Description 'Managed by the Halden JML engine' `
                -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
                -ChangePasswordAtLogon $true -Enabled $true
            # Mark ownership so the engine only ever touches accounts it created.
            Set-ADUser $p.Sam -Replace @{ extensionAttribute1 = 'JML-Managed' }
            foreach ($g in $desired) {
                if (Get-ADGroup -Filter "SamAccountName -eq '$g'" -ErrorAction SilentlyContinue) {
                    Add-ADGroupMember -Identity $g -Members $p.Sam -ErrorAction SilentlyContinue
                } else {
                    Write-Warning "Role group '$g' does not exist in AD; add it before relying on this role."
                }
            }
            # Manager: resolve ManagerID to the manager's account, never from a name.
            if ($row.ManagerID) {
                $mgr = $adUsers | Where-Object { $_.EmployeeID -eq $row.ManagerID } | Select-Object -First 1
                if (-not $mgr) { $mgr = Get-ADUser -Filter "EmployeeID -eq '$($row.ManagerID)'" -ErrorAction SilentlyContinue }
                if ($mgr) { Set-ADUser $p.Sam -Manager $mgr.SamAccountName }
                else { Write-Warning "Manager EmployeeID $($row.ManagerID) not found; Manager attribute left unset." }
            }
            $home = New-HomeFolder -Sam $p.Sam
            $initialPasswords.Add([pscustomobject]@{ User = $p.Sam; EmployeeID = $row.EmployeeID; InitialPassword = $password; HomeFolder = $home })
            Write-Audit -Action 'Joiner' -Target $p.Sam -Before 'no account' -After ("groups: " + ($desired -join ', ') + "; home: $home")
            $applied++
        }

        'Mover' {
            Write-Audit -Action 'Mover' -Target $p.Sam `
                -Before ("{0}/{1}; groups: {2}" -f $p.User.Department, $p.User.Title, (($p.User.MemberOf | ForEach-Object { (Get-ADGroup $_).SamAccountName }) -join ', ')) `
                -After  ("{0}/{1}; +{2}; -{3}" -f $row.Department, $row.Title, ($p.Add -join ', '), ($p.Remove -join ', '))
            # Remove before adding: never leave the mover holding both the old and the new role.
            foreach ($g in $p.Remove) { Remove-ADGroupMember -Identity $g -Members $p.Sam -Confirm:$false -ErrorAction SilentlyContinue }
            foreach ($g in $p.Add)    { Add-ADGroupMember    -Identity $g -Members $p.Sam -ErrorAction SilentlyContinue }
            Set-ADUser $p.Sam -Department $row.Department -Title $row.Title
            if ($row.ManagerID) {
                $mgr = Get-ADUser -Filter "EmployeeID -eq '$($row.ManagerID)'" -ErrorAction SilentlyContinue
                if ($mgr) { Set-ADUser $p.Sam -Manager $mgr.SamAccountName }
            }
            $targetOu = "OU=$($row.Department),$usersOu"
            if ($p.User.DistinguishedName -notlike "*,$targetOu" ) {
                Move-ADObject -Identity $p.User.DistinguishedName -TargetPath $targetOu
            }
            $applied++
        }

        'Leaver' {
            $snapshot = Join-Path $LogDir "leavers\$($row.EmployeeID).json"
            # Snapshot FIRST: the record of what the person could reach is needed for rehires and
            # investigations, and it is gone the moment the groups are removed.
            $snapshotData = [pscustomobject] @{
                EmployeeID   = $row.EmployeeID
                Sam          = $p.Sam
                DistinguishedName = $p.User.DistinguishedName
                Department   = $p.User.Department
                Title        = $p.User.Title
                EndDate      = $row.EndDate
                CapturedAt   = (Get-Date).ToString('s')
                CapturedBy   = $operator
                Groups       = @($p.User.MemberOf | ForEach-Object { (Get-ADGroup $_).SamAccountName })
                Description  = $p.User.Description
            }
            $snapshotData | ConvertTo-Json -Depth 4 | Set-Content -Path $snapshot -Encoding UTF8

            $before = "enabled, groups: " + (($p.User.MemberOf | ForEach-Object { (Get-ADGroup $_).SamAccountName }) -join ', ')
            Disable-ADAccount -Identity $p.Sam
            Set-ADAccountPassword -Identity $p.Sam -Reset `
                -NewPassword (ConvertTo-SecureString (New-RandomPassword -Length 64) -AsPlainText -Force)
            $keep = @('Domain Users')
            foreach ($groupDn in $p.User.MemberOf) {
                $g = Get-ADGroup $groupDn
                if ($keep -notcontains $g.SamAccountName -and $g.SamAccountName -notmatch '^Domain Users$') {
                    Remove-ADGroupMember -Identity $g.SamAccountName -Members $p.Sam -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            Set-ADUser $p.Sam -Description ("Leaver $($row.EndDate) - processed by the Halden JML engine $((Get-Date).ToString('yyyy-MM-dd'))")
            if ($p.User.DistinguishedName -notlike "*,$disabledOu") {
                Move-ADObject -Identity $p.User.DistinguishedName -TargetPath $disabledOu
            }
            Write-Audit -Action 'Leaver' -Target $p.Sam -Before $before -After "disabled, groups stripped, moved to OU=Disabled, snapshot $snapshot"
            $applied++
        }
    }
}

if ($initialPasswords.Count -gt 0) {
    # Git-ignored by .gitignore (logs/). Hand over securely, never by clear-text email.
    $initialPasswords | Export-Csv -Path $pwPath -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Warning "Initial passwords were written to $pwPath (git-ignored). Hand them to the line manager over the agreed secure channel and delete the file's rows after first sign-in."
}

# --- Orphan report: enabled accounts the engine owns but HR no longer lists ---------------------
$hrIds = $hr.EmployeeID
$orphans = @(Get-HaldenAdUser | Where-Object { $_.Enabled -and ($hrIds -notcontains $_.EmployeeID) })
if ($orphans.Count -gt 0) {
    $orphans | Select-Object SamAccountName, Name, Department, EmployeeID, DistinguishedName |
        Export-Csv -Path (Join-Path $ReportDir 'orphans.csv') -NoTypeInformation -Encoding UTF8
    Write-Warning "$($orphans.Count) enabled account(s) have no HR record. Written to $ReportDir\orphans.csv - review them, the engine does not change them."
}

Write-Host ''
Write-Host ("Applied $applied change(s). Audit log: $auditPath") -ForegroundColor Cyan

if ($WhatIfPreference) { exit 0 }

# --- Cloud continuation reminder (Phase 3) -----------------------------------------------------
$cloudLeavers = @($plan | Where-Object Kind -eq 'Leaver')
if ($cloudLeavers.Count -gt 0) {
    Write-Host ''
    Write-Host 'Leavers still need the cloud steps (Phase 3):' -ForegroundColor Yellow
    Write-Host '  Revoke-MgUserSignInSession <upn>                 # kills refresh tokens'
    Write-Host '  Update-MgUser -UserId <upn> -AccountEnabled:$false'
    Write-Host '  (remove the licence only after the mailbox has been handled)'
    Write-Host '  .\04-Remove-LeaverCloudAccess.ps1 -EmployeeID <id>   # does all three, with logging'
}

Write-Host ''
Write-Host 'Verify: re-run with -WhatIf. A correct, idempotent run now reports no planned changes.' -ForegroundColor Cyan

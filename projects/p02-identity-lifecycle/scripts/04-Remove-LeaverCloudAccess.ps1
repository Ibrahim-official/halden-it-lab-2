<#
.SYNOPSIS
  Phase 3: revoke a leaver's cloud access (sessions, sign-in, licence) - the online half of offboarding.

.DESCRIPTION
  For a person the on-premises engine has already processed as a leaver, this script performs the
  Microsoft Entra ID steps that AD cannot do:

    1. Revoke-MgUserSignInSession  - invalidates refresh tokens, so an already-signed-in device is
                                     thrown out at the next token refresh instead of staying alive
    2. Block sign-in               - the cloud account cannot authenticate at all
    3. Mailbox check, then licence - the licence is removed only after the mailbox has been handled
                                     (delegated or exported), so mail is not silently destroyed

  The order matters and is the point of the script: blocking sign-in without revoking refresh tokens
  leaves live sessions behind; removing a licence before handling the mailbox loses mail. Step 3 is
  therefore opt-in (-RemoveLicence) and refuses to run unless the mailbox has been addressed.

  Every action is appended to the same audit log the on-premises engine writes, so one file answers
  "what happened to this person's access, on both sides".

.PARAMETER EmployeeID
  The EmployeeID to offboard. Required. Matching is on EmployeeID, never on a name.

.PARAMETER UpnSuffix
  The tenant's verified or onmicrosoft.com UPN suffix. The lab's .internal UPN is not routable and is
  never used for cloud sign-in.

.PARAMETER MailboxHandled
  Confirms the mailbox has been dealt with (delegated or exported). Required with -RemoveLicence.

.PARAMETER RemoveLicence
  Also remove the licence. Refused unless -MailboxHandled is supplied.

.EXAMPLE
  .\04-Remove-LeaverCloudAccess.ps1 -EmployeeID '1042'
  Revoke sessions and block sign-in for that leaver.

.EXAMPLE
  .\04-Remove-LeaverCloudAccess.ps1 -EmployeeID '1042' -MailboxHandled -RemoveLicence
  The full offboarding, once the mailbox has been dealt with.

.NOTES
  Requires the Microsoft.Graph modules (Authentication, Users) and an interactive sign-in with the
  least role that can do the job (User Administrator), not Global Administrator.
  Run on DC01 or FS01. No snapshot is needed for the cloud steps; the on-premises snapshot for P3
  belongs to 05-Prepare-HybridIdentity.ps1.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [string[]] $EmployeeID,
    [string] $UpnSuffix = 'onmicrosoft.com',
    [switch] $MailboxHandled,
    [switch] $RemoveLicence,
    [string] $LogDir = "$PSScriptRoot\..\logs",
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop
foreach ($m in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Required module '$m' is not installed. Run: Install-Module $m -Scope CurrentUser"
    }
    Import-Module $m -ErrorAction Stop
}

if ($RemoveLicence -and -not $MailboxHandled) {
    throw 'Refusing to remove a licence without -MailboxHandled. Handle the mailbox first so mail is not destroyed.'
}
if ($UpnSuffix -match '\.internal$') {
    throw 'Refusing to use a .internal UPN suffix for cloud sign-in. Use the tenant''s verified or onmicrosoft.com suffix.'
}

$operator = "$env:USERDOMAIN\$env:USERNAME"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$auditPath = Join-Path $LogDir 'jml-audit.csv'

function Write-Audit {
    param([string]$Action, [string]$Target, [string]$Before = '', [string]$After = '')
    [pscustomobject] @{
        Timestamp = (Get-Date).ToString('s'); Action = $Action; Target = $Target
        Before = $Before; After = $After; Operator = $operator
    } | Export-Csv -Path $auditPath -NoTypeInformation -Append -Encoding UTF8
}

Connect-MgGraph -Scopes 'User.ReadWrite.All', 'User.EnableDisableAccount.All', 'User.RevokeSessions.All', 'LicenseAssignment.ReadWrite.All' -NoWelcome

foreach ($id in $EmployeeID) {
    $adUser = Get-ADUser -Filter "EmployeeID -eq '$id'" -Properties EmployeeID, MemberOf, Enabled -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $adUser) { Write-Warning "No AD account with EmployeeID '$id' - skipping."; continue }

    $upn = "$($adUser.SamAccountName)@$UpnSuffix"
    Write-Host "Cloud offboarding for $($adUser.SamAccountName) ($upn)" -ForegroundColor Cyan

    $mg = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if (-not $mg) {
        Write-Warning "No Entra ID object for $upn. If hybrid identity is not live yet, there is nothing to revoke - record that and move on."
        continue
    }

    if ($PSCmdlet.ShouldProcess($upn, 'Revoke sign-in sessions')) {
        Revoke-MgUserSignInSession -UserId $mg.Id
        Write-Audit -Action 'CloudRevokeSessions' -Target $upn -Before 'sessions may be live' -After 'refresh tokens invalidated'
        Write-Host '  sessions revoked' -ForegroundColor DarkGreen
    }

    if ($PSCmdlet.ShouldProcess($upn, 'Block cloud sign-in')) {
        Update-MgUser -UserId $mg.Id -AccountEnabled:$false
        Write-Audit -Action 'CloudBlockSignIn' -Target $upn -Before 'sign-in allowed' -After 'sign-in blocked'
        Write-Host '  sign-in blocked' -ForegroundColor DarkGreen
    }

    if ($RemoveLicence) {
        $licences = @(Get-MgUserLicenseDetail -UserId $mg.Id -ErrorAction SilentlyContinue)
        if ($licences.Count -eq 0) {
            Write-Host '  no licence assigned - nothing to remove' -ForegroundColor DarkYellow
        } elseif ($PSCmdlet.ShouldProcess($upn, "Remove $($licences.Count) licence(s)")) {
            $skuIds = $licences.SkuId
            Set-MgUserLicense -UserId $mg.Id -AddLicenses @() -RemoveLicenses $skuIds
            Write-Audit -Action 'CloudRemoveLicence' -Target $upn -Before ($licences.SkuPartNumber -join ', ') -After 'licence removed (mailbox handled)'
            Write-Host "  licence(s) removed: $($licences.SkuPartNumber -join ', ')" -ForegroundColor DarkGreen
        }
    } else {
        Write-Host '  licence retained - re-run with -MailboxHandled -RemoveLicence once the mailbox is dealt with' -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host "Audit log: $auditPath" -ForegroundColor Cyan
Write-Host 'Verify: the sign-in log shows the blocked account, and the device is signed out at the next token refresh.' -ForegroundColor Cyan
Write-Host 'Note: record only that the tenant is the lab trial tenant. Never publish a tenant ID, domain or object ID (AGENTS.md 4.6).' -ForegroundColor DarkYellow

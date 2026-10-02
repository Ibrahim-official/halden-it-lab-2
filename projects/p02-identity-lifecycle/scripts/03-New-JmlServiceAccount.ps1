<#
.SYNOPSIS
  Phase 1: create the least-privilege identity the JML engine runs as, and delegate only what it needs.

.DESCRIPTION
  Creates a group managed service account (gMSA) called gmsa-jml and grants it exactly the rights the
  joiner-mover-leaver engine needs, over exactly two OUs:

    OU=Users,OU=Halden       read, create/delete user objects, write the attributes the engine sets
    OU=Disabled              move user objects in and out

  It does NOT grant Domain Admin, Enterprise Admin or any other privileged group membership. The
  scheduled task then runs as this gMSA instead of as a human administrator.

  Why this matters (docs\00-design.md section 3, and the AGENTS.md pitfall list): an automation that
  can create and disable accounts is a sensitive identity. If it runs as Domain Admin, a compromised
  scheduled task owns the whole directory. Delegating two OUs means the blast radius is two OUs.

  The script also writes the exact delegated rights to a text file for the evidence folder, so the
  claim "least privilege" is backed by `dsacls` output rather than by assertion.

.PARAMETER GmsaName
  Name of the gMSA to create. Default gmsa-jml.

.PARAMETER AllowedPrincipals
  Which principals may retrieve the gMSA password (that is, run as it). Defaults to the current
  computer (DC01) so the account can be used immediately; add the host that will run the schedule
  with -AllowedPrincipals if that is not DC01.

.PARAMETER TaskAccount
  Optional: also reconfigure the 'Halden-JML-Daily' scheduled task to run as this gMSA.

.EXAMPLE
  .\03-New-JmlServiceAccount.ps1 -WhatIf
  Show what would be created and delegated, and change nothing.

.EXAMPLE
  .\03-New-JmlServiceAccount.ps1 -TaskAccount
  Create the gMSA, delegate the two OUs, and point the scheduled task at it.

.NOTES
  Run on DC01 as a Domain Admin - this is the one script in P2 that needs those rights, and it is run
  once, deliberately, to remove the need for them everywhere else.
  Snapshot DC01 first: snap-p2-ph1-before. Rollback: see the bottom of this file.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $GmsaName = 'gmsa-jml',
    [string[]] $AllowedPrincipals = @("$env:COMPUTERNAME$"),
    [string] $TaskName = 'Halden-JML-Daily',
    [switch] $TaskAccount,
    [string] $EvidencePath = "$PSScriptRoot\..\evidence\raw\p02-ph1-gmsa-delegation-result.txt",
    [string] $Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Import-Module ActiveDirectory -ErrorAction Stop

$root       = (Get-ADDomain).DistinguishedName
$usersOu    = "OU=Users,OU=Halden,$root"
$disabledOu = "OU=Disabled,$root"
$gmsaOu     = "OU=ServiceAccounts,OU=Halden,$root"

# --- Permission sets ---------------------------------------------------------------------------
# Each entry: the ADRIGHTS leaf name and a short human explanation for the evidence file.
$usersRights = @(
    @{ Right = 'ListChildren';                        Why = 'enumerate the department OUs' },
    @{ Right = 'ReadProperty';                        Why = 'compare the live account with the HR export' },
    @{ Right = 'WriteProperty';                       Why = 'set Department, Title, Manager, Description, extensionAttribute1' },
    @{ Right = 'CreateChild';                         Why = 'create the user object on the joiner path' },
    @{ Right = 'DeleteChild';                         Why = 'close out a cancelled hire (last resort, requires approval)' },
    @{ Right = 'ChangePassword';                      Why = 'reset the password on the joiner and leaver paths' },
    @{ Right = 'DeleteTree';                          Why = 'remove the home-folder stub when a hire is cancelled' }
)
$disabledRights = @(
    @{ Right = 'ListChildren';                        Why = 'confirm a leaver is already in the Disabled OU (idempotency)' },
    @{ Right = 'ReadProperty';                        Why = 'report on retained leavers' },
    @{ Right = 'WriteProperty';                       Why = 'update the Description set on the leaver path' },
    @{ Right = 'CreateChild';                         Why = 'move a user object into this OU' },
    @{ Right = 'DeleteChild';                         Why = 'move a user object back out of this OU (rehire)' }
)

Write-Host "gMSA identity for the JML engine: $GmsaName" -ForegroundColor Cyan
Write-Host "Delegated OUs: $usersOu ; $disabledOu"

# --- Create the gMSA ---------------------------------------------------------------------------
$existing = Get-ADServiceAccount -Filter "Name -eq '$GmsaName'" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "gMSA $GmsaName already exists - reusing it (idempotent)." -ForegroundColor DarkYellow
    $gmsa = $existing
} else {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'ServiceAccounts'" -SearchBase "OU=Halden,$root" -SearchScope OneLevel)) {
        if ($PSCmdlet.ShouldProcess($gmsaOu, 'Create ServiceAccounts OU')) {
            New-ADOrganizationalUnit -Name 'ServiceAccounts' -Path "OU=Halden,$root" -ProtectedFromAccidentalDeletion $true
        }
    }
    if ($PSCmdlet.ShouldProcess($GmsaName, 'Create gMSA')) {
        $gmsa = New-ADServiceAccount -Name $GmsaName -Path $gmsaOu `
            -DNSHostName "$GmsaName.$Domain" `
            -PrincipalsAllowedToRetrieveManagedPassword $AllowedPrincipals `
            -Description 'Runs the Halden JML engine. Delegated rights over OU=Users and OU=Disabled only.' `
            -Enabled $true -PassThru
    } else {
        Write-Host 'Dry run: would create the gMSA and the ServiceAccounts OU.' -ForegroundColor Cyan
    }
}

if (-not (Get-Command dsacls.exe -ErrorAction SilentlyContinue)) {
    Write-Warning 'dsacls.exe not found. Install the AD DS tools (RSAT) to apply and verify the delegation.'
}

$evidence = New-Object System.Collections.Generic.List[string]
$evidence.Add("Halden P2 - gMSA delegation evidence")
$evidence.Add("Generated: $((Get-Date).ToString('s'))  Operator: $env:USERDOMAIN\$env:USERNAME")
$evidence.Add("Account:   $GmsaName")
$evidence.Add("Domain:    $Domain")
$evidence.Add("Delegated: $usersOu")
$evidence.Add("Delegated: $disabledOu")
$evidence.Add("Principals allowed to retrieve the managed password: $($AllowedPrincipals -join ', ')")
$evidence.Add("")
$evidence.Add("NOTE: this file records DELEGATED RIGHTS only. It contains no passwords, hashes or secrets.")

function Invoke-Delegation {
    <# Apply dsacls rights on one OU, and capture the before/after access list as evidence. #>
    param(
        [Parameter(Mandatory)] [string] $OuDn,
        [Parameter(Mandatory)] $Rights,
        [Parameter(Mandatory)] [string] $Account
    )
    $path = "LDAP://$OuDn"
    $before = (dsacls $path) 2>&1 | Out-String
    foreach ($r in $Rights) {
        # Grant the right, inheritable to container objects beneath the OU.
        $args = @($path, '/I:S', '/G', "${Account}:$($r.Right)")
        if ($PSCmdlet.ShouldProcess("$OuDn -> $($r.Right)", 'Delegate')) {
            $result = (dsacls @args) 2>&1 | Out-String
            if ($result -match 'Access is denied|failed') {
                throw "dsacls failed granting $($r.Right) on $OuDn : $result"
            }
        } else {
            Write-Host ("  would grant {0,-16} on {1}" -f $r.Right, $OuDn) -ForegroundColor DarkGray
        }
    }
    $after = (dsacls $path) 2>&1 | Out-String
    $evidence.Add("")
    $evidence.Add("=== $OuDn (before) ===")
    $evidence.Add($before.Trim())
    $evidence.Add("")
    $evidence.Add("=== $OuDn (after) ===")
    $evidence.Add($after.Trim())
    foreach ($r in $Rights) { $evidence.Add("  $($r.Right) - $($r.Why)") }
}

Invoke-Delegation -OuDn $usersOu    -Rights $usersRights    -Account $GmsaName
Invoke-Delegation -OuDn $disabledOu -Rights $disabledRights -Account $GmsaName

# --- Scheduled task ----------------------------------------------------------------------------
if ($TaskAccount) {
    $action  = New-ScheduledTaskAction -Execute 'pwsh.exe' `
        -Argument "-NoLogo -NonInteractive -File `"$PSScriptRoot\01-Invoke-HaldenJML.ps1`""
    $trigger = New-ScheduledTaskTrigger -Daily -At 06:00
    $principal = New-ScheduledTaskPrincipal -UserId "$Domain\$GmsaName$" -LogonType Password -RunLevel Highest
    try {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Register scheduled task running as the gMSA')) {
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
                -Description 'Runs the Halden joiner-mover-leaver engine. Least-privilege gMSA, not Domain Admin.' -Force
            Write-Host "Scheduled task $TaskName now runs as $Domain\$GmsaName$." -ForegroundColor Cyan
            $evidence.Add("")
            $evidence.Add("Scheduled task: $TaskName, principal $Domain\$GmsaName$, trigger daily 06:00")
        }
    } catch {
        Write-Warning "Could not register the scheduled task: $($_.Exception.Message)"
        Write-Warning "A gMSA logon type for a scheduled task sometimes needs 'Password' or 'GroupManagedServiceAccount'. Try: Register-ScheduledTask -TaskName $TaskName -User 'gmsa-jml$'"
    }
} else {
    $evidence.Add("")
    $evidence.Add("Scheduled task: not configured in this run (re-run with -TaskAccount).")
}

New-Item -ItemType Directory -Force -Path (Split-Path $EvidencePath) | Out-Null
$evidence | Set-Content -Path $EvidencePath -Encoding UTF8
Write-Host ''
Write-Host "Delegation evidence written: $EvidencePath" -ForegroundColor Cyan
Write-Host 'Sanitize this file before it goes into evidence/public (AGENTS.md 4.6).' -ForegroundColor DarkYellow
Write-Host ''
Write-Host 'Verify the delegation by signing in as the gMSA context and reading one account, e.g.:' -ForegroundColor Cyan
Write-Host "  dsacls 'LDAP://$usersOu' | Select-String '$GmsaName'"
Write-Host 'The engine must NOT be a member of Domain Admins. Confirm with:'
Write-Host "  (Get-ADGroupMember 'Domain Admins').Name"

<#
Rollback
  1. Stop the scheduled task:  Disable-ScheduledTask -TaskName 'Halden-JML-Daily'
  2. Remove the delegation:    dsacls 'LDAP://OU=Users,OU=Halden,DC=ad,DC=halden,DC=internal' /R 'gmsa-jml'
                               dsacls 'LDAP://OU=Disabled,DC=ad,DC=halden,DC=internal'     /R 'gmsa-jml'
  3. Remove the gMSA:          Remove-ADServiceAccount -Identity 'gmsa-jml' -Confirm:$false
  The engine then falls back to an interactive admin account until a new identity is delegated.
#>

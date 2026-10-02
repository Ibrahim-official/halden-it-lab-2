<#
.SYNOPSIS
  P3 Phase 2: low-risk quick wins — AD Recycle Bin, Domain Admin reduction, pre-auth and
  delegation cleanup, Print Spooler off on DCs, and password policy (FGPP + default domain).
  Idempotent; every action is logged.

.DESCRIPTION
  These are the fixes that are cheap, reversible and do not need a pilot. They remove the
  easiest ways for a standard account to become a domain administrator:

    1. Enable the AD Recycle Bin (recovery, and a requirement for safe object restoration).
    2. Reduce Domain Admins to the Tier 0 admin accounts plus the built-in Administrator.
    3. Clear "Do not require Kerberos pre-authentication" where it was enabled by the seed.
    4. Remove unconstrained Kerberos delegation from member servers.
    5. Stop and disable the Print Spooler on domain controllers (PrintNightmare class of risk).
    6. Create the FGPP-Admins policy and raise the default domain policy to 14 characters.

  Nothing here is claimed to work until 11-Verify-Remediation.ps1 has been run in the lab.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER Tier0Admins
  SamAccountNames that are allowed to remain in Domain Admins. Defaults to the seeded Tier 0
  administrator plus a placeholder pattern; supply the real list once 07-Set-AdminTiering.ps1
  has created the adm-t0-* accounts.

.PARAMETER Log
  CSV action log. Defaults to ..\evidence\raw\p03-ph2-quickwins-log.csv.

.EXAMPLE
  .\05-Invoke-QuickWins.ps1 -WhatIf
  Preview every change without making it.

.EXAMPLE
  .\05-Invoke-QuickWins.ps1 -Tier0Admins Administrator,adm-t0-sara.khan

.NOTES
  Snapshot DC01 and DC02 first (snap-p3-ph2-before). Rollback: revert the snapshots, or for the
  policy items re-run 08-New-HaldenGpos.ps1 from P1 to restore the previous baseline.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string[]]$Tier0Admins = @('Administrator'),
  [string]$Log = "$PSScriptRoot\..\evidence\raw\p03-ph2-quickwins-log.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$actions = [System.Collections.Generic.List[object]]::new()
function Add-Action([string]$Item, [string]$Action, [string]$Detail) {
  $actions.Add([pscustomobject]@{ Time = Get-Date -Format s; Item = $Item; Action = $Action; Detail = $Detail })
}
$root = (Get-ADDomain).DistinguishedName
$keep = @($Tier0Admins) + @('Administrator')

# ---------------------------------------------------------------- 1. AD Recycle Bin
$recycle = Get-ADOptionalFeature 'Recycle Bin Feature'
if (@($recycle.EnabledScopes).Count -eq 0) {
  if ($PSCmdlet.ShouldProcess($Domain, 'Enable AD Recycle Bin')) {
    Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $Domain -Confirm:$false
    Add-Action '(AD Recycle Bin)' 'enabled' 'forest-wide'
  }
} else {
  Add-Action '(AD Recycle Bin)' 'exists-skip' ("already enabled for {0} scope(s)" -f @($recycle.EnabledScopes).Count)
}

# ---------------------------------------------------------------- 2. Reduce Domain Admins
$current = @(Get-ADGroupMember 'Domain Admins' | Select-Object -ExpandProperty SamAccountName)
$toRemove = @($current | Where-Object { $_ -notin $keep })
foreach ($member in $toRemove) {
  if ($PSCmdlet.ShouldProcess($member, 'Remove from Domain Admins')) {
    Remove-ADGroupMember 'Domain Admins' -Members $member -Confirm:$false
    Add-Action $member 'domain-admin-removed' 'daily-use account no longer a Domain Admin'
  }
}
if (-not $toRemove) { Add-Action '(Domain Admins)' 'exists-skip' 'membership already minimal' }

# ---------------------------------------------------------------- 3. Clear DoesNotRequirePreAuth
$noPreAuth = @(Get-ADUser -Filter 'DoesNotRequirePreAuth -eq $true' -Properties DoesNotRequirePreAuth)
foreach ($user in $noPreAuth) {
  if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Require Kerberos pre-authentication')) {
    Set-ADAccountControl -Identity $user.SamAccountName -DoesNotRequirePreAuth $false
    Add-Action $user.SamAccountName 'preauth-enabled' 'AS-REP roastable condition removed'
  }
}
if (-not $noPreAuth) { Add-Action '(pre-auth)' 'exists-skip' 'no accounts skip pre-authentication' }

# ---------------------------------------------------------------- 4. Remove unconstrained delegation
$delegated = @(Get-ADComputer -Filter 'TrustedForDelegation -eq $true' -Properties TrustedForDelegation)
foreach ($computer in $delegated) {
  if ($PSCmdlet.ShouldProcess($computer.Name, 'Remove unconstrained delegation')) {
    Set-ADComputer -Identity $computer.SamAccountName -TrustedForDelegation $false
    Add-Action $computer.Name 'delegation-removed' 'use constrained or resource-based delegation if genuinely required'
  }
}
if (-not $delegated) { Add-Action '(delegation)' 'exists-skip' 'no unconstrained delegation found' }

# ---------------------------------------------------------------- 5. Print Spooler off on DCs
$spoolerGpo = 'DC - Disable Print Spooler - v1'
$dcOu = "OU=Domain Controllers,$root"
if (-not (Get-GPO -Name $spoolerGpo -ErrorAction SilentlyContinue)) {
  if ($PSCmdlet.ShouldProcess($spoolerGpo, 'Create Print Spooler GPO')) {
    New-GPO -Name $spoolerGpo -Comment 'P3: Print Spooler disabled on domain controllers.' | Out-Null
    New-GPLink -Name $spoolerGpo -Target $dcOu | Out-Null
    Set-GPRegistryValue -Name $spoolerGpo -Key 'HKLM\SYSTEM\CurrentControlSet\Services\Spooler' `
      -ValueName 'Start' -Type DWord -Value 4 | Out-Null
    Add-Action $spoolerGpo 'created' 'Print Spooler service set to Disabled on DCs'
  }
} else {
  Add-Action $spoolerGpo 'exists-skip' 'GPO already present'
}
foreach ($dc in @('DC01', 'DC02')) {
  if ($PSCmdlet.ShouldProcess($dc, 'Stop and disable Print Spooler')) {
    try {
      Invoke-Command -ComputerName $dc -ScriptBlock {
        Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        Set-Service -Name Spooler -StartupType Disabled
      } -ErrorAction Stop
      Add-Action $dc 'spooler-disabled' 'service stopped and disabled'
    } catch {
      Add-Action $dc 'failed' "could not reach DC: $($_.Exception.Message)"
    }
  }
}

# ---------------------------------------------------------------- 6. Password policy
$fgpp = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP-Admins'" -ErrorAction SilentlyContinue
if (-not $fgpp) {
  if ($PSCmdlet.ShouldProcess('FGPP-Admins', 'Create admin fine-grained password policy')) {
    New-ADFineGrainedPasswordPolicy -Name 'FGPP-Admins' -Precedence 10 -MinPasswordLength 20 `
      -LockoutThreshold 5 -LockoutDuration 00:30:00 -LockoutObservationWindow 00:30:00 `
      -ComplexityEnabled $true -MaxPasswordAge 180.00:00:00 -Description 'P3: policy for Tier 0/1 admin accounts' | Out-Null
    Add-Action 'FGPP-Admins' 'created' '20 characters, lockout 5, max age 180 days'
  }
} else {
  Add-Action 'FGPP-Admins' 'exists-skip' 'policy already present'
}
foreach ($group in @('G_Tier0_Admins', 'G_Tier1_Admins')) {
  if (Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue) {
    $applied = @(Get-ADFineGrainedPasswordPolicySubject 'FGPP-Admins' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    if ($group -notin $applied) {
      if ($PSCmdlet.ShouldProcess($group, 'Apply FGPP-Admins')) {
        Add-ADFineGrainedPasswordPolicySubject 'FGPP-Admins' -Subjects $group
        Add-Action $group 'fgpp-applied' 'FGPP-Admins now applies'
      }
    }
  } else {
    Add-Action $group 'skipped' 'group does not exist yet - run 07-Set-AdminTiering.ps1 first'
  }
}
$pol = Get-ADDefaultDomainPasswordPolicy
if ($pol.MinPasswordLength -lt 14 -or $pol.LockoutThreshold -ne 10) {
  if ($PSCmdlet.ShouldProcess($Domain, 'Raise default domain password policy')) {
    Set-ADDefaultDomainPasswordPolicy -Identity $Domain -MinPasswordLength 14 -ComplexityEnabled $true `
      -LockoutThreshold 10 -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00
    Add-Action '(domain policy)' 'raised' 'min 14, lockout 10 / 15 minutes'
  }
} else {
  Add-Action '(domain policy)' 'exists-skip' 'policy already meets the target'
}

$actions | Export-Csv -Path $Log -NoTypeInformation -Append
Write-Output ("Quick wins complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
Write-Output 'Next: 06-Deploy-Laps.ps1.'

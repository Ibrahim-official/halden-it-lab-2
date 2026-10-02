<#
.SYNOPSIS  Phase 4: AD recovery helper - demonstrate AD Recycle Bin restore and prepare an
  authoritative restore (DSRM) for a deleted OU or object.
.DESCRIPTION  Runs on a domain controller. Two modes:
    RecycleBin  - restore a deleted object (or a whole OU and its children) with Restore-ADObject.
    Authoritative - guide (and optionally perform) an authoritative restore of a subtree.
  It is deliberately conservative: a destructive/irreversible action requires -Confirm. Supports -WhatIf.
  Snapshot first: snap-p8-ph4-before. Rollback: none for a restore (it adds objects back); a wrong
  authoritative restore is corrected forward only. Never restore a DC from a backup older than the
  tombstone lifetime (180 days).
  Lab guard: DNS root must be ad.halden.internal.
.NOTES  AD Recycle Bin must be enabled (it is on by default at Windows Server 2025 forest level).
.EXAMPLE
  .\07-Restore-ADRecovery.ps1 -Mode RecycleBin -Name 'Sales*'
  .\07-Restore-ADRecovery.ps1 -Mode RecycleBin -DistinguishedName 'OU=Sales,OU=Users,OU=Halden,DC=ad,DC=halden,DC=internal'
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [ValidateSet('RecycleBin', 'Authoritative')]
  [string]$Mode = 'RecycleBin',
  [string]$Name,
  [string]$DistinguishedName,
  [string]$Domain = 'ad.halden.internal',
  [string]$LogPath = "$PSScriptRoot\..\evidence\raw\p08-ph4-adrecovery-result.csv",
  [switch]$IncludeChildren
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Lab guard: this only ever runs against the Halden lab.
if ((Get-ADDomain).DNSRoot -ne $Domain) {
  throw 'Not the Halden lab domain. Aborting.'
}

function Get-DeletedObject {
  if ($DistinguishedName) {
    Get-ADObject -Filter 'isDeleted -eq $true' -IncludeDeletedObjects -Properties whenChanged, lastKnownParent |
      Where-Object { $_.DistinguishedName -eq $DistinguishedName }
  } elseif ($Name) {
    Get-ADObject -Filter 'isDeleted -eq $true' -IncludeDeletedObjects -Properties whenChanged, lastKnownParent |
      Where-Object { $_.Name -like $Name }
  } else {
    throw 'Provide -Name or -DistinguishedName.'
  }
}

function Restore-RecycleBin {
  $objects = @(Get-DeletedObject)
  if ($objects.Count -eq 0) { Write-Warning 'No matching deleted objects found.'; return }
  # Restore parents before children: sort by DN depth ascending.
  $ordered = $objects | Sort-Object { ($_.DistinguishedName -split ',').Count }
  $log = foreach ($o in $ordered) {
    if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Restore-ADObject (Recycle Bin)')) {
      try {
        Restore-ADObject -Identity $o.DistinguishedName -ErrorAction Stop
        [pscustomobject]@{ Time=(Get-Date).ToString('s'); Object=$o.DistinguishedName; Action='restored'; Result='ok' }
      } catch {
        [pscustomobject]@{ Time=(Get-Date).ToString('s'); Object=$o.DistinguishedName; Action='restored'; Result="failed: $($_.Exception.Message)" }
      }
    }
  }
  if ($log) {
    New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
    $log | Export-Csv -Path $LogPath -NoTypeInformation -Append
    $log | Format-Table -AutoSize
  }
  Write-Output 'Verify: the OU and its children are visible in ADUC; group memberships restored with the objects.'
}

function Invoke-Authoritative {
  if (-not $DistinguishedName) { throw 'Authoritative mode needs -DistinguishedName of the subtree root.' }
  Write-Warning 'Authoritative restore is IRREVERSIBLE and must be performed from DSRM.'
  Write-Output @"
Authoritative restore procedure (run from DSRM on the target DC):
  1. Boot the DC into DSRM (bcdedit /set safeboot dsrepair, reboot) - document the current DSRM password first.
  2. Restore the system state:   wbadmin get versions
                                 wbadmin start systemstaterecovery -version:<id> -authsysvol -quiet
  3. Mark the subtree authoritative:
       ntdsutil
       activate instance ntds
       authoritative restore
       restore subtree $DistinguishedName
       quit
       quit
  4. Remove the safe-boot flag (bcdedit /deletevalue safeboot) and reboot normally.
  5. Verify replication (repadmin /showrepl) and check SYSVOL/DFSR is consistent.
  Spoken for interviews: a non-authoritative restore brings the object back but replication would
  overwrite it from the healthy partner; an authoritative restore bumps the version number so the
  restored data WINS during replication.
"@
  if ($PSCmdlet.ShouldProcess($DistinguishedName, 'Write authoritative restore record to log')) {
    New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
    [pscustomobject]@{ Time=(Get-Date).ToString('s'); Object=$DistinguishedName; Action='authoritative-prep'; Result='procedure-printed' } |
      Export-Csv -Path $LogPath -NoTypeInformation -Append
  }
}

switch ($Mode) {
  'RecycleBin'   { Restore-RecycleBin }
  'Authoritative' { Invoke-Authoritative }
}

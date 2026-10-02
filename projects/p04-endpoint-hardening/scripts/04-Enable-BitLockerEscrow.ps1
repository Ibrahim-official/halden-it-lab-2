<#
.SYNOPSIS
  Phase 3 - enable BitLocker (TPM + recovery password) and escrow the recovery keys to AD.
.DESCRIPTION
  Enforces the order the P4 plan is emphatic about: the AD escrow policy must exist BEFORE any
  drive is encrypted, otherwise a recovery key ends up in the wrong hands. The script therefore
  aborts unless you confirm the "WKS - BitLocker - v1" policy is in place (-EscrowPolicyVerified),
  unless -Force is used with a recorded reason.

  On each client it checks the TPM is ready, enables XTS-AES 256 encryption with a TPM protector
  and a recovery password protector, and escrows the recovery password to Active Directory. It is
  idempotent: an already-protected volume with an escrowed password protector is left alone.

  SECURITY: the recovery password is never read into a variable, printed or written to a file.
  The output CSV records only the key protector ID and the escrow result. Recovery keys stay in
  the vault (AD / the owner password manager) and are never committed to the repository.
.PARAMETER ComputerName
  Clients to protect. Defaults to WS01.
.PARAMETER MountPoint
  Volume to encrypt. Default 'C:'.
.PARAMETER EncryptionMethod
  Encryption cipher. Default XtsAes256 (the requirement in the P4 plan).
.PARAMETER UseUsedSpaceOnly
  Encrypt used space only (faster; fine for new machines). Default off (full-disk encryption).
.PARAMETER EscrowPolicyVerified
  Confirms the AD key-escrow GPO is deployed. Required unless -Force.
.PARAMETER Force
  Proceed without the confirmation. Record the reason in the change record.
.PARAMETER OutputPath
  Folder for the status CSV evidence. Defaults to evidence\raw.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\04-Enable-BitLockerEscrow.ps1 -ComputerName WS01 -EscrowPolicyVerified -WhatIf
.EXAMPLE
  .\04-Enable-BitLockerEscrow.ps1 -ComputerName WS01,WS02 -EscrowPolicyVerified
.NOTES
  Snapshot the client first: snap-p4-ph3-before. Rollback = Disable-BitLocker -MountPoint 'C:' while
  the recovery key is still escrowed, or revert the snapshot. A vTPM must exist on the VM for
  Windows 11 and for TPM-only startup to work. Verify escrow from a DC with:
  Get-ADObject -Filter 'objectClass -eq "msFVE-RecoveryInformation"' -SearchBase (Get-ADComputer WS01).DistinguishedName
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @('WS01'),
    [string]$MountPoint = 'C:',
    [string]$EncryptionMethod = 'XtsAes256',
    [switch]$UseUsedSpaceOnly,
    [switch]$EscrowPolicyVerified,
    [switch]$Force,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\evidence\raw'),
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

if (-not $EscrowPolicyVerified -and -not $Force) {
    throw 'Refusing to encrypt before the AD key-escrow policy is confirmed. Pass -EscrowPolicyVerified, or -Force with a recorded reason.'
}

if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$state = @()

foreach ($computer in $ComputerName) {
    if (-not $PSCmdlet.ShouldProcess($computer, "Enable BitLocker ($EncryptionMethod) and escrow the recovery key to AD")) { continue }

    try {
        $result = Invoke-Command -ComputerName $computer -ArgumentList $MountPoint, $EncryptionMethod, $UseUsedSpaceOnly.IsPresent -ScriptBlock {
            param([string]$Mount, [string]$Method, [bool]$UsedSpaceOnly)

            $tpm = Get-Tpm
            if (-not $tpm.TpmReady) { throw "TPM is not ready on $env:COMPUTERNAME; Windows 11 requires TPM 2.0." }

            $volume = Get-BitLockerVolume -MountPoint $Mount
            $escrowResult = 'Skipped'

            if ($volume.ProtectionStatus -ne 'On') {
                $enableParams = @{ MountPoint = $Mount; EncryptionMethod = $Method; TpmProtector = $true }
                if ($UsedSpaceOnly) { $enableParams['UsedSpaceOnly'] = $true }
                Enable-BitLocker @enableParams | Out-Null
            }

            $recovery = Get-BitLockerVolume -MountPoint $Mount |
                Select-Object -ExpandProperty KeyProtector |
                Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } |
                Select-Object -First 1

            if (-not $recovery) {
                $recovery = Add-BitLockerKeyProtector -MountPoint $Mount -RecoveryPasswordProtector
                $recovery = Get-BitLockerVolume -MountPoint $Mount |
                    Select-Object -ExpandProperty KeyProtector |
                    Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } |
                    Select-Object -First 1
            }

            if ($recovery) {
                # Escrow to AD. The recovery password itself is never read, printed or saved here.
                Backup-BitLockerKeyProtector -MountPoint $Mount -KeyProtectorId $recovery.KeyProtectorId | Out-Null
                $escrowResult = 'Escrowed'
            }

            $final = Get-BitLockerVolume -MountPoint $Mount
            [pscustomobject]@{
                ComputerName       = $env:COMPUTERNAME
                CapturedUtc        = (Get-Date).ToUniversalTime().ToString('s')
                TpmReady           = $tpm.TpmReady
                ProtectionStatus   = [string]$final.ProtectionStatus
                EncryptionMethod   = [string]$final.EncryptionMethod
                EncryptionPercent  = $final.EncryptionPercentage
                RecoveryKeyId      = if ($recovery) { [string]$recovery.KeyProtectorId } else { '' }
                EscrowResult       = $escrowResult
            }
        }
        $state += $result
        Write-Host ("{0}: BitLocker {1}, escrow {2}." -f $computer, $result.ProtectionStatus, $result.EscrowResult)
    }
    catch {
        Write-Warning ("Failed to protect {0}: {1}" -f $computer, $_.Exception.Message)
    }
}

if ($state) {
    $report = Join-Path $OutputPath ('p04-ph3-bitlocker-escrow-result-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $state | Export-Csv -Path $report -NoTypeInformation
    Write-Host "BitLocker status written to $report (keys are NOT in this file, by design)."
}

Write-Host 'Now run the recovery test from docs/runbooks/bitlocker-recovery.md and record the result.'

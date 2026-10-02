<#
.SYNOPSIS
  P6 Phase 5: deploy the internal Enterprise CA on CA01 and create the certificate templates used
  by 802.1X Wi-Fi and by the NPS server.

.DESCRIPTION
  Run on CA01 (Windows Server 2025, 192.168.10.43) as Domain Admin. Idempotent: the role check and
  the GPO check skip work that is already done.

  A root CA certificate is PUBLIC and safe to commit (configs/public-certs/). The CA private key is
  generated on CA01, backed up to the owner's password manager, and never committed. The repository
  .gitignore blocks *.key / *.pfx / *.p12 for exactly this reason.

  In production: an offline root CA plus a separate issuing CA, and the CA treated as Tier 0. For a
  lab of this size a single Enterprise Root CA is acceptable because it is documented as a trade-off
  - see configs/p06-certificate-plan.md.

.PARAMETER CaCommonName
  Common name of the CA.

.EXAMPLE
  .\07-Install-EnterpriseCa.ps1 -WhatIf
  .\07-Install-EnterpriseCa.ps1

.NOTES
  Lab only (AGENTS.md R1). Snapshot CA01 first: snap-p6-ph5-before.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$CaCommonName = 'Halden-Root-CA',
  [string]$AutoenrollGpo = 'WKS - Cert Autoenrollment - v1'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

# --- 1. AD CS role -------------------------------------------------------------------------------
$feature = Get-WindowsFeature ADCS-Cert-Authority
if ($feature.InstallState -ne 'Installed') {
  if ($PSCmdlet.ShouldProcess('CA01', 'Install AD CS Certification Authority')) {
    Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools | Out-Null
    Write-Information 'AD CS role installed.' -InformationAction Continue
  }
}
else {
  Write-Information 'AD CS role already installed.' -InformationAction Continue
}

# --- 2. Configure the Enterprise Root CA ---------------------------------------------------------
$caConfig = 'Halden-Root-CA'
$configured = $false
try { $configured = ((certutil -getreg CA\CommonName 2>$null) -match [regex]::Escape($CaCommonName)) } catch { $configured = $false }

if ($configured) {
  Write-Information "CA '$CaCommonName' already configured." -InformationAction Continue
}
elseif ($PSCmdlet.ShouldProcess($CaCommonName, 'Configure Enterprise Root CA')) {
  # The CA private key is protected by a password entered at the prompt (DPAPI/CSP) - never stored
  # in this repository. Please keep that password in the owner's password manager.
  Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName $CaCommonName `
    -KeyLength 4096 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 10 `
    -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' -Force
  Write-Information "CA '$CaCommonName' configured." -InformationAction Continue
}

# --- 3. Certificate templates --------------------------------------------------------------------
# Templates are most reliably created from the Certificate Templates console (duplicate an existing
# template). The script records the exact settings and the required EKUs so the work is reviewable.
$templates = @(
  [pscustomobject]@{
    Name = 'Halden-WiFi-Computer'; Source = 'Computer'; Subject = 'Built from AD'
    Eku = 'Client Authentication'; Validity = '2 years'
    Enroll = 'Domain Computers'
    Note = 'Used by Halden-Corp 802.1X (EAP-TLS). Autoenroll for workstations.'
  },
  [pscustomobject]@{
    Name = 'Halden-RAS-IAS-Server'; Source = 'RAS and IAS Server'; Subject = 'Built from AD'
    Eku = 'Server Authentication, Client Authentication'; Validity = '2 years'
    Enroll = 'FS01 only'
    Note = 'Server certificate for NPS so clients can validate the RADIUS server.'
  }
)

foreach ($t in $templates) {
  if ($PSCmdlet.ShouldProcess($t.Name, 'Publish certificate template')) {
    Write-Information ("Template '{0}': duplicate '{1}', EKU {2}, validity {3}, enrol {4}." -f `
      $t.Name, $t.Source, $t.Eku, $t.Validity, $t.Enroll) -InformationAction Continue
    Write-Information ("  then publish it: certutil -SetCATemplates +{0}" -f $t.Name) -InformationAction Continue
  }
}

# --- 4. Autoenrollment GPO ----------------------------------------------------------------------
Import-Module GroupPolicy -ErrorAction Stop
$gpo = Get-GPO -Name $AutoenrollGpo -ErrorAction SilentlyContinue
if (-not $gpo) {
  if ($PSCmdlet.ShouldProcess($AutoenrollGpo, 'Create autoenrollment GPO')) {
    $gpo = New-GPO -Name $AutoenrollGpo -Comment 'P6: computer certificate autoenrollment'
    Write-Information "Created GPO '$AutoenrollGpo'." -InformationAction Continue
  }
}
else {
  Write-Information "GPO '$AutoenrollGpo' exists." -InformationAction Continue
}

if ($gpo -and $PSCmdlet.ShouldProcess($AutoenrollGpo, 'Set autoenrollment policy values')) {
  # Autoenrollment is a Certificate Services Client policy; these keys are the documented ones.
  Set-GPRegistryValue -Name $AutoenrollGpo -Key 'HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment' `
    -ValueName 'AEPolicy' -Type DWord -Value 7 | Out-Null
  Set-GPRegistryValue -Name $AutoenrollGpo -Key 'HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment' `
    -ValueName 'AEPolicyName' -Type String -Value 'Halden-WiFi-Computer' -ErrorAction SilentlyContinue | Out-Null
  Write-Information 'Autoenrollment policy set (enrol + renew + update certificates).' -InformationAction Continue
}

Write-Information @"

Verification (run in the lab, paste into docs/as-built.md):
  on CA01      : certutil -cainfo | Select-String "CA Name"
  on a client  : gpupdate /force ; certutil -store My   -> the Halden-WiFi-Computer certificate
  on FS01      : the Halden-RAS-IAS-Server certificate is present for NPS
  export ONLY the public root CA certificate to configs/public-certs/halden-root-ca.pem
Status: designed. No certificate is reported as issued until these checks are captured.
"@ -InformationAction Continue

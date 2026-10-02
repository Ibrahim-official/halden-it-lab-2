<#
.SYNOPSIS
  P6 Phase 5: create the wireless Group Policy for the corporate 802.1X (EAP-TLS) SSID and retire
  the shared pre-shared key.

.DESCRIPTION
  Run on DC01. The Wireless Network (IEEE 802.11) policy is not registry-backed, so the script
  creates the GPO and writes the WLAN policy XML next to it for import through the Group Policy
  Management Console - that keeps the whole change reviewable rather than half-scripted and half
  remembered. The guest SSID is not published by GPO; it is open with a captive portal on VLAN 50.

  Idempotent: the GPO is created once and left alone on re-run.

.PARAMETER Ssid
  Corporate SSID. Default: Halden-Corp.

.PARAMETER GpoName
  Wireless GPO name. Default: 'WKS - Wireless - v1'.

.EXAMPLE
  .\08-Configure-8021xWifi.ps1 -WhatIf
  .\08-Configure-8021xWifi.ps1

.NOTES
  Lab only (AGENTS.md R1). Wi-Fi changes only matter once an access point exists; without one the
  eapol_test validation in 10-Test-EapTls.sh still proves the RADIUS and certificate path.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [string]$Ssid = 'Halden-Corp',
  [string]$GpoName = 'WKS - Wireless - v1',
  [string]$RadiusServer = 'fs01.ad.halden.internal',
  [string]$OutputDir = (Join-Path $PSScriptRoot '..\configs')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
Import-Module GroupPolicy -ErrorAction Stop

# --- 1. The GPO ----------------------------------------------------------------------------------
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
  if ($PSCmdlet.ShouldProcess($GpoName, 'Create wireless GPO')) {
    $gpo = New-GPO -Name $GpoName -Comment 'P6: corporate 802.1X EAP-TLS wireless policy'
    Write-Information "Created GPO '$GpoName'." -InformationAction Continue
  }
}
else {
  Write-Information "GPO '$GpoName' already exists." -InformationAction Continue
}

# --- 2. WLAN policy XML for import ---------------------------------------------------------------
# The settings below are exactly the security decisions in docs/00-design.md section 8 and
# configs/p06-wifi-8021x.conf. The owner imports the XML through:
#   GPMC > <GPO> > Computer Configuration > Policies > Windows Settings > Security Settings >
#   Wireless Network (IEEE 802.11) Policies > Create A New Wireless Network Policy > import.
$wlanXml = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- P6 corporate wireless policy. No secrets: EAP-TLS uses certificates, not a shared key. -->
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$Ssid</name>
  <SSIDConfig>
    <SSID>
      <name>$Ssid</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA3ENT</authentication>
        <encryption>AES</encryption>
        <useOneX>true</useOneX>
      </authEncryption>
      <OneX xmlns="http://www.microsoft.com/networking/OneX/v1">
        <authMode>machine</authMode>
        <EAPConfig>
          <EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
            <EapMethod>
              <Type xmlns="http://www.microsoft.com/provisioning/EapCommon">13</Type>
              <VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId>
              <VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType>
              <AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</AuthorId>
            </EapMethod>
            <Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
              <EapType xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV1">
                <CredentialsSource>
                  <CertificateStore>
                    <SimpleCertSelection>true</SimpleCertSelection>
                  </CertificateStore>
                </CredentialsSource>
                <ServerValidation>
                  <DisableUserPromptForServerValidation>true</DisableUserPromptForServerValidation>
                  <ServerNames>$RadiusServer</ServerNames>
                  <TrustedRootCAHash>HALDEN-ROOT-CA-PUBLIC-CERT-THUMBPRINT</TrustedRootCAHash>
                </ServerValidation>
                <DifferentUsername>false</DifferentUsername>
                <PerformServerValidation>true</PerformServerValidation>
              </EapType>
            </Config>
          </EapHostConfig>
        </EAPConfig>
      </OneX>
    </security>
  </MSM>
</WLANProfile>
"@
$xmlPath = Join-Path $OutputDir 'p06-wifi-corp-wlan-profile.xml'
if ($PSCmdlet.ShouldProcess($xmlPath, 'Write WLAN policy XML')) {
  Set-Content -Path $xmlPath -Value $wlanXml -Encoding UTF8
  Write-Information "WLAN policy XML written to $xmlPath (import it through GPMC)." -InformationAction Continue
}

# --- 3. Retire the shared PSK --------------------------------------------------------------------
Write-Information @"

Retiring the shared pre-shared key (do this only once clients can join Halden-Corp by certificate):
  1. Confirm every domain computer has the autoenrolled certificate (certutil -store My).
  2. Change the access point so the old PSK SSID is off and Halden-Corp (802.1X) is on.
  3. Send the staff notice (business/p06-guest-wifi-notice.md covers guests;
     business/p06-network-access-policy.md covers the corporate change).
  4. Reception issues guest vouchers for Halden-Guest (VLAN 50, client isolation, internet only).

Verification (lab phase, pasted into docs/as-built.md): a domain computer joins by certificate; a
device with no certificate is rejected; the guest SSID cannot reach any 192.168.x internal address.
Status: designed. Nothing is claimed until the tests run.
"@ -InformationAction Continue

<#
.SYNOPSIS  Phase 1: static IP, forest promotion, DNS forwarders/reverse zone/scavenging, time source.
.DESCRIPTION Run on DC01 (local admin) in two stages: -Stage Promote (reboots), then -Stage Configure.
  Snapshot first: snap-p1-ph1-before. Rollback: revert snapshot (nothing else exists yet).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('Promote','Configure')][string]$Stage = 'Promote',
  [string]$Domain = 'ad.halden.internal', [string]$Netbios = 'HALDEN',
  [string]$Ip = '192.168.10.10', [string]$Gateway = '192.168.10.1',
  [string[]]$Forwarders = @('9.9.9.9','1.1.1.1'), [string]$NtpPeer = 'time.windows.com'
)
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
Start-Transcript -Path "$PSScriptRoot\..\logs\01-$Stage-$(Get-Date -f yyyyMMdd).log" -Append -ErrorAction SilentlyContinue
if ($Stage -eq 'Promote') {
  if ($env:COMPUTERNAME -ne 'DC01') { if ($PSCmdlet.ShouldProcess('DC01','Rename+restart')) { Rename-Computer DC01 -Restart }; return }
  $nic = (Get-NetAdapter | Where-Object Status -eq Up | Select-Object -First 1).Name
  if (-not (Get-NetIPAddress -IPAddress $Ip -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess($nic,"Set $Ip")) {
    New-NetIPAddress -InterfaceAlias $nic -IPAddress $Ip -PrefixLength 24 -DefaultGateway $Gateway | Out-Null }
  Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses 127.0.0.1
  if ((Get-WindowsFeature AD-Domain-Services).InstallState -ne 'Installed') { Install-WindowsFeature AD-Domain-Services,DNS -IncludeManagementTools | Out-Null }
  if ($PSCmdlet.ShouldProcess($Domain,'Install-ADDSForest')) {
    Install-ADDSForest -DomainName $Domain -DomainNetbiosName $Netbios -ForestMode Win2025 -DomainMode Win2025 -InstallDns `
      -SafeModeAdministratorPassword (Read-Host -AsSecureString 'DSRM password (store in password manager)') -Force }
  return
}
# --- Configure (after reboot) ---
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
Set-DnsServerForwarder -IPAddress $Forwarders
if (-not (Get-DnsServerZone -Name '10.168.192.in-addr.arpa' -ErrorAction SilentlyContinue)) {
  Add-DnsServerPrimaryZone -NetworkId '192.168.10.0/24' -ReplicationScope Domain }
Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00 -ApplyOnAllZones
foreach ($z in $Domain,'10.168.192.in-addr.arpa') { Set-DnsServerZoneAging -Name $z -Aging $true -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00 }
w32tm /config /manualpeerlist:"$NtpPeer,0x8" /syncfromflags:manual /reliable:yes /update | Out-Null
Restart-Service w32time
Add-DnsServerResourceRecordA -ZoneName $Domain -Name 'fs01' -IPv4Address 192.168.10.20 -CreatePtr -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -ZoneName $Domain -Name 'lnx01' -IPv4Address 192.168.10.30 -CreatePtr -ErrorAction SilentlyContinue
dcdiag /q; w32tm /query /status | Select-String 'Source|Stratum'
Stop-Transcript -ErrorAction SilentlyContinue

<#
.SYNOPSIS  Phase 3: DHCP on DC01+DC02, scope, options, 50/50 failover, name protection, dedicated DNS credential.
.DESCRIPTION Run on DC01 as Domain Admin (needs WinRM to DC02). Snapshot both DCs first (snap-p1-ph3-before).
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Domain='ad.halden.internal')
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
$root = (Get-ADDomain).DistinguishedName
if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc-dhcpdns'")) {   # low-privilege DNS update account
  New-ADUser svc-dhcpdns -Path "OU=ServiceAccounts,OU=Halden,$root" -AccountPassword (Read-Host -AsSecureString 'svc-dhcpdns password (password manager)') `
    -PasswordNeverExpires $true -CannotChangePassword $true -Enabled $true -Description 'DHCP dynamic DNS updates only' }
$cred = Get-Credential -UserName 'HALDEN\svc-dhcpdns' -Message 'svc-dhcpdns'
foreach ($dc in 'DC01','DC02') {
  Invoke-Command -ComputerName $dc -ScriptBlock {
    if ((Get-WindowsFeature DHCP).InstallState -ne 'Installed') { Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null }
    Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue } }
Add-DhcpServerInDC -DnsName "dc01.$Domain" -IPAddress 192.168.10.10 -ErrorAction SilentlyContinue
Add-DhcpServerInDC -DnsName "dc02.$Domain" -IPAddress 192.168.10.11 -ErrorAction SilentlyContinue
if (-not (Get-DhcpServerv4Scope -ScopeId 192.168.10.0 -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess('HQ-Clients','Create scope')) {
  Add-DhcpServerv4Scope -Name 'HQ-Clients' -StartRange 192.168.10.100 -EndRange 192.168.10.200 -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 }
Set-DhcpServerv4OptionValue -ScopeId 192.168.10.0 -Router 192.168.10.1 -DnsServer 192.168.10.10,192.168.10.11 -DnsDomain $Domain
Set-DhcpServerv4DnsSetting -ScopeId 192.168.10.0 -DynamicUpdates Always -DeleteDnsRROnLeaseExpiry $true -NameProtection $true
Set-DhcpServerDnsCredential -Credential $cred
if (-not (Get-DhcpServerv4Failover -Name 'HQ-Failover' -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess('HQ-Failover','Create failover')) {
  Add-DhcpServerv4Failover -Name 'HQ-Failover' -PartnerServer "dc02.$Domain" -ScopeId 192.168.10.0 -LoadBalancePercent 50 `
    -SharedSecret (Read-Host 'Failover shared secret (password manager)') -AutoStateTransition $true -MaxClientLeadTime 01:00:00 }
Get-DhcpServerv4Failover | Format-List Name,State,Mode,LoadBalancePercent,MaxClientLeadTime
# TEST: power off DC01; on WS01 run: ipconfig /release ; ipconfig /renew  (lease must come from DC02)

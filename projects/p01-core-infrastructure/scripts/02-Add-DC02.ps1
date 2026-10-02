<#
.SYNOPSIS  Phase 2: promote DC02, fix DNS client order, create sites/subnets, verify replication.
.DESCRIPTION Run on DC02 (-Stage Promote, after setting its DNS to DC01), then on DC01 (-Stage Sites).
  Snapshot: snap-p1-ph2-before (DC02 only; do not revert DC01 afterwards).
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Promote','Sites','Verify')][string]$Stage='Promote', [string]$Domain='ad.halden.internal')
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
switch ($Stage) {
 'Promote' {
  $nic = (Get-NetAdapter | Where-Object Status -eq Up | Select-Object -First 1).Name
  if ($env:COMPUTERNAME -ne 'DC02') { if ($PSCmdlet.ShouldProcess('DC02','Rename+restart')) { Rename-Computer DC02 -Restart }; return }
  if (-not (Get-NetIPAddress -IPAddress 192.168.10.11 -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceAlias $nic -IPAddress 192.168.10.11 -PrefixLength 24 -DefaultGateway 192.168.10.1 | Out-Null }
  Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses 192.168.10.10
  Install-WindowsFeature AD-Domain-Services,DNS -IncludeManagementTools | Out-Null
  if ($PSCmdlet.ShouldProcess($Domain,'Install-ADDSDomainController')) {
    Install-ADDSDomainController -DomainName $Domain -InstallDns -Credential (Get-Credential -Message 'HALDEN\Administrator') `
      -SafeModeAdministratorPassword (Read-Host -AsSecureString 'DSRM password') -Force }
 }
 'Sites' {   # run on DC01 once DC02 is up; also set NIC DNS order (peer first, self second)
  if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
  $nic = (Get-NetAdapter | Where-Object Status -eq Up | Select-Object -First 1).Name
  $peer = if ($env:COMPUTERNAME -eq 'DC01') { '192.168.10.11','192.168.10.10' } else { '192.168.10.10','192.168.10.11' }
  Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses $peer
  if (Get-ADReplicationSite 'Default-First-Site-Name' -ErrorAction SilentlyContinue) { Get-ADReplicationSite 'Default-First-Site-Name' | Rename-ADObject -NewName HQ }
  if (-not (Get-ADReplicationSite -Filter "Name -eq 'WAREHOUSE'")) { New-ADReplicationSite WAREHOUSE }
  foreach ($s in @(@('192.168.10.0/24','HQ'),@('192.168.20.0/24','WAREHOUSE'))) {
    if (-not (Get-ADReplicationSubnet -Filter "Name -eq '$($s[0])'")) { New-ADReplicationSubnet -Name $s[0] -Site $s[1] } }
  foreach ($dc in 'DC01','DC02') { Move-ADDirectoryServer -Identity $dc -Site HQ -ErrorAction SilentlyContinue }
 }
 'Verify' {
  repadmin /replsummary; dcdiag /e /q
  Get-ADDomainController -Filter * | Select-Object Name,IsGlobalCatalog,@{n='FSMO';e={$_.OperationMasterRoles -join ','}}
 }
}

<#
.SYNOPSIS  Phase 4a: OU tree, AGDLP groups, service account OU. Idempotent. Run on DC01.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Domain='ad.halden.internal')
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
$root = (Get-ADDomain).DistinguishedName
function New-Ou([string]$Name,[string]$Path) {
  if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel)) {
    if ($PSCmdlet.ShouldProcess("OU=$Name,$Path",'Create OU')) { New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true } } }
New-Ou '_Admin' $root; New-Ou 'Halden' $root; New-Ou 'Disabled' $root
$h = "OU=Halden,$root"
'Users','Computers','Groups','Servers','ServiceAccounts' | ForEach-Object { New-Ou $_ $h }
'Management','Finance','HR','Sales','Operations','IT' | ForEach-Object { New-Ou $_ "OU=Users,$h" }
'Workstations','Laptops','Kiosks' | ForEach-Object { New-Ou $_ "OU=Computers,$h" }
'Role','Resource' | ForEach-Object { New-Ou $_ "OU=Groups,$h" }
'File','App','Linux' | ForEach-Object { New-Ou $_ "OU=Servers,$h" }

function New-Grp([string]$Name,[string]$Scope,[string]$Ou) {
  if (-not (Get-ADGroup -Filter "Name -eq '$Name'")) {
    if ($PSCmdlet.ShouldProcess($Name,'Create group')) { New-ADGroup -Name $Name -GroupScope $Scope -Path "OU=$Ou,OU=Groups,$h" } } }
'G_Management','G_Finance_Staff','G_HR_Staff','G_Sales_Staff','G_Operations_Staff','G_IT_Staff','G_IT_LinuxAdmins','G_AllStaff' | ForEach-Object { New-Grp $_ Global Role }
# DL group -> members (AGDLP). Only DL_ groups ever go on ACLs.
$dl = [ordered]@{
 'DL_Share-Finance_RW'=@('G_Finance_Staff'); 'DL_Share-Finance_RO'=@('G_Management')
 'DL_Share-HR_RW'=@('G_HR_Staff');           'DL_Share-HR_RO'=@('G_Management')
 'DL_Share-Sales_RW'=@('G_Sales_Staff');     'DL_Share-Operations_RW'=@('G_Operations_Staff')
 'DL_Share-Company_RO'=@('G_AllStaff');      'DL_Share-Users_Home'=@('G_AllStaff') }
foreach ($k in $dl.Keys) {
  New-Grp $k DomainLocal Resource
  foreach ($m in $dl[$k]) { if ($PSCmdlet.ShouldProcess("$m -> $k",'Add member')) { Add-ADGroupMember -Identity $k -Members $m -ErrorAction SilentlyContinue } } }

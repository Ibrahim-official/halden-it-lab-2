<#
.SYNOPSIS  Phase 5: FS01 shares, AGDLP NTFS ACLs, ABE, DFS namespace, FSRM quota/screens/reports, shadow copies.
.DESCRIPTION Run on FS01 (domain-joined, Domain Admin). Snapshot first: snap-p1-ph5-before.
  Only DL_ groups, SYSTEM and Administrators are ever placed on ACLs (verified by 07-Test-ShareAcl.ps1).
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Domain='ad.halden.internal', [string]$Base='C:\Shares', [string]$Nb='HALDEN')
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
if ((Get-CimInstance Win32_ComputerSystem).Domain -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
Install-WindowsFeature FS-FileServer,FS-DFS-Namespace,FS-Resource-Manager,RSAT-DFS-Mgmt-Con,RSAT-FSRM-Mgmt -IncludeManagementTools | Out-Null
# share -> (DL_ RW group, DL_ RO groups, DFS folder name)
$shares = [ordered]@{
 Finance   = @{ rw='DL_Share-Finance_RW';    ro=@('DL_Share-Finance_RO');  dfs='Finance' }
 HR        = @{ rw='DL_Share-HR_RW';         ro=@('DL_Share-HR_RO');       dfs='HR' }
 Sales     = @{ rw='DL_Share-Sales_RW';      ro=@();                       dfs='Sales' }
 Operations= @{ rw='DL_Share-Operations_RW'; ro=@();                       dfs='Operations' }
 Company   = @{ rw=$null;                    ro=@('DL_Share-Company_RO');  dfs='Shared' } }
foreach ($n in $shares.Keys) {
  $s = $shares[$n]; $path = Join-Path $Base $n
  New-Item -ItemType Directory -Force $path | Out-Null
  $g = @("SYSTEM:(OI)(CI)F","Administrators:(OI)(CI)F")
  if ($s.rw) { $g += "${Nb}\$($s.rw):(OI)(CI)M" }
  foreach ($r in $s.ro) { $g += "${Nb}\${r}:(OI)(CI)RX" }
  if ($PSCmdlet.ShouldProcess($path,'Set NTFS ACL')) { icacls $path /inheritance:r /grant:r @g | Out-Null }
  if (-not (Get-SmbShare -Name $n -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess($n,'Create share')) {
    New-SmbShare -Name $n -Path $path -ChangeAccess 'Authenticated Users' -FolderEnumerationMode AccessBased | Out-Null }
}
# Home folders: DL_Share-Users_Home may list + create a subfolder (this folder only); the creator owns their own folder.
$homeDir = Join-Path $Base 'Users$'; New-Item -ItemType Directory -Force $homeDir | Out-Null
icacls $homeDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "${Nb}\DL_Share-Users_Home:(RX,AD)" "CREATOR OWNER:(OI)(CI)(IO)M" | Out-Null
if (-not (Get-SmbShare -Name 'Users$' -ErrorAction SilentlyContinue)) { New-SmbShare -Name 'Users$' -Path $homeDir -ChangeAccess 'Authenticated Users' -FolderEnumerationMode AccessBased | Out-Null }
# DFS namespace \\ad.halden.internal\Company\<folder>
$rootDir = Join-Path $Base '_DfsRoot'; New-Item -ItemType Directory -Force $rootDir | Out-Null
if (-not (Get-SmbShare -Name 'CompanyRoot' -ErrorAction SilentlyContinue)) { New-SmbShare -Name CompanyRoot -Path $rootDir -ReadAccess 'Authenticated Users' | Out-Null }
if (-not (Get-DfsnRoot -Path "\\$Domain\Company" -ErrorAction SilentlyContinue)) {
  New-DfsnRoot -Path "\\$Domain\Company" -TargetPath "\\FS01.$Domain\CompanyRoot" -Type DomainV2 -EnableAccessBasedEnumeration $true | Out-Null }
foreach ($n in $shares.Keys) {
  $p = "\\$Domain\Company\$($shares[$n].dfs)"
  if (-not (Get-DfsnFolder -Path $p -ErrorAction SilentlyContinue)) { New-DfsnFolder -Path $p -TargetPath "\\FS01.$Domain\$n" | Out-Null } }
# FSRM: 10 GB soft quota on home folders, executable screen on shared folders, weekly report
if (-not (Get-FsrmQuotaTemplate 'Home 10GB Soft' -ErrorAction SilentlyContinue)) { New-FsrmQuotaTemplate -Name 'Home 10GB Soft' -Size 10GB -SoftLimit }
if (-not (Get-FsrmAutoQuota -Path $homeDir -ErrorAction SilentlyContinue)) { New-FsrmAutoQuota -Path $homeDir -Template 'Home 10GB Soft' | Out-Null }
if (-not (Get-FsrmFileScreenTemplate 'Block Executables' -ErrorAction SilentlyContinue)) {
  New-FsrmFileScreenTemplate -Name 'Block Executables' -Active -IncludeGroup 'Executable Files' | Out-Null }
foreach ($n in $shares.Keys) { $p = Join-Path $Base $n
  if (-not (Get-FsrmFileScreen -Path $p -ErrorAction SilentlyContinue)) { New-FsrmFileScreen -Path $p -Template 'Block Executables' | Out-Null } }
if (-not (Get-FsrmStorageReport 'Weekly Large Files' -ErrorAction SilentlyContinue)) {
  New-FsrmStorageReport -Name 'Weekly Large Files' -Namespace $Base -ReportType LargeFiles,DuplicateFiles -Schedule (New-FsrmScheduledTask -Time (Get-Date '02:00') -Weekly Sunday) | Out-Null }
# Shadow copies twice daily (07:00, 12:00) on the data volume; real backups come in P8
$vol = (Split-Path $Base -Qualifier) + '\'
vssadmin Resize ShadowStorage /For=$vol /On=$vol /MaxSize=15% | Out-Null
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -Command `"Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{Volume='$vol';Context='ClientAccessible'}`""
if (-not (Get-ScheduledTask 'Halden-ShadowCopy' -ErrorAction SilentlyContinue)) {
  Register-ScheduledTask 'Halden-ShadowCopy' -Action $act -User SYSTEM -RunLevel Highest -Trigger (New-ScheduledTaskTrigger -Daily -At 7am),(New-ScheduledTaskTrigger -Daily -At 12pm) | Out-Null }
Get-SmbShare | Where-Object { $_.Name -in $shares.Keys + 'Users$' } | Format-Table Name,Path,FolderEnumerationMode

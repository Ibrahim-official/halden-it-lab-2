<#
.SYNOPSIS  Phase 6: Central Store, six baseline GPOs (+kiosk lockdown), links, GPO backup. Idempotent. Run on DC01.
.DESCRIPTION Snapshot first: snap-p1-ph6-before. Verify on WS01: gpupdate /force; gpresult /h C:\gp.html
  Drive maps (GPP) are written to SYSVOL as Drives.xml with group item-level targeting; loopback (merge)
  makes the user-side drive maps apply on workstations. Rollback: Remove-GPLink / Remove-GPO by name.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Domain='ad.halden.internal', [string]$BackupPath="$PSScriptRoot\..\configs\gpo-backup")
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
$dn = (Get-ADDomain).DistinguishedName; $h = "OU=Halden,$dn"; $sysvol = "\\$Domain\SYSVOL\$Domain\Policies"
if (-not (Test-Path "$sysvol\PolicyDefinitions")) { Copy-Item "$env:windir\PolicyDefinitions" "$sysvol\PolicyDefinitions" -Recurse }  # Central Store
function Get-OrNewGpo($n) { $g = Get-GPO -Name $n -ErrorAction SilentlyContinue; if (-not $g) { $g = New-GPO -Name $n }; $g }
function Link($g,$target) { if (-not (Get-GPInheritance -Target $target).GpoLinks.DisplayName.Contains($g.DisplayName)) { New-GPLink -Name $g.DisplayName -Target $target | Out-Null } }
function Add-Ext($g,$side,$ext,$tool) {   # register a client-side extension and bump the SYSVOL version
  $o = Get-ADObject "CN={$($g.Id)},CN=Policies,CN=System,$dn" -Properties versionNumber,gPC${side}ExtensionNames
  $pair = "[{$ext}{$tool}]"; $cur = [string]$o."gPC${side}ExtensionNames"
  if ($cur -notlike "*$ext*") { Set-ADObject $o -Replace @{"gPC${side}ExtensionNames"=($cur+$pair); versionNumber=([int]$o.versionNumber + $(if($side -eq 'User'){65536}else{1}))} } }

# 1 Password & lockout (security template written into the GPO; applies at domain root)
$g = Get-OrNewGpo 'DOMAIN - Password & Lockout - v1'
$inf = "$sysvol\{$($g.Id)}\Machine\Microsoft\Windows NT\SecEdit"; New-Item -ItemType Directory -Force $inf | Out-Null
@"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordLength = 14
PasswordComplexity = 1
LockoutBadCount = 10
ResetLockoutCount = 15
LockoutDuration = 15
[Version]
signature="`$CHICAGO`$"
Revision=1
"@ | Set-Content "$inf\GptTmpl.inf" -Encoding Unicode
Add-Ext $g 'Machine' '827D319E-6EAC-11D2-A4EA-00C04F79F83A' '803E14A0-B4FB-11D0-A0D0-00A0C90F574B'
Link $g $dn
# 2 Drive maps with item-level targeting (F: Finance, H: HR, S: Sales, O: Operations, G: Shared)
$g = Get-OrNewGpo 'WKS - Drive Maps - v1'
Set-GPRegistryValue $g -Key 'HKLM\Software\Policies\Microsoft\Windows\System' -ValueName UserPolicyMode -Type DWord -Value 1   # loopback: merge
$maps = @(@('F','Finance','G_Finance_Staff'),@('H','HR','G_HR_Staff'),@('S','Sales','G_Sales_Staff'),@('O','Operations','G_Operations_Staff'),@('G','Shared','G_AllStaff'))
$x = '<?xml version="1.0" encoding="utf-8"?><Drives clsid="{8FDDCC1A-0C3C-43cd-A6B4-5FB4E8D9BF17}">'
foreach ($m in $maps) { $u=[guid]::NewGuid().ToString('B').ToUpper()
  $x += "<Drive clsid=`"{935D1B74-9CB8-4e3c-9914-7DD559B7A417}`" name=`"$($m[0]):`" status=`"$($m[0]):`" image=`"2`" changed=`"$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')`" uid=`"$u`"><Properties action=`"U`" thisDrive=`"NOCHANGE`" allDrives=`"NOCHANGE`" userName=`"`" path=`"\\$Domain\Company\$($m[1])`" label=`"$($m[1])`" persistent=`"1`" useLetter=`"1`" letter=`"$($m[0])`"/><Filters><FilterGroup bool=`"AND`" not=`"0`" name=`"HALDEN\$($m[2])`" sid=`"$((Get-ADGroup $m[2]).SID.Value)`" userContext=`"1`" primaryGroup=`"0`" localGroup=`"0`"/></Filters></Drive>" }
$x += '</Drives>'
$dir = "$sysvol\{$($g.Id)}\User\Preferences\Drives"; New-Item -ItemType Directory -Force $dir | Out-Null
Set-Content "$dir\Drives.xml" $x -Encoding UTF8
Add-Ext $g 'User' '5794DAFD-BE60-433F-88A2-1A31939AC01F' '2EA1A81B-48E5-45E9-8BB7-A6E3AC170006'
Link $g "OU=Workstations,OU=Computers,$h"
# 3 / 4 placeholders (P4 imports the baseline, P5 configures update rings)
foreach ($n in 'WKS - Security Baseline - v1','WKS - Windows Update - v1') { Link (Get-OrNewGpo $n) "OU=Workstations,OU=Computers,$h" }
# 5 Desktop standards: 10-minute secured screen saver (user side)
$g = Get-OrNewGpo 'USR - Desktop Standards - v1'
$k = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
Set-GPRegistryValue $g -Key $k -ValueName ScreenSaveActive -Type String -Value '1' | Out-Null
Set-GPRegistryValue $g -Key $k -ValueName ScreenSaveTimeOut -Type String -Value '600' | Out-Null
Set-GPRegistryValue $g -Key $k -ValueName ScreenSaverIsSecure -Type String -Value '1' | Out-Null
Link $g "OU=Users,$h"
# 5b Kiosk lockdown: block Control Panel for anyone on a kiosk (loopback replace)
$g = Get-OrNewGpo 'WKS - Kiosk Lockdown - v1'
Set-GPRegistryValue $g -Key 'HKLM\Software\Policies\Microsoft\Windows\System' -ValueName UserPolicyMode -Type DWord -Value 2 | Out-Null
Set-GPRegistryValue $g -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -ValueName NoControlPanel -Type DWord -Value 1 | Out-Null
Link $g "OU=Kiosks,OU=Computers,$h"
# 6 Servers: WinRM on, restricted to the lab server subnet (P6 narrows to MGMT)
$g = Get-OrNewGpo 'SRV - Remote Management - v1'
$k = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
Set-GPRegistryValue $g -Key $k -ValueName AllowAutoConfig -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue $g -Key $k -ValueName IPv4Filter -Type String -Value '192.168.10.*' | Out-Null
Link $g "OU=Servers,$h"
New-Item -ItemType Directory -Force $BackupPath | Out-Null
Backup-GPO -All -Path $BackupPath | Out-Null
Get-GPO -All | Select-Object DisplayName,GpoStatus | Format-Table

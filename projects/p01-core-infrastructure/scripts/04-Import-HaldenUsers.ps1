<#
.SYNOPSIS  Phase 4b: import the SYNTHETIC staff CSV into AD. Idempotent; logs every action.
.DESCRIPTION Initial passwords are random, forced to change at next logon, and written ONLY to
  logs\initial-passwords-*.csv (git-ignored). Audit log: logs\import-YYYYMMDD.csv. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Csv="$PSScriptRoot\..\data\halden-staff.csv", [string]$LogDir="$PSScriptRoot\..\logs", [string]$Domain='ad.halden.internal')
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
New-Item -ItemType Directory -Force $LogDir | Out-Null
$stamp = Get-Date -f yyyyMMdd; $log = @(); $pw = @()
$root = (Get-ADDomain).DistinguishedName; $upn = $Domain
function New-RandomPassword { $c='abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%+='.ToCharArray(); $b=New-Object byte[] 18
  [Security.Cryptography.RandomNumberGenerator]::Fill($b); -join ($b | ForEach-Object { $c[$_ % $c.Length] }) }
$rows = Import-Csv $Csv
foreach ($r in $rows) {
  $sam = "$($r.First).$($r.Last)".ToLower(); $ou = "OU=$($r.Department),OU=Users,OU=Halden,$root"
  if (Get-ADUser -Filter "SamAccountName -eq '$sam'") { $log += [pscustomobject]@{Time=Get-Date;User=$sam;Action='exists-skip'}; continue }
  $p = New-RandomPassword
  if ($PSCmdlet.ShouldProcess($sam,'Create user')) {
    New-ADUser -Name "$($r.First) $($r.Last)" -GivenName $r.First -Surname $r.Last -SamAccountName $sam -UserPrincipalName "$sam@$upn" `
      -Path $ou -Department $r.Department -Title $r.Title -Office $r.Office -EmployeeID $r.EmployeeID `
      -AccountPassword (ConvertTo-SecureString $p -AsPlainText -Force) -ChangePasswordAtLogon $true -Enabled $true
    $grp = if ($r.Department -eq 'Management') { 'G_Management' } else { "G_$($r.Department)_Staff" }
    Add-ADGroupMember $grp -Members $sam; Add-ADGroupMember G_AllStaff -Members $sam
    if ($r.Department -eq 'IT' -and $r.Title -match 'Systems') { Add-ADGroupMember G_IT_LinuxAdmins -Members $sam }
    $pw  += [pscustomobject]@{User=$sam;InitialPassword=$p}
    $log += [pscustomobject]@{Time=Get-Date;User=$sam;Action='created'}
  }
}
foreach ($r in $rows | Where-Object Manager) {   # second pass: managers (all users now exist)
  $sam = "$($r.First).$($r.Last)".ToLower()
  if ($PSCmdlet.ShouldProcess($sam,'Set manager')) { Set-ADUser $sam -Manager $r.Manager -ErrorAction SilentlyContinue } }
$log | Export-Csv "$LogDir\import-$stamp.csv" -NoTypeInformation -Append
if ($pw) { $pw | Export-Csv "$LogDir\initial-passwords-$stamp.csv" -NoTypeInformation -Append }
"{0} created, {1} skipped" -f ($log|Where-Object Action -eq created).Count, ($log|Where-Object Action -eq 'exists-skip').Count

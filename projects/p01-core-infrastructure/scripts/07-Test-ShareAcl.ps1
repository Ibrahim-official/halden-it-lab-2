<#
.SYNOPSIS  Audit: flag any ACE on share roots that is not a DL_ group, SYSTEM, Administrators or CREATOR OWNER.
.DESCRIPTION Read-only. Exit code = number of violations (target 0). Writes a CSV report for evidence.
#>
[CmdletBinding()]
param([string]$Base='C:\Shares', [string]$Report="$PSScriptRoot\..\evidence\raw\p01-ph5-acl-audit-result.csv")
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
$ok = '^(NT AUTHORITY\\SYSTEM|BUILTIN\\Administrators|CREATOR OWNER|[^\\]+\\DL_.+)$'
$rows = foreach ($d in Get-ChildItem $Base -Directory -Force | Where-Object Name -ne '_DfsRoot') {
  foreach ($a in (Get-Acl $d.FullName).Access) {
    [pscustomobject]@{ Path=$d.FullName; Identity=$a.IdentityReference.Value; Rights=$a.FileSystemRights; Violation=($a.IdentityReference.Value -notmatch $ok) } } }
New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
$rows | Export-Csv $Report -NoTypeInformation
$v = @($rows | Where-Object Violation).Count
"{0} ACEs checked, {1} violations" -f @($rows).Count, $v
exit $v

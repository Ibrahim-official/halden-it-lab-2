<#
.SYNOPSIS
  Phase 5: export Halden infrastructure configuration to Git for config-as-code.
.DESCRIPTION
  Runs nightly (Task Scheduler) on DC01 and writes a versioned snapshot of the
  domain configuration into a Git working copy: GPO backups and XML reports, the
  AD structure (OUs, groups, privileged-group membership), DHCP server config,
  DNS zones and the NPS export. The Linux/OPNsense half is scripts/07-export-configs.sh.
  If anything changed, the script commits with 'nightly: <date>' and, when
  HALDEN_ALERT_WEBHOOK is set in the environment, posts a short summary.
  Secrets: NPS is exported with exportPSK=NO; the DHCP export excludes leases.
  Never commit an export that still contains a secret (see configs/halden-config-sources.json).
.PARAMETER RepoPath
  Path to the local clone of the private halden-configs Git repository.
.PARAMETER Subset
  Which sources to export: All (default), GPO, AD, DHCP, DNS, NPS.
.PARAMETER Domain
  Expected AD DNS root; the lab guard aborts if it does not match.
.EXAMPLE
  .\06-Export-HaldenConfigs.ps1 -RepoPath C:\halden-configs -Subset All
.NOTES
  Read-only against the domain. Snapshot not required. Modes: run on DC01 (GPO/AD/
  DHCP/DNS/NPS). Rollback: `git revert` the commit; re-applying an old config is a
  change in its own right and needs a change record.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$RepoPath = 'C:\halden-configs',
  [ValidateSet('All', 'GPO', 'AD', 'DHCP', 'DNS', 'NPS')][string]$Subset = 'All',
  [string]$Domain = 'ad.halden.internal'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Start-Transcript -Path "$PSScriptRoot\..\logs\p09-config-export-$(Get-Date -f yyyyMMdd).log" -Append -ErrorAction SilentlyContinue

function Assert-Lab {
  if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
}
function Want([string]$Name) { return $Subset -eq 'All' -or $Subset -eq $Name }
function Ensure-Dir([string]$Path) { New-Item -ItemType Directory -Force $Path | Out-Null }

function Export-Gpo {
  $dir = Join-Path $RepoPath 'gpo'; Ensure-Dir $dir
  if ($PSCmdlet.ShouldProcess($dir, 'Backup-GPO + Get-GPOReport')) {
    Backup-GPO -All -Path (Join-Path $dir 'backup') | Out-Null
    Get-GPOReport -All -ReportType Xml -Path (Join-Path $dir 'gpo-report.xml')
  }
}
function Export-Ad {
  $dir = Join-Path $RepoPath 'ad'; Ensure-Dir $dir
  Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName |
    Export-Csv (Join-Path $dir 'ous.csv') -NoTypeInformation
  Get-ADGroup -Filter * -Properties Members | ForEach-Object {
    [pscustomobject]@{ Group = $_.SamAccountName; Members = ($_.Members -join ';') }
  } | Export-Csv (Join-Path $dir 'groups.csv') -NoTypeInformation
  foreach ($g in 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators') {
    Get-ADGroupMember $g -ErrorAction SilentlyContinue |
      Select-Object @{n = 'Group'; e = { $g }}, Name, SamAccountName |
      Export-Csv (Join-Path $dir "privileged-$g.csv") -NoTypeInformation
  }
}
function Export-Dhcp {
  $dir = Join-Path $RepoPath 'dhcp'; Ensure-Dir $dir
  if ($PSCmdlet.ShouldProcess($dir, 'Export-DhcpServer (no leases)')) {
    Export-DhcpServer -File (Join-Path $dir 'dhcp.xml') -Leases:$false -Force
  }
}
function Export-Dns {
  $dir = Join-Path $RepoPath 'dns'; Ensure-Dir $dir
  foreach ($z in (Get-DnsServerZone | Where-Object { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' })) {
    $out = Join-Path $dir "$($z.ZoneName).txt"
    Get-DnsServerResourceRecord -ZoneName $z.ZoneName -ErrorAction SilentlyContinue |
      Out-File $out
  }
}
function Export-Nps {
  $dir = Join-Path $RepoPath 'nps'; Ensure-Dir $dir
  if (Get-WindowsFeature NPAS -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($dir, 'netsh nps export (exportPSK=NO)')) {
      netsh nps export filename=(Join-Path $dir 'nps-export.xml') exportPSK=NO | Out-Null
    }
  } else { Write-Warning 'NPS is not installed on this host (arrives in P6); skipped.' }
}

Assert-Lab
Ensure-Dir $RepoPath
if (Want 'GPO') { Export-Gpo }
if (Want 'AD') { Export-Ad }
if (Want 'DHCP') { Export-Dhcp }
if (Want 'DNS') { Export-Dns }
if (Want 'NPS') { Export-Nps }

if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
  Write-Warning "$RepoPath is not a Git repository. Exports were written but not committed."
  Stop-Transcript -ErrorAction SilentlyContinue
  return
}

$changed = @(git -C $RepoPath status --porcelain)
if ($changed.Count -gt 0) {
  if ($PSCmdlet.ShouldProcess($RepoPath, 'git add + commit')) {
    git -C $RepoPath add -A | Out-Null
    git -C $RepoPath commit -m "nightly: $(Get-Date -f yyyy-MM-dd)" | Out-Null
  }
  Write-Warning ("Config drift: {0} file(s) changed. Review: git -C {1} show --stat" -f $changed.Count, $RepoPath)
  if ($env:HALDEN_ALERT_WEBHOOK) {
    $body = @{ text = "halden-configs changed $($changed.Count) file(s):`n$($changed -join "`n")" } | ConvertTo-Json
    try { Invoke-RestMethod -Uri $env:HALDEN_ALERT_WEBHOOK -Method Post -Body $body -ContentType 'application/json' } catch { Write-Warning "Alert webhook failed: $($_.Exception.Message)" }
  }
} else {
  Write-Host 'No configuration changes since the last export.'
}
Stop-Transcript -ErrorAction SilentlyContinue

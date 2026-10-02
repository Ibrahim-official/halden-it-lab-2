<#
.SYNOPSIS
  P6 Phase 1: create the USERS-HQ (192.168.30.0/24) and WAREHOUSE (192.168.20.0/24) DHCP scopes
  on the existing Windows DHCP failover pair (DC01 + DC02) and add them to HQ-Failover.

.DESCRIPTION
  Run on DC01 as Domain Admin. The relay that forwards the broadcast from VLAN 30 (and VLAN 20,
  via FW02) to these servers runs on FW01 - see scripts/01-Apply-OpnSenseNetworks.sh.

  Idempotent: existing scopes and failover relationships are detected and skipped, not recreated.
  Supports -WhatIf. Snapshots: snap-p6-ph1-before on both DCs.

  Target addresses come from configs/p06-dhcp-scope-plan.csv; nothing is hard-coded.

.PARAMETER ScopePlanCsv
  Path to the scope plan CSV. Defaults to ..\configs\p06-dhcp-scope-plan.csv.

.PARAMETER Domain
  AD DNS root used by the lab guard.

.EXAMPLE
  .\02-Set-WindowsDhcpScopes.ps1 -WhatIf
  .\02-Set-WindowsDhcpScopes.ps1

.NOTES
  Lab only (AGENTS.md R1). The guard aborts outside ad.halden.internal. No secrets are taken on the
  command line; the failover shared secret, if a new relationship had to be created, is prompted for
  and read from the owner's password manager.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ScopePlanCsv = (Join-Path $PSScriptRoot '..\configs\p06-dhcp-scope-plan.csv'),
  [string]$Domain = 'ad.halden.internal',
  [string]$FailoverName = 'HQ-Failover'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Halden lab guard (AGENTS.md Section 2) -----------------------------------------------------
if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }
if (-not (Get-Module -ListAvailable DhcpServer)) {
  Import-Module DhcpServer -ErrorAction Stop
}

$log = Join-Path $PSScriptRoot '..\evidence\raw\p06-ph1-dhcp-scopes-log.csv'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
$results = [System.Collections.Generic.List[object]]::new()

function Write-Result {
  param([string]$Scope, [string]$Action, [string]$Detail)
  $row = [pscustomobject]@{ Time = (Get-Date -Format s); Scope = $Scope; Action = $Action; Detail = $Detail }
  $results.Add($row)
  Write-Information ("{0,-22} {1,-10} {2}" -f $Scope, $Action, $Detail) -InformationAction Continue
}

# --- Failover relationship (must already exist from P1) -----------------------------------------
$failover = Get-DhcpServerv4Failover -Name $FailoverName -ErrorAction SilentlyContinue
if (-not $failover) {
  throw "DHCP failover relationship '$FailoverName' was not found. P1 must be complete before P6."
}
Write-Result -Scope $FailoverName -Action 'check' -Detail ("state={0} mode={1}" -f $failover.State, $failover.Mode)

# --- Read the scope plan ------------------------------------------------------------------------
if (-not (Test-Path $ScopePlanCsv)) { throw "Scope plan not found: $ScopePlanCsv" }
$plan = Import-Csv -Path $ScopePlanCsv | Where-Object { $_.scope_name -and -not $_.scope_name.StartsWith('#') }
if (-not $plan) { throw "No usable rows in $ScopePlanCsv" }

foreach ($s in $plan) {
  $subnet = [string]$s.subnet
  $scopeId = ($subnet -split '/')[0]
  $maskText = $s.subnet.Split('/')[1]
  $mask = switch ($maskText) { '24' { '255.255.255.0' } default { throw "Unsupported prefix /$maskText in the scope plan." } }

  $existing = Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Result -Scope $s.scope_name -Action 'skip' -Detail 'scope already exists (idempotent)'
  }
  elseif ($PSCmdlet.ShouldProcess($s.scope_name, 'Create DHCP scope')) {
    $lease = [TimeSpan]::Parse($s.lease)
    Add-DhcpServerv4Scope -Name $s.scope_name -StartRange $s.start_range -EndRange $s.end_range `
      -SubnetMask $mask -LeaseDuration $lease -State Active
    Write-Result -Scope $s.scope_name -Action 'created' -Detail ("$($s.start_range)-$($s.end_range) lease $($s.lease)")
  }

  if ($PSCmdlet.ShouldProcess($s.scope_name, 'Set scope options 003/006/015')) {
    $dns = @($s.option006_dns -split '\s+' | Where-Object { $_ })
    Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $s.option003_router -DnsServer $dns -DnsDomain $s.option015_domain
    Write-Result -Scope $s.scope_name -Action 'options' -Detail ("router={0} dns={1} domain={2}" -f $s.option003_router, ($dns -join ','), $s.option015_domain)
  }

  # Add the scope to the existing failover relationship (idempotent: it is skipped if already there).
  $failoverScopes = @($failover.ScopeId)
  $already = ($failoverScopes -contains $scopeId) -or (((@($failoverScopes) -join ',')) -match [regex]::Escape($scopeId))
  if ($already) {
    Write-Result -Scope $s.scope_name -Action 'skip' -Detail 'already in the failover relationship'
  }
  elseif ($PSCmdlet.ShouldProcess($s.scope_name, "Add to $FailoverName")) {
    Add-DhcpServerv4FailoverScope -Name $FailoverName -ScopeId $scopeId
    Write-Result -Scope $s.scope_name -Action 'failover' -Detail "added to $FailoverName"
  }
}

# --- Name protection and dynamic DNS, inherited from the P1 design -------------------------------
foreach ($s in $plan) {
  $scopeId = (([string]$s.subnet) -split '/')[0]
  if ($PSCmdlet.ShouldProcess($s.scope_name, 'Set dynamic DNS and name protection')) {
    Set-DhcpServerv4DnsSetting -ScopeId $scopeId -DynamicUpdates Always -DeleteDnsRROnLeaseExpiry $true -NameProtection $true
  }
}

$results | Export-Csv -Path $log -NoTypeInformation

# --- Verification snapshot (paste into docs/as-built.md after the lab run) -----------------------
Write-Information "`n--- Current state ---" -InformationAction Continue
Get-DhcpServerv4Scope | Select-Object ScopeId, Name, StartRange, EndRange, State | Format-Table -AutoSize |
  Out-String | Write-Information -InformationAction Continue
Get-DhcpServerv4Failover | Select-Object Name, State, Mode, ScopeId | Format-List |
  Out-String | Write-Information -InformationAction Continue

Write-Information "Log written to $log. Next: AD Sites and Services subnets (00-design.md section 8), then interfaces and rules on FW01." -InformationAction Continue

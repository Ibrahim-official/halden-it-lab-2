<#
.SYNOPSIS  Phase 8: dump real as-built facts (read-only) to Markdown so docs/as-built.md is generated, not typed.
.DESCRIPTION Run on DC01. Output: evidence\raw\p01-as-built-facts.md - copy sanitized content into docs/as-built.md.
#>
[CmdletBinding()]
param([string]$Out="$PSScriptRoot\..\evidence\raw\p01-as-built-facts.md")
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
function Md($t,$o) { "`n## $t`n"; '```'; ($o | Out-String).Trim(); '```' }
& {
 Md 'Domain controllers' (Get-ADDomainController -Filter * | Select-Object Name,IPv4Address,Site,IsGlobalCatalog,OperatingSystem,@{n='FSMO';e={$_.OperationMasterRoles -join ','}})
 Md 'Replication summary' (repadmin /replsummary)
 Md 'DNS zones' (Get-DnsServerZone | Select-Object ZoneName,ZoneType,IsDsIntegrated)
 Md 'DNS forwarders / scavenging' ((Get-DnsServerForwarder),(Get-DnsServerScavenging))
 Md 'DHCP scope / failover' ((Get-DhcpServerv4Scope),(Get-DhcpServerv4Failover))
 Md 'GPOs' (Get-GPO -All | Select-Object DisplayName,GpoStatus,ModificationTime)
 Md 'Users per OU' (Get-ADUser -Filter * -SearchBase "OU=Users,OU=Halden,$((Get-ADDomain).DistinguishedName)" | Group-Object { ($_.DistinguishedName -split ',')[1] } | Select-Object Name,Count)
 Md 'DFS folders' (Get-DfsnFolder "\\ad.halden.internal\Company\*" | Select-Object Path)
} | Set-Content $Out -Encoding UTF8
"Wrote $Out"

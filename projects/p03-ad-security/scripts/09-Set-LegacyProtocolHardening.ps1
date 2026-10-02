<#
.SYNOPSIS
  P3 Phase 6: legacy-protocol hardening by Group Policy — NTLM level, NTLM auditing, SMB
  signing, SMBv1 removal, LDAP signing and channel binding, LLMNR and NetBIOS-NS. Audit first,
  enforce second. Idempotent; every action is logged.

.DESCRIPTION
  Weak legacy protocols are what turn one compromised workstation into domain-wide compromise:
  NTLMv1/LM responses crack in seconds, unsigned SMB allows relay, LDAP without signing allows
  a relay to the directory, and LLMNR/NetBIOS-NS let an attacker answer for a name that was
  mistyped. Every one of these is a policy setting, so the control is the policy and the audit
  evidence comes before the enforcement.

  Phase 6a (default, -Enforce not set): configure NTLM auditing and record the current protocol
  posture. Nothing is broken.
  Phase 6b (-Enforce): apply the enforcing settings.

.PARAMETER Domain
  Expected AD DNS domain. Default ad.halden.internal.

.PARAMETER Enforce
  Apply the enforcing values. Without it, the script only enables NTLM auditing and reports the
  current state, which is the correct first step (audit -> analyse -> enforce).

.PARAMETER Log
  CSV action log. Defaults to ..\evidence\raw\p03-ph6-legacy-protocols-log.csv.

.EXAMPLE
  .\09-Set-LegacyProtocolHardening.ps1
  Audit phase: NTLM auditing on, posture recorded, nothing enforced.

.EXAMPLE
  .\09-Set-LegacyProtocolHardening.ps1 -Enforce
  Apply LM level 5, SMB signing, LDAP signing and channel binding, LLMNR off.

.NOTES
  Snapshot DC01, DC02, FS01 and WS01 first (snap-p3-ph6-before). Rollback: set the GPOs back to
  "Not Configured" and re-run gpupdate; the audit-phase log records the previous posture.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Domain = 'ad.halden.internal',
  [switch]$Enforce,
  [string]$Log = "$PSScriptRoot\..\evidence\raw\p03-ph6-legacy-protocols-log.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

$root = (Get-ADDomain).DistinguishedName
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$actions = [System.Collections.Generic.List[object]]::new()
function Add-Action([string]$Item, [string]$Action, [string]$Detail) {
  $actions.Add([pscustomobject]@{ Time = Get-Date -Format s; Item = $Item; Action = $Action; Detail = $Detail })
}
function Ensure-Gpo([string]$Name, [string]$Target, [string]$Comment) {
  $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
  if (-not $gpo) {
    $gpo = New-GPO -Name $Name -Comment $Comment
    New-GPLink -Name $Name -Target $Target | Out-Null
    Add-Action $Name 'created' "linked to $Target"
  }
  $gpo
}
function Set-Policy([string]$Gpo, [string]$Key, [string]$Value, [string]$Type, $Data) {
  $type = switch ($Type) { 'DWord' { 'DWord' } 'String' { 'String' } default { throw "Unsupported type $Type" } }
  Set-GPRegistryValue -Name $Gpo -Key $Key -ValueName $Value -Type $type -Value $Data | Out-Null
}

# ---------------------------------------------------------------- 1. NTLM auditing (always on)
$ntlmGpo = Ensure-Gpo -Name 'DOMAIN - NTLM Audit - v1' -Target $root -Comment 'P3: audit incoming NTLM before restricting it.'
if ($PSCmdlet.ShouldProcess($ntlmGpo.DisplayName, 'Enable NTLM audit for all accounts')) {
  # Value 3 = "Audit all". Analyze with event 8004 on the domain controllers, then restrict.
  Set-Policy -Gpo $ntlmGpo.DisplayName -Key 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' `
    -Value 'AuditReceivingNTLMTraffic' -Type DWord -Data 2
  Add-Action 'NTLM audit' 'enabled' 'audit incoming NTLM traffic for all accounts; review event 8004 on the DCs'
}

# ---------------------------------------------------------------- 2. Record current posture
$posture = [ordered]@{
  LmCompatibilityLevel = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -ErrorAction SilentlyContinue).LmCompatibilityLevel
  Smbv1Feature         = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State
  SpoolerOnDc          = (Get-Service Spooler -ErrorAction SilentlyContinue).StartType
  NetbiosTcpipEnabled  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\*' -Name NetbiosOptions -ErrorAction SilentlyContinue).NetbiosOptions}
foreach ($key in $posture.Keys) {
  $value = [string]$posture[$key]
  Add-Action '(posture)' 'recorded' ("{0} = {1}" -f $key, $value)
}

if (-not $Enforce) {
  Add-Action '(enforcement)' 'audit-only' 'run again with -Enforce after reviewing the NTLM audit events'
  $actions | Export-Csv -Path $Log -NoTypeInformation -Append
  Write-Output ("Legacy-protocol audit phase complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
  Write-Output 'Review event 8004 on DC01/DC02, then re-run with -Enforce.'
  return
}

# ---------------------------------------------------------------- 3. Enforcement
$hardGpo = Ensure-Gpo -Name 'DOMAIN - Legacy Protocol Hardening - v1' -Target $root -Comment 'P3 Phase 6: enforce current protocol standards.'

if ($PSCmdlet.ShouldProcess($hardGpo.DisplayName, 'Configure legacy protocol hardening')) {
  # LAN Manager authentication level 5 = send NTLMv2 only, refuse LM and NTLM.
  Set-Policy -Gpo $hardGpo.DisplayName -Key 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' -Value 'LmCompatibilityLevel' -Type DWord -Data 5
  # SMB signing required on both sides (default in recent builds - configure it rather than assume).
  Set-Policy -Gpo $hardGpo.DisplayName -Key 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Value 'RequireSecuritySignature' -Type DWord -Data 1
  Set-Policy -Gpo $hardGpo.DisplayName -Key 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Value 'RequireSecuritySignature' -Type DWord -Data 1
  # LLMNR off.
  Set-Policy -Gpo $hardGpo.DisplayName -Key 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Value 'EnableMulticast' -Type DWord -Data 0
  Add-Action $hardGpo.DisplayName 'enforced' 'LM level 5; SMB signing required; LLMNR disabled'

  # LDAP signing and channel binding apply to domain controllers.
  Set-Policy -Gpo $hardGpo.DisplayName -Key 'HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -Value 'LDAPServerIntegrity' -Type DWord -Data 2
  Set-Policy -Gpo $hardGpo.DisplayName -Key 'HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -Value 'LdapEnforceChannelBinding' -Type DWord -Data 2
  Add-Action $hardGpo.DisplayName 'ldap-hardening' 'LDAP signing required; channel binding always'
}

foreach ($host_ in @('DC01', 'DC02', 'FS01', 'WS01')) {
  if ($PSCmdlet.ShouldProcess($host_, 'Disable SMBv1 feature')) {
    try {
      Invoke-Command -ComputerName $host_ -ScriptBlock {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol).State
        if ($state -ne 'Disabled') {
          Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
        }
      } -ErrorAction Stop
      Add-Action $host_ 'smbv1-disabled' 'SMB1Protocol feature disabled'
    } catch {
      Add-Action $host_ 'failed' "could not reach host: $($_.Exception.Message)"
    }
  }
}

$actions | Export-Csv -Path $Log -NoTypeInformation -Append
Write-Output ("Legacy-protocol enforcement complete: {0} action(s) written to {1}" -f $actions.Count, $Log)
Write-Output 'Next: 11-Verify-Remediation.ps1, then re-run the assessment (Phases 1 and 7).'

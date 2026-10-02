# P7 as-built — Halden Distribution Ltd. monitoring and incident response

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md), written so the *measured* facts can be pasted
> straight in. Nothing here is presented as a captured result: the **Verified ☐** column stays empty
> until the matching script has actually run in the lab.
>
> **How to finish this document:** run the phase scripts, capture the output, sanitize it
> (AGENTS.md 4.6) and paste the real values below, replacing *(designed)* with *(verified)*.
> Evidence files go in `evidence/public/` named `p07-ph<N>-<what>-<result>.<ext>`.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| SIEM host | SIEM01, Ubuntu Server 24.04, 192.168.10.41, VLAN 10 | ☐ |
| Stack | Wazuh 4.x all-in-one (manager + indexer + dashboard) via Docker Compose | ☐ |
| SIEM01 RAM | 6 GB (minimum 4 GB, smooth 8 GB) | ☐ |
| Domain | `ad.halden.internal` | ☐ |
| Availability monitor | Uptime Kuma on OPS01 (installed in P9) | ☐ |
| Dashboard exposure | MGMT/lab network only — never the internet | ☐ |

## 2. Log sources and agents *(designed)*

| Host | Agent group | Sources | Verified |
|---|---|---|---|
| DC01 | windows-servers | Security, System, Sysmon, PowerShell, Defender, Firewall; FIM on SYSVOL Policies | ☐ |
| DC02 | windows-servers | Same as DC01 | ☐ |
| FS01 | windows-servers | Same as DC01 | ☐ |
| WS01 | windows-workstations | Security, Sysmon, PowerShell, Defender | ☐ |
| WS02 | windows-workstations | Same as WS01 | ☐ |
| LNX01 | linux-servers | auth.log, syslog, auditd; FIM on /etc/sudoers.d, /etc/ssh | ☐ |
| OPS01 | linux-servers | auth.log, syslog, auditd | ☐ |
| BKP01 | linux-servers | syslog (backup job), auditd (key auth, not domain-joined) | ☐ |
| SIEM01 | linux-servers | Wazuh internal events | ☐ |
| FW01, FW02 | syslog (not an agent) | filterlog, OpenVPN, WireGuard over UDP 514 | ☐ |

Agents reporting (all Active) — to be verified: ☐

## 3. Windows audit policy and endpoint telemetry *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Audit subcategories | Per `configs/windows-audit-policy.csv` (`scripts/05`) | ☐ |
| Command-line process auditing | Enabled (`ProcessCreationIncludeCmdLine_Enabled=1`) | ☐ |
| PowerShell script-block logging (4104) | Enabled | ☐ |
| Security log size | 1 GB servers / 512 MB workstations | ☐ |
| Sysmon | Halden config (`configs/sysmonconfig-halden.xml`), all Windows hosts | ☐ |
| Sysmon config update | `sysmon64 -c` when the config hash changes | ☐ |

## 4. Custom detections *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Rules file | `/var/ossec/etc/rules/local_rules.xml`, IDs 100100-100116 | ☐ |
| Rule count | 16 (14 mapped to ATT&CK, 2 availability) | ☐ |
| ATT&CK techniques covered | 14 | ☐ |
| Rules tested with `wazuh-logtest` | Each rule against a captured sample | ☐ |
| Rules validated by simulation | *(empty — filled from the approved run)* | ☐ |

Per-rule validation state is tracked in `configs/detection-coverage-matrix.csv`
(`validated` and `time_to_alert_s` columns are empty until measured).

## 5. Availability monitoring *(designed)*

| Monitor | Target | Type | Verified |
|---|---|---|---|
| DNS resolution | DC01/DC02 SRV for ad.halden.internal | DNS | ☐ |
| LDAP | DC01, DC02 (389/636) | TCP | ☐ |
| File share | FS01 (445) | TCP | ☐ |
| Web apps | GLPI, BookStack, Wazuh dashboard | HTTPS keyword | ☐ |
| VPN endpoint | FW01 | TCP | ☐ |
| Backups | P8 backup job push heartbeat (absence = failure) | Push | ☐ |
| Disk space | Host script, alarm at 85% | Push | ☐ |
| Status page | Published for staff | — | ☐ |

## 6. Incident response capability *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| IR plan | `business/p07-ir-plan.md` (NIST SP 800-61r3 / CSF 2.0 aligned) | ☐ |
| Playbooks | 5: suspicious logon, ransomware, privileged group change, account compromise, lost laptop | ☐ |
| Severity matrix | SEV1/SEV2/SEV3 per `configs/alert-severity-triage.csv` | ☐ |
| On-call/escalation | `configs/escalation-oncall-matrix.csv` | ☐ |
| Lab incident worked end-to-end | *(not run yet)* | ☐ |
| Tabletop exercise | *(not run yet — outcomes section empty)* | ☐ |
| Tracked improvement actions | *(empty until the tabletop runs)* | ☐ |

## 7. Noise tuning *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Tuning method | Narrow exceptions (process+path+host), never disabling a rule | ☐ |
| Tuning log | `docs/tuning-log.md` | ☐ |
| Alerts/day before tuning | *(not measured)* | ☐ |
| Alerts/day after tuning | *(not measured)* | ☐ |
| High+ alerts that were true positives | *(not measured)* | ☐ |

## 8. Known gaps and exceptions

| Item | Note |
|---|---|
| No 24×7 staffing in the lab | Response targets describe the design, not a staffed rota |
| 90-day hot retention | Covers the "found out weeks later" case; longer retention is out of scope for a 16 GB host |
| Base SIDs vary by Wazuh version | Rules are verified with `wazuh-logtest` before trust |
| Defender may prevent some simulations | Recorded as "prevented", separately from "detected" |
| Mapped ≠ validated | The heat map shows mapped coverage; validation is a separate, measured result |
| Active response risk | An IP allow-list protects management access; short timeouts limit the chance of self-lockout |

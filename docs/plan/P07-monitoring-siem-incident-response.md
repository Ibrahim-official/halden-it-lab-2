# P7: Security Monitoring, SIEM and Incident Response

> **Pitch:** Built centralized monitoring for the whole environment: Wazuh SIEM with Sysmon and Windows audit policy tuned to MITRE ATT&CK, custom detections for AD attacks, Uptime Kuma availability monitoring with alert routing, and a tested incident response capability (playbooks, severity matrix, and a management tabletop exercise). Detections were validated with Atomic Red Team: **N/N simulated techniques detected**, mean time to alert **X seconds**.

**Anchor score:** 94 (merged with #29 availability monitoring, #30 IR playbooks + tabletop) · **Time:** about 2 weeks · **Depends on:** P1–P6

---

## 1. Business problem

At Halden, nobody would notice an attacker until the ransom note appeared. Logs sit on each machine and get overwritten within days. When the file server filled up last month, users reported it before IT knew. There's no incident process: "who do we call?" was answered on WhatsApp.

**Market evidence:** ransomware is present in 88% of SMB breaches (Verizon DBIR 2025), and attackers typically spend days escalating privilege before they encrypt. That's the window in which detection pays off. The job ad asks directly for monitoring of "system health, availability, logs, alerts, and security events" and the ability to "identify and respond to security incidents".

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | **Monitor system health, availability, logs, alerts, and security events** |
| SysAdmin | **Identify and respond to security incidents** and unauthorized access |
| SysAdmin | Provide technical support and **escalation** assistance |
| SysAdmin | Coordinate with vendors/service providers (IR contacts, insurer) |
| Officer | Communicate issues to management; coordinate teams; follow up on action items (tabletop actions) |

## 3. Success criteria

- [ ] Wazuh agents on **100% of servers and workstations** + syslog from OPNsense (FW01/FW02)
- [ ] Sysmon (community config) on all Windows hosts; **Advanced Audit Policy** per Microsoft recommendations via GPO
- [ ] **≥10 custom/tuned detections** mapped to MITRE ATT&CK, each with a runbook
- [ ] Atomic Red Team validation: **detection coverage table** (technique → expected alert → detected Y/N → time to alert)
- [ ] Availability monitoring for all critical services with alerts to email/Teams/Telegram and a **status page**
- [ ] IR plan + 5 playbooks + severity matrix + contact tree; **one tabletop exercise** run with a report and tracked actions
- [ ] Alert noise tuned: false-positive rate documented before and after

## 4. Architecture

```
 Windows (DCs, FS01, WS01/02): Wazuh agent + Sysmon + Advanced Audit Policy + PowerShell logging
 Linux (LNX01, OPS01, BKP01): Wazuh agent (auth.log, auditd, FIM)
 OPNsense FW01/FW02: syslog → Wazuh (filterlog, OpenVPN, WireGuard)
 Entra ID sign-in logs (optional, M365 trial): Wazuh Office365/Graph module
                       │
                       ▼
            SIEM01: Wazuh manager + indexer + dashboard (8 GB RAM)
            ├─ Custom rules (local_rules.xml) mapped to ATT&CK
            ├─ Active response (e.g. block IP on repeated SSH fail)
            └─ Integrations → email / Teams / Telegram webhook
 OPS01: Uptime Kuma → HTTP/TCP/DNS/ping checks → alerts + public status page
```

## 5. Tools and cost

[Wazuh](https://wazuh.com) 4.x (all-in-one) · [Sysmon](https://learn.microsoft.com/sysinternals/downloads/sysmon) + [SwiftOnSecurity](https://github.com/SwiftOnSecurity/sysmon-config) or [Olaf Hartong sysmon-modular](https://github.com/olafhartong/sysmon-modular) config · [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) + Invoke-AtomicRedTeam · [Uptime Kuma](https://github.com/louislam/uptime-kuma) · MITRE ATT&CK Navigator. **Cost: free.**

> ⚠️ Run Atomic Red Team **only on lab machines you own**, snapshot first, and state that in the README.

## 6. Step-by-step action plan

### Phase 0: Decide what to watch (Day 1)
Log sources **by priority**, with a justification for each. Use-case driven, not "collect everything":
| Priority | Source | Why |
|---|---|---|
| 1 | DC Security logs (4624/4625/4672/4720/4728/4732/4740/4756/4768/4769/4771) | Identity is the #1 attack vector |
| 1 | Sysmon on all Windows (process create 1, network 3, image load 7, LSASS access 10, file create 11, registry 13, DNS 22) | Endpoint behaviour |
| 1 | PowerShell 4104 script block logs | Living-off-the-land |
| 2 | Firewall + VPN logs | Perimeter and remote-access abuse |
| 2 | Linux auth/auditd | SSH brute force, sudo misuse |
| 3 | Entra ID sign-ins | Cloud identity, break-glass use |

Also define the **alert routing** now: Critical → phone push (Telegram/Teams) 24×7; High → email + ticket (P9); Medium/Low → daily digest.

### Phase 1: Deploy Wazuh and Windows telemetry (Day 2–4)
1. SIEM01 (Ubuntu 24.04, 8 GB RAM, 4 vCPU, 100 GB): `curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh && sudo bash ./wazuh-install.sh -a` (check the docs for the current version). Change the default admin password and restrict dashboard access to the MGMT VLAN (P6 rule).
2. **Agents:** deploy the Windows MSI via GPO startup script or PowerShell (`WAZUH_MANAGER`, `WAZUH_AGENT_GROUP=windows-servers|windows-workstations`). Linux via apt. Use **agent groups** with a shared `agent.conf` per group.
3. **Sysmon:** deploy via a GPO startup script from `\\ad.halden.internal\NETLOGON\sysmon\` (`sysmon64 -accepteula -i sysmonconfig.xml`, with an update check `-c` when the config hash changes).
4. Wazuh `agent.conf` for the Windows group:
   ```xml
   <localfile><location>Microsoft-Windows-Sysmon/Operational</location><log_format>eventchannel</log_format></localfile>
   <localfile><location>Microsoft-Windows-PowerShell/Operational</location><log_format>eventchannel</log_format></localfile>
   <localfile><location>Microsoft-Windows-Windows Defender/Operational</location><log_format>eventchannel</log_format></localfile>
   ```
5. **Advanced Audit Policy GPO** (`DC - Audit Policy - v1`, `WKS - Audit Policy - v1`): enable *Force audit policy subcategory settings*. Turn on Credential Validation, Kerberos Authentication/Service Ticket Operations, Security Group Management, User Account Management, Logon/Logoff, Special Logon, **Process Creation + command line** (`Include command line in process creation events`), Directory Service Changes (DCs), Detailed File Share (FS01, sensitive shares only). Set the Security log size to at least 1 GB on DCs.
6. **OPNsense syslog → Wazuh** (UDP/TCP 514 listener in `ossec.conf` with `<allowed-ips>` for the firewalls only).
7. **FIM (File Integrity Monitoring):** watch `C:\Windows\SYSVOL\domain\Policies` (GPO tampering), `/etc/sudoers.d`, `/etc/ssh`, and the web roots.

### Phase 2: Detections that matter (Day 5–7)
Write custom rules in `/var/ossec/etc/rules/local_rules.xml` (IDs 100000+), each with an **ATT&CK ID**, severity, and a matching runbook in `docs/runbooks/`:

| # | Detection | Data source / logic | ATT&CK |
|---|---|---|---|
| D1 | User added to Domain/Enterprise/Schema Admins | 4728/4732/4756 where group ∈ privileged list | T1098 |
| D2 | Kerberoasting | 4769 with ticket encryption type `0x17` (RC4) for a user SPN (after P3 there should be none, so any hit is suspicious) | T1558.003 |
| D3 | AS-REP roasting | 4768 with pre-auth type 0 | T1558.004 |
| D4 | Password spraying | ≥10 × 4625/4771 from one source to ≥5 accounts in 5 min | T1110.003 |
| D5 | LSASS access | Sysmon 10 TargetImage lsass.exe, GrantedAccess 0x1010/0x1410, excluding known-good | T1003.001 |
| D6 | Encoded / download-cradle PowerShell | 4104 or Sysmon 1 with `-enc`, `FromBase64String`, `IEX`, `DownloadString` | T1059.001 |
| D7 | Shadow copy deletion (ransomware precursor) | Sysmon 1: `vssadmin delete shadows`, `wmic shadowcopy delete`, `wbadmin delete catalog` | T1490 |
| D8 | Security log cleared | 1102 | T1070.001 |
| D9 | New service / scheduled task on server | 7045 / 4698 | T1543.003 / T1053.005 |
| D10 | Break-glass or Tier 0 account logon | 4624 for `adm-t0-*` on a non-DC/non-PAW, or any break-glass sign-in | T1078 |
| D11 | DCSync attempt | 4662 with replication GUIDs from a non-DC account | T1003.006 |
| D12 | VPN logon from an unusual country / off-hours | OPNsense OpenVPN logs + GeoIP | T1133 |

Example rule:
```xml
<group name="halden,windows,attack,">
  <rule id="100110" level="12">
    <if_sid>60103</if_sid>  <!-- base Windows security event; verify SID in your Wazuh version -->
    <field name="win.system.eventID">^4728$|^4732$|^4756$</field>
    <field name="win.eventdata.targetUserName" type="pcre2">(?i)^(Domain Admins|Enterprise Admins|Schema Admins|Administrators)$</field>
    <description>Halden D1: Member added to privileged group $(win.eventdata.targetUserName) by $(win.eventdata.subjectUserName)</description>
    <mitre><id>T1098</id></mitre>
  </rule>
</group>
```
Test every rule with `/var/ossec/bin/wazuh-logtest` using a sample event **before** relying on it.

**Active response (careful):** auto-block a source IP on OPNsense or `firewall-drop` on Linux after SSH brute force (rule 5763), with a timeout. Document the risk of blocking yourself and the allow-list.

### Phase 3: Validate with attack simulation (Day 8–9)
```powershell
# On WS01 (snapshot first!), as a lab admin:
IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
Install-AtomicRedTeam -getAtomics
Invoke-AtomicTest T1003.001 -ShowDetailsBrief      # read what it does first
Invoke-AtomicTest T1059.001 -TestNumbers 1,2
Invoke-AtomicTest T1490 -TestNumbers 1
Invoke-AtomicTest T1136.002                         # create domain account
Invoke-AtomicTest T1003.001 -Cleanup
```
- Defender (P4) will block some of these. **That's a good result.** Record "prevented" and "detected" separately, and use temporary exclusions on one test VM only if you need to test the detection layer (document this and remove them afterwards).
- Build `evidence/p7-detection-coverage.xlsx`: technique · atomic test · expected rule · alert fired? · time to alert · prevented by Defender? · tuning needed.
- Colour an **ATT&CK Navigator layer** with the techniques you cover and export the PNG. It makes a strong portfolio image.

### Phase 4: Tune the noise (Day 10)
- Run for 3–5 days of "normal" lab activity (scripted logons, file access, patching). Count alerts by rule.
- Suppress known-good items with narrow exceptions (specific process + path + host), **never by disabling a rule**. Record each tuning decision in `docs/tuning-log.md`.
- Report: alerts/day before vs after, and the % of High+ alerts that were true positives.

### Phase 5: Availability monitoring (Day 10–11)
Uptime Kuma (docker on OPS01):
| Monitor | Type | Target |
|---|---|---|
| DNS resolution | DNS | `dc01`/`dc02` resolve `ad.halden.internal` SRV |
| LDAP | TCP 389/636 | DC01, DC02 |
| File share | TCP 445 | FS01 |
| Web apps | HTTPS keyword | GLPI (P9), BookStack, Wazuh dashboard |
| VPN endpoint | TCP/UDP | FW01 WAN |
| Backups | **Push monitor** | Backup job calls the push URL on success (P8). **A missing heartbeat means failed backups.** |
| Disk space | Push via script | `Get-Volume` / `df` check < 85% |

- Notifications: Telegram/Teams webhook + email, with escalation (repeat every 30 min until acknowledged).
- **Status page** for staff ("Is it down or just me?"), which also cuts helpdesk tickets (IT Support Officer angle).

### Phase 6: Incident response capability (Day 12–14)
1. `docs/ir/ir-plan.md` (NIST SP 800-61r3 / CSF 2.0 aligned: Govern-Detect-Respond-Recover): roles (Incident Lead, Comms, Technical, Management decision-maker), **severity matrix**, escalation times, evidence handling, external contacts (insurer, legal, data-protection regulator notification deadlines per your jurisdiction (Pakistan: PECA 2016 plus any sector regulator rules, e.g. SBP for banks, and check the status of the Personal Data Protection Bill; EU customers: 72h under GDPR), forensics retainer, police/cyber reporting), and communication templates.

   | Severity | Example | Response | Notify |
   |---|---|---|---|
   | SEV1 | Ransomware executing, DC compromise | Immediate, all hands | MD within 15 min, insurer ASAP |
   | SEV2 | Confirmed account compromise, malware contained on 1 host | < 1 h | IT Manager, dept head |
   | SEV3 | Suspicious activity, policy violation | < 1 business day | IT |
2. **5 playbooks** (1–2 pages each, checklist format): Ransomware · Compromised user account (M365 + AD) · Phishing email reported · Lost/stolen laptop (links to BitLocker P4, LAPS P3) · Privileged group change / suspected AD compromise.
   Each covers: triage questions → containment (e.g. disable account, `Revoke-MgUserSignInSession`, isolate host via Defender/firewall VLAN, block IP) → evidence to preserve → eradication → recovery (link to P8) → lessons learned.
3. **Run one incident end-to-end in the lab:** trigger D1 (a rogue Domain Admin add) + D6. Work the playbook, write an **incident report** with a timeline built from Wazuh events.
4. **Tabletop exercise (IT Support Officer showcase):** a 60-minute scenario ("Friday 16:30, Finance reports files renamed `.locked`"), with injects every 10 minutes (backups also targeted, press enquiry, CEO asks "should we pay?"). Role-play participants (MD, Finance, HR, IT, external MSP). Output:
   - `business/p7-tabletop-report.md`: what went well, gaps, **action items with owners and dates** (tracked in P10)

## 7. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p7-ir-plan-summary.pdf` | 2-page plan for management: severity, who decides what, who to call |
| `business/p7-contact-tree.xlsx` | Internal + vendor/insurer/legal contacts, 24×7 numbers (fictional) |
| `business/p7-tabletop-report.md` | Findings + action tracker |
| `business/p7-monthly-security-summary.md` | Template: alerts by severity, incidents, notable detections, uptime %, feeds P10 |

## 8. Evidence to capture

Wazuh agents list (all active) · custom rule XML + `wazuh-logtest` output · alert screenshots for D1/D2/D5/D7 · ATT&CK Navigator layer · detection coverage table · before/after alert volume chart · Uptime Kuma dashboard + status page + backup push monitor · incident report timeline · tabletop report.

## 9. Common pitfalls

- Sending every log and alerting on everything, which leads to alert fatigue and ignored alerts. Start from use cases.
- Not enabling command-line process auditing or PowerShell 4104. Without them most detections can't see anything.
- Tuning by disabling rules instead of writing narrow exceptions.
- Running attack simulations on a non-snapshotted DC.
- An IR plan nobody has rehearsed. The tabletop is what makes it real.

## 10. Resume bullets (templates)

- Deployed **Wazuh SIEM** with Sysmon, tuned Windows advanced auditing and firewall/VPN syslog across **N endpoints**, and wrote **12 ATT&CK-mapped detections** for AD attacks (Kerberoasting, DCSync, privileged group changes, password spraying, shadow-copy deletion).
- Validated detection coverage with **Atomic Red Team** (**X/Y techniques detected, median time-to-alert Z s**) and cut alert noise by **N%** through documented tuning.
- Wrote an **incident response plan with 5 playbooks** and facilitated a ransomware **tabletop exercise** with management, producing **N tracked improvement actions**. Added Uptime Kuma availability monitoring with backup heartbeat checks and a staff status page.

## 11. Interview talking points

- **"You get an alert: a user was added to Domain Admins at 2am. Walk me through it."** Validate (who, from where, via what tool), check the change log (P10), contain (remove membership, disable the source account, isolate the host), preserve evidence, scope (other changes by that account), escalate per severity, report.
- **"How do you avoid alert fatigue?"** Use-case-driven collection, severity routing, narrow tuning with a log, and measuring the true-positive rate.
- **"How do you know your monitoring works?"** Atomic Red Team coverage table. Detection is tested, not assumed.

## 12. AI-ready build prompt

```text
Act as a senior security operations engineer mentoring me on a homelab capstone.
Project: P7 Security Monitoring, SIEM & Incident Response for fictional "Halden Distribution Ltd".
Lab: ad.halden.internal (DC01, DC02, FS01), WS01/WS02 Win 11 (Defender + ASR from P4), LNX01/OPS01 Ubuntu,
FW01/FW02 OPNsense, new SIEM01 Ubuntu 24.04 (8 GB). Tiering, LAPS, gMSA done in P3; VLANs in P6.

Phase by phase:
0. Use-case-driven log source plan + alert routing matrix.
1. Wazuh all-in-one install, agent groups with agent.conf (Sysmon, PowerShell, Defender channels), Sysmon deployment
   via GPO, Advanced Audit Policy GPOs for DCs and workstations, OPNsense syslog, FIM targets.
2. 12 custom Wazuh rules (D1-D12 list: privileged group add, Kerberoasting RC4 4769, AS-REP, spraying, LSASS access,
   encoded PowerShell, shadow copy deletion, log clearing, new service/task, Tier0/break-glass logon, DCSync 4662,
   VPN anomaly) with ATT&CK IDs; verify base SIDs for my Wazuh version; test each with wazuh-logtest.
3. Atomic Red Team validation plan (safe tests, cleanup, snapshots), coverage table, ATT&CK Navigator layer.
4. Noise tuning method + tuning log.
5. Uptime Kuma monitors incl. push heartbeat for backups and disk space scripts; notifications; status page.
6. IR plan (NIST 800-61r3 / CSF 2.0), severity matrix, 5 playbooks, one lab incident with a timeline report, and a
   60-min ransomware tabletop script with injects + report template.
Give commands, config, expected output, verification and screenshots each phase. Finish with README, metrics
and resume bullets. Start with Phase 0.
```

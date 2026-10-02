# P7 — Phase 0: Design document (what to watch, and why)

**Project:** P7 Security Monitoring, SIEM and Incident Response
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P07-monitoring-siem-incident-response.md`](../../../docs/plan/P07-monitoring-siem-incident-response.md)

> Why design first: monitoring is the project where "collect everything and alert on everything" is
> the default failure mode. It produces an unreadable dashboard, an exhausted analyst and no real
> detection. This document fixes *what* is collected, *why*, and *how an alert becomes an incident*
> before any agent is installed. It is deliberately a design, not a result: measured numbers appear
> only after the lab run (see `as-built.md` and `README.md`).

---

## 1. Goal and scope

Stand up centralised security monitoring and a rehearsed incident response capability for the
Halden lab:

- **SIEM:** Wazuh (manager + indexer + dashboard) on SIEM01, agents on every Windows and Linux
  log source, and syslog from both OPNsense firewalls.
- **Telemetry:** Sysmon and Windows advanced audit policy tuned to the ATT&CK techniques that
  matter here, not the whole matrix.
- **Detections:** 16 custom rules mapped to ATT&CK, each with a runbook.
- **Availability:** Uptime Kuma monitors, including a backup heartbeat where a *missing* signal
  means a failed backup.
- **Incident response:** an IR plan, five playbooks, a severity matrix, one tabletop exercise and
  one end-to-end lab incident with a timeline.
- **Validation:** prove the detections work with an authorised lab simulation, and be honest about
  what did not fire.

Out of scope: an always-on managed SOC, 24×7 staffing, threat-intel subscriptions, a full forensic
platform, and anything outside the lab (AGENTS.md R1). The lab is never exposed to the internet
(AGENTS.md 5.1).

## 2. Business context (why this exists)

At Halden, nobody would notice an attacker until the ransom note appeared. Logs sit on each machine
and overwrite within days. When the file server filled up last month, users reported it before IT
knew. And "who do we call?" had no documented answer.

**Market evidence:** ransomware appears in **88% of SMB breaches** (Verizon DBIR 2025, cited in
`docs/plan/00-research-and-selection.md`), and attackers typically spend days escalating privilege
before they encrypt. That window — between first access and encryption — is exactly what this
project is built to shorten. The job ad asks for monitoring of "system health, availability, logs,
alerts and security events" and for the ability to "identify and respond to security incidents".

**Success = the measurable criteria** in the P7 plan: agents on 100% of hosts, ≥10 custom
detections each with a runbook, a validation coverage table, availability monitoring with a status
page, an IR plan with playbooks and a tabletop, and documented noise before/after.

## 3. Design principles

1. **Use-case driven, not "collect everything".** Each log source exists because a detection or a
   runbook needs it (§5). A source with no use case is not collected.
2. **Behaviour over signatures.** Rules match what an action *does* (a member added to Domain
   Admins, a process reading LSASS, shadow copies being deleted), not a known bad string that an
   attacker changes tooling to avoid.
3. **Every detection has an owner and a runbook.** An alert with no documented response is noise
   with a level attached.
4. **Tune narrowly, never by disabling.** Suppress a specific process+path+host, record the decision
   in `docs/tuning-log.md`; never switch a rule off to quieten the dashboard.
5. **Detection is tested, not assumed.** The coverage matrix's `validated` column is filled only
   from an approved simulation run; until then it is empty.
6. **Honesty is a control.** A rule that did not fire is recorded as not fired. A hypothesis is
   labelled a hypothesis. (AGENTS.md R2.)

## 4. Architecture

```
 Windows (DC01, DC02, FS01, WS01, WS02)              Linux (LNX01, OPS01, BKP01, SIEM01)
  Wazuh agent                                         Wazuh agent
  + Sysmon (Halden config)                            + auth.log, syslog, auditd
  + Advanced Audit Policy                             + FIM: /etc/sudoers.d, /etc/ssh, /etc/group
  + PowerShell script-block logging
                \                                                 /
                 \                                               /
   FW01 / FW02 (OPNsense) -- syslog 514 -->  SIEM01: Wazuh manager + indexer + dashboard
                                              ├─ local_rules.xml  (16 Halden detections 100100-100116)
                                              ├─ agent.conf per agent group (windows-servers,
                                              │     windows-workstations, linux-servers)
                                              ├─ Integrations -> email / Teams / Telegram
                                              └─ Active response (block IP on repeated SSH fail, with timeout)
                                                        │
                                          OPS01: Uptime Kuma  ──  status page + alert routing
```

Full diagram (hero image): [`docs/diagrams/p07-architecture.svg`](./diagrams/p07-architecture.svg).
ATT&CK coverage heat map (derived from `data/attack-mapping.csv`):
[`docs/diagrams/p07-attack-coverage.svg`](./diagrams/p07-attack-coverage.svg).

### 4.1 SIEM01 sizing (the RAM warning)

P7 is the heaviest project in the lab. The Wazuh indexer alone wants about 4 GB, and the manager,
dashboard and Docker overhead sit on top. The owner's host has **16 GB**, so:

| SIEM01 RAM | Result |
|---|---|
| 4 GB | Minimum that still starts; dashboards are slow, indexer may struggle |
| **6 GB (chosen)** | Comfortable for a lab of this size; run other VMs sparingly while Wazuh is up |
| 8 GB | Smooth; use for a live demo or if the owner adds RAM |

While Wazuh runs, power off FS01, WS02 and OPS01 where the phase allows. `scripts/00-Prepare-SIEM01.sh`
refuses to continue below 4 GB and warns below 8 GB.

## 5. Log sources and retention

Priority 1 sources are collected first (full table: `configs/log-source-inventory.csv`).

| Priority | Source | Why | Retention (planned) |
|---|---|---|---|
| 1 | DC Security logs (4624/4625/4672/4720/4728/4732/4740/4756/4768/4769/4771) | Identity is the #1 vector; base for D1-D4, D10, D11 | 90 days hot, configurable |
| 1 | Sysmon on all Windows hosts | Endpoint behaviour: process, LSASS access, file, registry, DNS | 90 days hot |
| 1 | PowerShell 4104 script-block logs | Living-off-the-land execution (D6) | 90 days hot |
| 1 | OPNsense syslog (filterlog, VPN) | Perimeter and remote-access abuse (D12) | 90 days hot |
| 2 | Linux auth.log + auditd (LNX01, OPS01, BKP01) | SSH brute force, sudo misuse, backup host | 90 days hot |
| 3 | Entra ID sign-ins (M365 trial, optional) | Cloud identity, break-glass use | If the trial is live |

**Security log sizing:** at least 1 GB on DCs and FS01, 512 MB on workstations
(`scripts/05-Set-WindowsAuditPolicy.ps1`). A log that rolls over before an analyst looks is an
unmonitored system. A log that is *cleared* is itself a detection (D8).

**Retention rationale:** 90 days hot covers the "we found out weeks later" case that the market
data describes; the lab is not sized for a year of hot storage, and that limitation is stated in
§9 rather than hidden.

## 6. Detection engineering approach

**Method.**

1. Start from the attacker behaviours that matter to Halden (identity abuse, credential access,
   ransomware staging, defence evasion), not from a tool's default rule list.
2. For each behaviour, ask: *is there a data source that would show it, and is that source turned
   on?* If not, fix the source first — that is why the audit policy and PowerShell logging are
   prerequisites, not afterthoughts.
3. Write the rule to match the behaviour with the **narrowest** condition that still catches it.
4. Give it a level (severity), an ATT&CK id, and a runbook.
5. Test with `wazuh-logtest` on a real sample event, then in an approved simulation.
6. Tune with documented narrow exceptions.

**The 16 detections** (full rationale in `configs/local_rules-rationale.md`, IDs `100100`-`100116`):
privileged group change, privileged group context, Kerberoasting, AS-REP roasting, LSASS access,
DCSync, encoded/cradle PowerShell, shadow-copy deletion, security log cleared, new service,
scheduled task, Tier 0/break-glass logon, password spraying, VPN anomaly, Defender/ASR block,
backup failure, agent-silent. **14 map to 14 ATT&CK techniques; 2 are availability checks** kept
out of ATT&CK deliberately because they are not attacker behaviour.

**Why behaviour over signature** is explained for interview purposes in the project README; the
short version is that a signature tells you a known tool was used, and a behaviour rule tells you
what happened to a host — which is what you escalate on.

**Base SID caveat:** the Windows-event rules use `<if_sid>60000</if_sid>` and narrow by EventID.
The exact parent SID and extracted field names vary between Wazuh versions, so each rule is
verified with `wazuh-logtest` on the installed version before it is trusted. This is stated in the
rules file header and is a known, honest limitation.

## 7. Triage and escalation model

**Severity is business impact, not rule level.** The same alert on a test workstation and on a
domain controller are not the same incident. Full matrix: `configs/alert-severity-triage.csv`.

| Severity | Trigger | Response target | Notify |
|---|---|---|---|
| SEV1 | Level ≥13, or multiple identity detections on one account/host | Immediate 24×7 | On-call + Incident Lead by phone; MD within 15 min |
| SEV2 | Level 10-12 | < 1 hour | On-call by email/Telegram + GLPI ticket |
| SEV3 | Level 7-9 | < 1 business day | Daily digest + ticket |
| Info | ≤6 | No response | Weekly review (baseline building) |

**Incident severity definitions** (used by the IR plan and the tabletop):

- **SEV1** — ransomware executing, active domain compromise, or a Tier 0 host lost. All hands;
  management decides on payment/communication.
- **SEV2** — a confirmed account compromise or malware contained on one host. IT handles it; the
  affected department head and the IT manager are informed.
- **SEV3** — suspicious activity or a policy violation with no confirmed impact. IT investigates in
  the normal queue.

**The triage loop** (what an analyst actually does): confirm the alert is real → establish scope
(who, what host, what else by that actor) → contain → preserve evidence → escalate per severity →
follow the matching playbook → write the incident report.

## 8. Availability monitoring design

Uptime Kuma on OPS01 (installed in P9 per the roadmap; P7 uses it). The design point worth
understanding: the **backup monitor is a push heartbeat**, not a check. The P8 backup job calls the
push URL **only on success**, and the monitor is set to a heartbeat interval — so no call means the
monitor goes down. An absence of a signal is the alert, which is the only way to catch a backup that
silently fails. Same pattern for disk space: a push script reports usage, and a monitor trips at
85%.

Notifications go to Telegram/Teams and email, with a repeat every 30 minutes until acknowledged.
A **status page** answers "is it down or just me?" for staff, which also reduces helpdesk tickets —
the IT Support Officer angle.

## 9. Honest limitations (write these down, do not hide them)

| Limitation | Consequence |
|---|---|
| The lab is not 24×7 staffed | SEV1 response targets are aspirational for the owner; the design says who *would* be called, not that someone is awake |
| Sysmon and Defender can prevent some simulated techniques | A "prevented" result is recorded separately from "detected"; a block is a good outcome, not a failed test |
| Indexer sizing on a 16 GB host | Slow dashboards; retention is 90 days hot, not a year; heavy queries may time out |
| Base SIDs and field names vary by Wazuh version | Rules must be verified with `wazuh-logtest` before trust; this is a build step, not an assumption |
| The Wazuh rules are mapped, not yet validated | The coverage matrix `validated` column is empty until an approved simulation runs |
| Active response can block yourself | The block list has an allow-list for management; the timeout is deliberately short and documented |
| Monitoring sees staff activity | Legitimate privacy considerations are addressed in the monitoring policy (`business/p07-monitoring-policy.md`); monitoring is for security, not performance surveillance |

## 10. Monitoring and privacy (called out early because it is a people project, not a cable project)

Halden monitors systems, not people. That is an important sentence for an interview and for the
staff communications:

- The purpose is **security and availability**, and it is stated in writing.
- Log collection covers **host and service activity** (logons, processes, service changes,
  availability) needed for the detections above.
- Access to the SIEM is restricted to IT and is itself logged; case notes explain *why* an analyst
  looked.
- Retention is defined and finite (90 days hot), and staff are told what is collected and why.
- Monitoring is **not** used for productivity measurement, and personal content is not the target.

This is written up as a policy in `business/p07-monitoring-policy.md`; the privacy argument is
rehearsed as an interview question in the README.

## 11. Build phases and evidence plan

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | This design document | (document itself) |
| 1 | SIEM01 up (manager/indexer/dashboard); agents on all sources; Sysmon; audit policy; firewall syslog | Agents list all Active; Sysmon running; `auditpol` output; dashboard screenshot |
| 2 | 16 custom rules installed and tested with `wazuh-logtest` | Rules file + logtest output for a sample event |
| 3 | Authorised simulation run; rules that fired recorded | `wazuh-logtest`/alerts for D1/D2/D5/D7; sanitized alert extract |
| 4 | Noise tuning with a written log | alerts/day before vs after; tuning-log entries |
| 5 | Availability monitoring + status page + backup heartbeat | Uptime Kuma dashboard; status page; push monitor |
| 6 | IR plan, 5 playbooks, one lab incident, tabletop | Incident report timeline; tabletop report (outcomes section empty until run) |

## 12. Acceptance tests (run before calling P7 Done)

| Test | Expected |
|---|---|
| Every host reports to Wazuh | Agent list shows all sources Active |
| `wazuh-logtest` on a captured sample for each rule | Rule matches with the intended level and description |
| Approved simulation of the mapped techniques | Each rule fires, or is recorded as not fired with a reason (Defender prevented / needs tuning) |
| Stop an agent | D15 alert after the expected interval |
| Backup job does not call the heartbeat | Uptime Kuma backup monitor goes down |
| Firewall syslog | FW01 events appear in Wazuh |
| Tabletop exercise | Report produced with tracked actions (outcomes filled only after it runs) |

## 13. Snapshot and rollback plan

- **Before every phase:** hypervisor snapshot of each VM the phase touches, named
  `snap-p7-ph<N>-before` (e.g. `snap-p7-ph1-before`). Rollback = revert the snapshot and re-run the
  phase scripts, which are idempotent.
- **Before any simulation:** snapshot the target VM (WS01), and DC01 too if the optional privileged
  group control test is used. `scripts/07` refuses to run without the snapshot attestation.
- **SIEM01:** a full VM snapshot is the rollback; the compose stack and data live in Docker volumes
  under `/opt/wazuh`, so a revert restores the previous state cleanly.
- **Tier 0 caution:** no simulation ever runs on DC01/DC02/FS01 (enforced in `scripts/07`); the one
  DC-touching test is off by default and double-gated.

## 14. Decisions taken

1. **Wazuh all-in-one via Docker Compose** on a single SIEM01 node, rather than the install script,
   so the stack is declarative and reproducible (`configs/docker-compose.wazuh.yml`).
2. **SIEM01 at 6 GB** given the 16 GB host (see `DECISIONS.md` D11 and §4.1).
3. **16 rules, not 12.** The plan lists D1-D12; the design adds availability checks (D14 backup
   failure, D15 agent silent) and a scheduled-task detection (D9b), all named in the plan's Phase 5
   and Phase 1 respectively. This is a build-kit enlargement, recorded for the owner's approval.
4. **Simulation is Atomic Red Team, curated and gated.** Only a safe subset of public technique
   tests, only on a snapshotted non-Tier-0 host, only with explicit approval (AGENTS.md R6).

## 15. Risks

| Risk | Mitigation |
|---|---|
| Alert fatigue (the classic SIEM failure) | Use-case-driven collection, severity routing, narrow tuning with a log, measured true-positive rate |
| Missing command-line/PowerShell auditing | Made a prerequisite; most endpoint detections depend on it |
| Simulation on an unsnapshotted or Tier 0 host | Hard gates in `scripts/07`; Tier 0 hosts refused outright |
| 16 GB host out of RAM | SIEM01 6 GB, other VMs powered off while Wazuh runs; sizing documented |
| Publishing something that could be a secret | Sanitization pass in `scripts/09`; raw archives never committed (AGENTS.md 4.6) |
| Presenting mapped coverage as validated coverage | Matrix `validated` column empty; heat map labelled "mapped" |

## 16. Interview notes (phase 0)

**"You get an alert that a user was added to Domain Admins at 2am. Walk me through it."** Validate
first (who, from where, via what), then check the change log — was this approved? If not, contain
(remove the membership, disable the source account, isolate the host), preserve evidence before
touching the machine further, scope for other changes by that account, escalate per severity, and
report. The point is that the alert starts a defined process, not an improvised one.

**"How do you avoid alert fatigue?"** Use-case-driven collection so we are not shipping noise,
severity routing so only the important things page a human, narrow tuning with a written log so
suppression is a decision rather than a habit, and a measured true-positive rate so we can prove
the signal got better.

**"How do you know your monitoring works?"** A detection-coverage table produced from a real,
approved simulation — detection is tested, not assumed — plus a rule that did not fire being
recorded honestly rather than assumed to be fine.

---

*Next step: Phase 1 — SIEM01 (plan §Phase 1). Snapshot first; advertise the changes before running
anything (Mode A: the owner runs the commands and pastes output back).*

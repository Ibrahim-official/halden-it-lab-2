# P7: Security Monitoring, SIEM and Incident Response — Wazuh, Sysmon, ATT&CK-mapped detections and a rehearsed IR capability

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd.").
> Presented as a home lab on the portfolio site — never as employment experience.
> Any attack-technique simulation described here is an **authorised lab exercise** on the owner's own
> isolated lab, run only with explicit approval (AGENTS.md R6) against a snapshotted host.

**Status:** build kit complete — **lab execution pending** · **Build order:** 9 of 10 · **Depends on:** P1-P6 (needs the most RAM; best done once everything else exists)
**Plan:** [`docs/plan/P07-monitoring-siem-incident-response.md`](../../docs/plan/P07-monitoring-siem-incident-response.md) · **Design:** [`docs/00-design.md`](./docs/00-design.md) · **Site page source:** [`showcase.md`](./showcase.md)

## Problem

At Halden nobody would notice an attacker until the ransom note appeared. Logs sit on each machine
and overwrite within days; nothing is watching them; and when the file server filled up last month,
users reported it before IT knew. There is no incident process either: "who do we call?" was answered
in a group chat. Ransomware appears in **88% of small-business breaches** (Verizon DBIR 2025, cited
in `docs/plan/00-research-and-selection.md`) and attackers typically spend days escalating privilege
before they encrypt — a window that is only useful if someone is watching for it. Two job-ad
responsibilities sit directly behind this project: monitor health, availability, logs, alerts and
security events, and identify and respond to security incidents.

## What I built

- **A single place that watches the whole environment** — a Wazuh SIEM (manager + indexer +
  dashboard) on SIEM01, receiving security events from every server and workstation and syslog from
  both OPNsense firewalls, deployed as a declarative Docker Compose stack.
- **Endpoint telemetry worth having** — Sysmon with a focused Halden config on every Windows host,
  Windows advanced audit policy per Microsoft's guidance, command-line process auditing, PowerShell
  script-block logging and enlarged security logs. Without these, most detections cannot see
  anything, so they are prerequisites rather than afterthoughts.
- **Sixteen custom detection rules mapped to fourteen MITRE ATT&CK techniques**, written for
  behaviour rather than signatures: privileged group changes, Kerberoasting, AS-REP roasting, LSASS
  access, DCSync, encoded PowerShell, shadow-copy deletion, log clearing, new services and scheduled
  tasks, Tier 0 logons, password spraying, VPN anomalies, Defender/ASR blocks, plus two availability
  checks. Each rule has a level, an ATT&CK id and a runbook.
- **A detection-validation method** — an approved, snapshotted lab exercise drives public Atomic Red
  Team tests and records which rules actually fired, how fast, and where Defender *prevented* the
  action (a prevention is a good result, recorded separately from a detection).
- **An ATT&CK coverage heat map derived from the rules themselves**, so the picture cannot drift away
  from what is actually configured.
- **Tuning by exception, not by disabling** — a written logging method with narrow process+path+host
  suppressions and a measured before/after noise figure.
- **Availability monitoring** on Uptime Kuma: DNS, LDAP, SMB, web apps and VPN checks, a **backup
  push heartbeat** where the *absence* of a signal means a failed backup, and a staff status page
  that answers "is it down or just me?" (and cuts helpdesk tickets).
- **An incident response capability** — a NIST SP 800-61r3 / CSF 2.0-aligned plan, a severity matrix
  by business impact, five runbooks, an escalation/on-call matrix, and a management tabletop exercise
  pack with a report template.
- **Documentation and business artefacts as deliverables** — design and as-built documents, two
  diagrams, six runbooks, an executive brief, the IR plan, a monitoring policy, the tabletop pack and
  a change record.

## Architecture

![P7 monitoring and incident response architecture](docs/diagrams/p07-architecture.svg)

Log sources (Windows servers and workstations, Linux servers, and both firewalls) send telemetry
through Wazuh agents into SIEM01, where the manager applies the custom rules, the indexer stores the
events and the dashboard presents them. Detection feeds analyst triage, which feeds a ticket or an
incident, which feeds improvements back into the detections — the feedback loop is the part that
keeps the coverage honest. Availability monitoring sits alongside on OPS01. The ATT&CK heat map
([`docs/diagrams/p07-attack-coverage.svg`](./docs/diagrams/p07-attack-coverage.svg)) is derived
directly from `data/attack-mapping.csv`.

The one idea worth an interview answer is *behaviour over signatures* — a rule that matches what an
action does to a host survives an attacker changing their tools:

```xml
<rule id="100107" level="14">
  <if_sid>60000</if_sid>
  <field name="win.system.eventID">^1$</field>
  <field name="win.eventdata.commandLine" type="pcre2">(?i)(vssadmin.*delete.*shadows|wmic.*shadowcopy.*delete|wbadmin.*delete.*(catalog|backup)|bcdedit.*recoveryenabled\s+no)</field>
  <description>Halden D7: shadow copies or recovery data being deleted by $(win.eventdata.image) (ransomware precursor)</description>
  <mitre><id>T1490</id></mitre>
</rule>
```

Shadow-copy deletion is the last step before encryption; by the time it happens, the useful response
window is measured in seconds. That is why D7 is the highest-severity rule in the set.

## How to reproduce

Run in order. Every script is idempotent, lab-guarded (it refuses to run outside `ad.halden.internal`
or a host carrying `/etc/halden-lab`), and PowerShell scripts support `-WhatIf` and
`[CmdletBinding(SupportsShouldProcess)]`.

| Order | Where | Script | Does |
|---|---|---|---|
| 0 | SIEM01 | `scripts/00-Prepare-SIEM01.sh` | Kernel settings, Docker, working directory; **refuses to run below 4 GB RAM** (warns below 8 GB) |
| 1 | SIEM01 | `scripts/01-Deploy-Wazuh.sh` | Certificates, random `.env`, starts manager + indexer + dashboard |
| 2 | Windows hosts | `scripts/03-Deploy-Agents-Windows.ps1` | Wazuh agent, correct agent group, idempotent |
| 3 | Linux hosts | `scripts/02-Deploy-Agents-Linux.sh` | Wazuh agent on LNX01/OPS01/BKP01 |
| 4 | All Windows | `scripts/04-Deploy-Sysmon.ps1` | Sysmon with the Halden config; updates when the config hash changes |
| 5 | DCs, FS01, WS01/02 | `scripts/05-Set-WindowsAuditPolicy.ps1` | Advanced audit subcategories, command-line auditing, PowerShell logging, log size |
| 6 | SIEM01 | `scripts/06-Deploy-DetectionRules.sh` | Validates XML, installs 16 rules and three agent groups, restarts the manager |
| 7 | WS01 (snapshotted) | `scripts/07-Run-AuthorisedSimulation.ps1` | **Approved** lab exercise only; four gates; never a Tier 0 host |
| 8 | SIEM01 | `scripts/08-Validate-Detections.sh` | Reports which custom rules actually fired |
| 9 | SIEM01 | `scripts/09-Export-AlertEvidence.sh` | Sanitized alert extract for the portfolio |
| 10 | OPS01 | `scripts/10-Configure-UptimeKuma.sh` | Monitor definitions + backup heartbeat + disk push helpers |
| 11 | anywhere | `scripts/11-AttackCoverageReport.py` | Coverage roll-up from the mapping + a real alert extract |
| 12 | anywhere | `scripts/tests/` | Unit tests for the coverage logic (`python3 -m unittest discover -s scripts/tests`) |

**Prerequisites.**

- **SIEM01 with enough RAM.** This is the heaviest project in the lab. Give SIEM01 **6 GB** (minimum
  4 GB, smooth 8 GB) and power off FS01/WS02/OPS01 while Wazuh runs — the owner's host has 16 GB.
- **The owner's explicit approval before any simulation** (AGENTS.md R6). `scripts/07` will not run
  without `-ApproveAuthorisedLabSimulation`, a typed approval phrase, a snapshotted target and
  `-SnapshotTaken`. It refuses to run on DC01/DC02/FS01 entirely.
- Ubuntu 24.04 on SIEM01, Docker, the Windows and Linux hosts from P1-P6, and the syslog path from
  FW01/FW02.
- Secrets (dashboard, indexer and API passwords; the Uptime Kuma token) are generated locally into an
  untracked `.env` or entered from the owner's password manager — never committed.

**Snapshot before every phase** (`snap-p7-ph<N>-before`). **Rollback:** revert the snapshot and
re-run the phase scripts, which are idempotent; on SIEM01 the stack and its data live in Docker
volumes under `/opt/wazuh`, so a revert restores the previous state cleanly. Windows audit-policy and
Sysmon changes are reversible with `auditpol` defaults and `sysmon64 -u`.

## Results

**Not measured yet.** This build kit has been written but not yet executed in the lab, so this table
is deliberately empty rather than filled with plausible-looking numbers. Detection coverage in
particular is a **result**, not a claim: `configs/detection-coverage-matrix.csv` lists all 16 rules
with the `validated` column empty, and it is filled only from an approved simulation run.

| Metric | Before | After | Source |
|---|---|---|---|
| Agents reporting (share of hosts) | not measured | not measured | — |
| ATT&CK-mapped detection rules deployed (mapped, not validated) | not measured | not measured | — |
| Rules that fired in the authorised validation run (`validated` column) | not measured | not measured | — |
| Median time from event to alert | not measured | not measured | — |
| Alerts per day (all) before vs after tuning | not measured | not measured | — |
| Share of High+ alerts that were true positives | not measured | not measured | — |
| Critical services covered by availability monitoring | not measured | not measured | — |
| Tabletop improvement actions produced (with owners) | not measured | not measured | — |

## Acceptance tests

| Test | Expected | Actual | Pass |
|---|---|---|---|
| Every host reports to Wazuh | Agent list shows all sources Active | not run | ☐ |
| `wazuh-logtest` on a captured sample per rule | Rule matches with the intended level and description | not run | ☐ |
| Approved simulation of the mapped techniques | Each rule fires, or is recorded as not fired with a reason | not run | ☐ |
| Stop an agent | D15 alert after the expected interval | not run | ☐ |
| Backup job does not call the heartbeat | Uptime Kuma backup monitor goes down | not run | ☐ |
| Firewall syslog | FW01 events appear in Wazuh | not run | ☐ |
| Publish nothing that could be a secret | Sanitized extract contains no credentials or keys | not run | ☐ |
| Tabletop exercise | Report produced with tracked actions | not run | ☐ |

## Business deliverables

| Artifact | For | File |
|---|---|---|
| Executive brief — what we can see, what we can respond to, what we ask management to approve | Managing Director and management | `business/p07-exec-brief.md` |
| Incident response plan (severity, roles, escalation, communication, evidence handling) | Management approval; operational use | `business/p07-ir-plan.md` |
| Monitoring and log collection policy (what is logged, retention, privacy commitments) | Staff and management; addresses the privacy question honestly | `business/p07-monitoring-policy.md` |
| Tabletop exercise pack (scenario, injects, facilitator notes) | Facilitating the management rehearsal | `business/p07-tabletop-exercise.md` |
| Tabletop report template (findings and actions) | Recording the rehearsal outcomes | `business/p07-tabletop-report.md` |
| Monthly security summary template (alerts, incidents, uptime) | Monthly management reporting; feeds P10 | `business/p07-monthly-security-summary.md` |
| Change record (risk, test plan, backout) | Management / audit trail; feeds the P10 change log | `business/p07-change-record.md` |

## Lessons learned

- **Monitoring is a design problem, not a tool problem.** The hardest part was deciding what *not* to
  collect. "Collect everything and alert on everything" is the failure mode that produces an
  unreadable dashboard and an analyst who stops reading it.
- **The data source is the real prerequisite.** Command-line process auditing and PowerShell
  script-block logging are boring settings, and without them half the endpoint detections literally
  cannot see anything — a rule is only as good as the telemetry underneath it.
- **Behaviour beats signatures in a small business.** There is no threat-intel feed to keep
  signatures fresh, but there is a known baseline of accounts, hosts and services; writing rules
  against that baseline is what makes them survive a change of tools.
- **A rule that did not fire is not a failure — hiding it would be.** The coverage matrix exists so
  that coverage is a measured result with gaps recorded, not a slide.
- **The privacy question is a people question.** Adding monitoring touches how staff feel about their
  workplace; the policy that says "systems, not people" had to be written as carefully as the rules.

## Interview notes

**"You get an alert that a user was added to Domain Admins at 3am. Walk me through it."** First,
validate — who made the change, from which account and host, and is there an approved change record
or a JML reason? If not, this is SEV1. Then contain reversibly (remove the membership, disable the
source account, isolate its host) while preserving evidence, scope for everything else that account
touched in the window — correlated group changes, DCSync, new services — escalate per the severity
matrix, and write the timeline from the events rather than from memory. The alert starts a defined
process; it does not start an improvisation.

**"Why behaviour-based detection over signatures?"** A signature matches a known bad string, so it is
defeated by an attacker changing tooling, and in a small business nobody is maintaining a fresh
signature feed. A behaviour rule matches what an action does to a host or an identity — a member
added to a privileged group, a process reading LSASS, shadow copies being deleted — which is stable
across tools and is also what you escalate on. The trade-off is more tuning work, which is why every
rule has a runbook and the noise is measured.

**"How do you decide a detection is worth keeping?"** Three questions. Does it map to behaviour that
would actually hurt us? Does it have a documented response that changes the outcome? And what does it
cost in analyst attention — measured as alerts per day and the true-positive share? A rule with a
real response and a manageable false-positive rate stays; a rule that fires constantly and is always
"probably fine" gets a narrow exception or is rewritten, never quietly disabled.

**"How do you explain monitoring to staff who are worried about privacy?"** Directly: we monitor
systems for security and availability, the way a building has smoke alarms — logons, system changes,
whether services are up — not the contents of their documents and not how hard they are working. The
monitoring policy says that in writing: purpose limitation, least collection, access to the SIEM is
logged, retention is finite and published, and looking at a person's activity needs a recorded
reason. The honest answer is more reassuring than a vague one.

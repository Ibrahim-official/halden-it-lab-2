# Halden Distribution Ltd. — IT at a glance (1 page)

**For:** the Managing Director and the management team · **From:** IT · **Date:** 2026-10-02
**Status of the programme:** build kits complete, lab execution pending

> Halden Distribution Ltd. is a **fictional** 85-user company used for a home-lab portfolio. The
> configurations, scripts and measurable results are real; the business, the people and the approvals
> are simulated. This page contains **no invented figures** — where a number has not been measured it
> says so.

## The situation we inherited

Halden ran everything on one aging server with no redundancy; all 85 staff held Full Control on the
shared drive; there was no MFA, no tested backup, no logging worth the name, assets tracked in a
spreadsheet and 30% of PCs on Windows 10 past its support date. Nobody could answer "who can read
Finance data?" or "what changed last week, and who approved it?".

## What IT has built

Nine technical projects cover the estate end to end, and this tenth one governs and reports on them:

| Area | What was built | Project |
|---|---|---|
| Foundation | Two domain controllers, DNS, DHCP failover, least-privilege file services, Group Policy baseline, Linux joined to AD | P1 |
| Identity | Automated joiner/mover/leaver from HR data, MFA and Conditional Access, quarterly access reviews | P2 |
| Security | Active Directory security assessment, privileged-access tiering, Windows LAPS | P3 |
| Endpoints | Security baselines, attack-surface reduction, BitLocker, Windows 11 readiness | P4 |
| Patching & vulnerabilities | Risk-tiered patch rings and a vulnerability prioritisation engine | P5 |
| Network | Zone segmentation, a firewall rule matrix, MFA-protected remote access, enterprise Wi-Fi | P6 |
| Monitoring | A SIEM with detections mapped to attacker techniques, and incident-response playbooks | P7 |
| Resilience | 3-2-1-1-0 backups with an immutable copy and automated restore verification | P8 |
| Service desk & records | A service desk with SLAs, an asset inventory (CMDB), a documentation hub, a vendor register | P9 |
| Governance | CIS IG1 scorecard, change control and a CAB, a ten-policy pack, a monthly KPI report and risk register | **P10** |

## What governance adds (this project)

- **A scorecard:** all 56 CIS Controls v8.1 IG1 safeguards, scored before and after, where a score of
  "fully implemented" requires a file that proves it — enforced by the tooling, not by trust.
- **Change control:** every change is classified standard, normal or emergency, risk-assessed and
  approved; a change with no rollback plan cannot be approved.
- **Policies:** ten short, plain-English policies ready for management approval, with an
  acknowledgement process and an exceptions register.
- **Reporting:** a two-page monthly report with a RAG status, plus a risk register and a consolidated
  action tracker so nothing is quietly dropped.

## What we need from management

1. **Approve the policy pack** (ten documents, 1–2 pages each).
2. **Appoint a business owner for each risk** on the register — IT cannot own a business risk.
3. **A decision on the 90-day roadmap** and its cost, presented in the "State of IT" talk.

## Honesty statement

Nothing has been measured in the lab yet. The percentage of CIS IG1 implemented, the KPI values and
the chart are **deliberately not published** until real figures exist. Every number added later will
carry a source file; anything unmeasured will say "not measured" rather than being estimated.

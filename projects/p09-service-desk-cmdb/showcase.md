---
id: p09
order: 3
title: IT Service Desk, Asset Inventory (CMDB) and Documentation Hub
tagline: "A real ITSM platform: asset discovery, SLAs, knowledge base, vendors and config-as-code"
status: in-progress
started: 2026-10-02
roles:
  - it-support
  - sysadmin
skills:
  - GLPI
  - ITSM
  - CMDB
  - Asset Discovery
  - SLAs
  - Service Catalogue
  - BookStack
  - PHP/MySQL
  - Uptime Kuma
  - Git config-as-code
  - Vendor Management
  - PowerShell
  - Python
jd_bullets:
  - Maintain accurate infrastructure inventory, configurations, diagrams and technical documentation
  - Coordinate with vendors and service providers
  - Provide technical support and escalation assistance to the IT Support team
  - Maintain accurate records and ensure timely completion (SLAs)
  - Follow change-control procedures (config drift detection)
  - Improve processes and produce reports for management
hero: ./evidence/public/p09-architecture.svg
documents:
  - title: "Change Record"
    href: ./business/p09-change-record.pdf
  - title: "Escalation Matrix"
    href: ./business/p09-escalation-matrix.pdf
  - title: "Itsm Brief"
    href: ./business/p09-itsm-brief.pdf
  - title: "Kpi Reporting"
    href: ./business/p09-kpi-reporting.pdf
  - title: "Service Catalogue"
    href: ./business/p09-service-catalogue.pdf
  - title: "Sla Policy"
    href: ./business/p09-sla-policy.pdf
  - title: "Vendor Management"
    href: ./business/p09-vendor-management.pdf
repo_path: projects/p09-service-desk-cmdb
cv_bullets:
  - Deployed GLPI ITSM on Ubuntu with agent-based asset discovery, LDAP authentication and a weekly reconciliation
    script that compares the CMDB against DHCP leases and network scans.
  - Built a helpdesk with a service catalogue, business-hours SLAs (TTO/TTR) and an L1 to L2 to vendor escalation
    matrix, plus a BookStack documentation hub with an owner and review date on every page.
  - "Implemented config-as-code: a nightly export of GPO, AD, DHCP, DNS, firewall and NPS configuration to a private Git
    repository, with drift detection that flags a change lacking an approved change record."
lab_note: Home-lab project in an isolated, simulated 85-user company (Halden Distribution Ltd.). Tickets, assets,
  suppliers and contracts are synthetic. This page shows a working build kit that is being executed in the lab phase by
  phase — the results table stays empty and no number appears here until it has actually been measured.
---

## The problem

At Halden, support requests arrive by email, Teams, WhatsApp and by people walking up to the desk.
Nothing is tracked, so nobody knows the workload, what keeps breaking, or whether a user waits an
hour or a week. The asset spreadsheet is out of date, and the firewall support contract expired
unnoticed because no one owned the renewal. For a small business this is not just untidy: many SMBs
still track IT assets on spreadsheets or not at all, and outdated records lead to overspending and to
unmanaged devices sitting on the network (`docs/plan/00-research-and-selection.md`, finding 9). CIS
Controls 1 and 2 — asset and software inventory — are the first two safeguards an SMB is measured
against. (Market context and the job-ad evidence behind this project are in
`docs/plan/00-research-and-selection.md`.)

## What I built

- **GLPI (PHP + MariaDB) on one Ubuntu host**, deployed with Docker Compose and authenticating to
  Active Directory over LDAPS, with group mapping so IT staff are Technicians and everyone else is
  Self-Service.
- **A service catalogue** of nine services with request forms, approval routes and target times,
  defined once in `configs/glpi-service-catalogue.json` and applied to GLPI by a script.
- **Priority-based SLAs on a business calendar** (Mon–Fri 08:00–18:00): P1 15 minutes to own and
  4 hours to resolve, through to P4 at one and five business days, with automatic escalation to L2 at
  75% of the resolution target.
- **An L1 → L2 → vendor escalation matrix** with a handoff template, so a ticket carries everything
  the next tier needs.
- **Agent-based asset discovery**, reconciled weekly against DHCP leases and a network sweep —
  target **0 unknown-on-network** — plus a drift check against AD, DNS and DHCP reservations.
- **A vendor, contract and licence register** (fictional suppliers) with renewal alerts at 90 and 30
  days and a licence right-sizing view.
- **BookStack as the documentation hub** for the as-built docs, runbooks and diagrams of the earlier
  projects, with an owner and a review date on every page.
- **Uptime Kuma** for monitoring, installed here so the backup project (P8) has a heartbeat to call
  after a successful restore test.
- **Config-as-code with drift detection**: a nightly export of GPO, AD, DHCP, DNS, firewall and NPS
  configuration to a private Git repository, and a check that raises an "unauthorised change" ticket
  when a changed file has no approved change record.

## How it works

![P9 service desk architecture](./evidence/public/p09-architecture.svg)

OPS01 runs five containers — GLPI and its database, Uptime Kuma, and BookStack and its database. The
P1 estate feeds it (DHCP leases, AD objects, agent inventory, SNMP), P7 alerts and the P8 restore
test create tickets automatically, and configuration flows the other way into a private Git
repository every night. The lab is never exposed to the internet: the interfaces bind to loopback
until the internal certificate from the network project exists.

The piece that makes the CMDB trustworthy is the reconciliation classifier — three sources, one
verdict per device:

```powershell
$status = if ($onNet -and -not $inGlpi) { 'Unknown-OnNetwork' }   # on the network, not in the CMDB
          elseif ($inGlpi -and -not ($onNet -or $inDhcp)) { 'Stale-InGlpi' }
          else { 'Matched' }
```

## Results

**Not measured yet.** The build kit (scripts, configuration, documentation and business artifacts) is
complete and lab execution has not started, so every metric is stated as "not measured" rather than
filled with a plausible-looking number. Real results are added to the project README with a file in
`evidence/public/` as the source for each one.

| Metric | Before | After | Source |
|---|---|---|---|
| Devices discovered automatically by the GLPI Agent | not measured | not measured | — |
| Reconciliation: unknown-on-network devices (target 0) | not measured | not measured | — |
| SLA compliance — time to own and time to resolve | not measured | not measured | — |
| Unauthorised configuration changes detected | not measured | not measured | — |

## Business side

The technical platform is only half of an IT support project; the other half is what the business
agrees and receives:

- **Service catalogue** — what IT offers, who may request it, who approves it and how long it should
  take. Access to business data is approved by the data owner, not by IT.
- **SLA policy** — the priority matrix, the business-hours calendar and the response and resolution
  targets, written so a target means the same thing to the desk and to the business.
- **Escalation matrix** — the L1/L2/vendor routes with a handoff template, so information is not lost
  between people.
- **Vendor management procedure** — how a case is raised and tracked, time-bound vendor access, and
  an annual review that includes security questions.
- **One-page executive brief** and **KPI/reporting definitions** — what will be reported each month,
  how each measure is calculated, and an explicit statement that no figure is published until it has
  been measured.
- **Change record** — risk, impact, test plan and backout, feeding the governance work in P10.

## What I learned / what I'd do differently

- **Write the catalogue before touching the tool.** The service list, the priorities and the
  escalation routes are business decisions; configuring GLPI first would have meant inventing them in
  the software, which is how catalogues turn into sixty categories nobody uses.
- **An SLA without a business-hours calendar is a promise you cannot keep.** Making the calendar
  explicit — and covering the weekend and holiday rollover with unit tests — is what turns "8 hours"
  into something the desk can actually be measured against.
- **An asset register is only true on the day it is reconciled.** Automating the three-source
  comparison and treating "0 unknown-on-network" as a test result, not an import, is the difference
  between a CMDB and another spreadsheet.
- **Config-as-code is only a control with a change record beside it.** A nightly diff that flags
  everything is noise; the value is checking the diff against approved change records, and I would
  wire that check in from the first commit next time.
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.

> Status: **in progress**. The build kit (scripts, configs, runbooks, business artifacts) is
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.

# Halden IT Lab — SMB IT portfolio (IT Support Officer / junior System Administrator)

A documented home lab that builds one fictional company end to end: **Halden Distribution Ltd.**
(85 staff, one head office, one warehouse, 12 remote sales staff). Ten projects cover Active
Directory, identity lifecycle and MFA, AD security and privileged access, endpoint hardening,
patch and vulnerability management, network segmentation and VPN, SIEM and incident response,
backup and disaster recovery, the IT service desk and CMDB, and IT governance with CIS Controls
IG1 reporting.

**This is a home lab, not job experience.** Everything runs in an isolated lab
(`ad.halden.internal`, 192.168.x ranges) on hardware the owner controls. Every number published
here comes from a real run in the lab; synthetic data (such as the 85-user HR file and the
synthetic device fleet) is labelled as synthetic wherever it appears.

## Projects (tailored build order)

| # | Project | Anchor score | Build kit | Lab run |
|---|---|---|---|---|
| 1 | [P1 — Core Infrastructure Build](projects/p01-core-infrastructure/) | 86 | ✅ complete | ⬜ pending |
| 2 | [P2 — Identity Lifecycle & Access Governance](projects/p02-identity-lifecycle/) | 94 | ✅ complete | ⬜ pending |
| 3 | [P9 — IT Service Desk, CMDB & Documentation Hub](projects/p09-service-desk-cmdb/) | 90 | ✅ complete | ⬜ pending |
| 4 | [P3 — AD Security & Privileged Access](projects/p03-ad-security/) | 93 | ✅ complete | ⬜ pending |
| 5 | [P4 — Endpoint Hardening & Windows 11 Readiness](projects/p04-endpoint-hardening/) | 87 | ✅ complete | ⬜ pending |
| 6 | [P8 — Backup, Recovery & DR](projects/p08-backup-dr/) | 97 | ✅ complete | ⬜ pending |
| 7 | [P5 — Patch & Vulnerability Management](projects/p05-vuln-management/) | 97 | ✅ complete | ⬜ pending |
| 8 | [P6 — Network Segmentation, VPN & Wi-Fi](projects/p06-network-segmentation/) | 87 | ✅ complete | ⬜ pending |
| 9 | [P7 — SIEM & Incident Response](projects/p07-siem-incident-response/) | 94 | ✅ complete | ⬜ pending |
| 10 | [P10 — IT Governance & Reporting](projects/p10-governance/) | 97 | ✅ complete | ⬜ pending |

A **build kit** means the design document, the phased and lab-guarded scripts, the configurations,
the runbooks, the diagrams, the business artifacts (as PDFs) and the showcase page are written,
reviewed and ready to run. **Nothing has been executed in the lab yet**, so no project is marked
`done` and no metric is published on the site — a rule enforced in CI, not just intended. See
[`PROGRESS.md`](PROGRESS.md) for the per-project state and the open Definition-of-Done items.

## What is in the repository today

| | |
|---|---|
| Projects | 10, in the tailored build order above |
| Scripts | 146 (PowerShell, Bash, Python, Ansible) — lab-guarded, idempotent, `-WhatIf` where they change state |
| Unit tests | 259 Python tests, all passing (the risk scoring, the JML rules, retention maths, restore-report parsing) |
| Runbooks | 47 operational runbooks written so someone other than the author can run the environment |
| Business artifacts | 61 documents (briefs, policies, matrices, registers, change records, plans) as Markdown **and** PDF |
| Diagrams | Governance/architecture diagrams per project, `.drawio` + `.svg` |
| Evidence | Architecture diagrams only so far — real screenshots and reports arrive with the lab runs |
| Site | Astro static build, 18 pages, honesty/placeholder/alt-text checks green |

Every published number must have a file behind it: `node site/scripts/check-honesty.mjs` fails the
build if a metric has no evidence or if a project that is not `done` declares one at all.

Total: about 18 weeks part-time (8–10 h/week). Application milestones: start applying for
IT Support Officer roles after P1 + P2 + P9 (week 6); junior sysadmin roles after P3 + P4 + P8
(week 11).

**Live portfolio website:** _not deployed yet_ — it goes live after P1 is Done (see
[`site/`](site/) and `AGENTS.md`, Section 5). The lab itself is never exposed to the internet;
the site publishes evidence (write-ups, diagrams, sanitized screenshots, documents).

## How this repo works

| File | Purpose |
|---|---|
| [`AGENTS.md`](AGENTS.md) | The operating guide every AI agent (and the owner) follows: rules, build loop, evidence and sanitization standards, Definition of Done, website spec |
| [`CLAUDE.md`](CLAUDE.md) | Same guide, for Claude Code |
| [`docs/plan/`](docs/plan/) | Research, tailored roadmap and the 10 project plans — the read-only spec |
| [`PROGRESS.md`](PROGRESS.md) | Status of every project and phase, session log, licence/​trial expiries |
| [`DECISIONS.md`](DECISIONS.md) | Deviations from the plan, with reasons |
| [`LAB-INVENTORY.md`](LAB-INVENTORY.md) | Hosts, IPs, roles, VLANs (no passwords) |
| [`projects/`](projects/) | One folder per project: scripts, configs, docs, business artifacts, evidence |
| [`site/`](site/) | The online CV website (Astro) |

**Working rules in one line each:** work only inside the lab; never invent results; no secrets in
Git or on the site; snapshot before every phase; follow the plan and log deviations; ask the owner
before paid services, real hardware, attack simulations or publishing; explain the work so the
owner can handle interviews; always present this as a home lab.

## Running the website locally

```bash
cd site
npm install
npm run dev        # http://localhost:4321
```

Build and checks: `npm run build`, `npm run check` (placeholder and alt-text checks).

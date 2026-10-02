# Halden Distribution Ltd. — Monthly IT report (2026-10)

**Prepared by:** IT · **For:** Management team · **As of:** 2026-10-02  
**Status of the lab:** the ten projects are complete **build kits** — scripts, configs, documentation and business artifacts exist, but the phases have **not been executed** in the lab yet. This report therefore says "not measured" for every operational KPI and reports the handful of numbers that can be derived from the repository itself.

> Halden Distribution Ltd. is a fictional 85-user company used for a home-lab portfolio. Every number below is labelled with where it came from; nothing is estimated.

## 1. Summary in three sentences

1. **What went well:** all ten project build kits (P1–P9 plus this governance capstone) are written, reviewable and internally consistent, with 123 automation scripts and 11 business artifacts committed.
2. **What did not:** nothing has been run in the lab yet, so no operational KPI (identity, patching, backup, service desk) has a measured value.
3. **What we need:** a decision to start lab execution and a business owner for each risk and action; until then the governance programme can only measure the repository, not the estate.

## 2. KPI table (RAG)

**Repository-derived (measured now, from this repository).** These are genuine measurements of the repository state, produced by `scripts/collect_kpis.py`; they are not lab results.

| KPI | Value | Target | RAG | Source |
|---|---|---|---|---|
| KPI-27 Projects with measured results | 0 | 10 of 10 | red | `projects/*/README.md (## Results tables)` |
| KPI-34 Projects whose README still says 'not measured' | 10 | 0 | red | `projects/*/README.md (## Results tables)` |
| KPI-28 Projects by showcase status | {'done': 0, 'in-progress': 10, 'planned': 0} | — | informational | `projects/*/showcase.md frontmatter (status)` |
| KPI-35 Projects carrying the Definition-of-Done template | 10 | 10 | green | `projects/*/README.md` |
| KPI-29 Acceptance tests not yet run | 95 | 0 | red | `projects/*/README.md (## Acceptance tests tables)` |
| KPI-25 Open Definition-of-Done items | 8 | 0 | red | `PROGRESS.md (Definition of Done table)` |
| KPI-30 Business artifacts authored (Markdown) | 61 | — | informational | `projects/*/business/*.md` |
| KPI-31 Automation scripts committed | 146 | — | informational | `projects/*/scripts/**/*.{ps1,sh,py}` |
| KPI-22 CIS IG1 implementation % | not measured % | trend up | not measured | `data/cis-ig1-safeguards.csv (after_status column)` |
| KPI-23 Safeguards with evidence present | 16 | 56 | red | `configs/cis-ig1-evidence-map.csv vs the repository` |
| KPI-18 Changes recorded | 1 | — | informational | `data/change-log.csv` |
| KPI-19 Emergency change share | 0.0 % | <= 10% | informational | `data/change-log.csv` |
| KPI-32 Changes awaiting approval (unsigned) | 1 | 0 | informational | `data/change-log.csv (approver column empty)` |
| KPI-33 Age of the oldest open change | 3 days | — | informational | `data/change-log.csv (date_raised column)` |
| KPI-26 Policies approved % | 0.0 % | 100% | red | `data/policy-register.csv` |
| KPI-24 Actions closed on time % | not measured % | >= 90% | not measured | `data/action-tracker.csv` |
| KPI-36 Open actions in the tracker | 0 | 0 | informational | `data/action-tracker.csv` |

**Lab-measured (not measured yet).** These need the lab to be executed.

| KPI | Value | Target | Where it will come from |
|---|---|---|---|
| KPI-01 MFA coverage | not measured | 100% | P2 MFA coverage report / Entra sign-in report |
| KPI-02 Leavers revoked within SLA | not measured | 100% | P2 JML audit log |
| KPI-03 Stale enabled accounts | not measured | 0 | P2 hygiene report |
| KPI-04 PingCastle risk score | not measured | <= 20 | P3 PingCastle monthly report |
| KPI-05 Endpoint compliance | not measured | >= 95% | P4 compliance report |
| KPI-06 Unsupported OS devices | not measured | 0 | P4 readiness report / P9 CMDB |
| KPI-07 Patch compliance within 14 days | not measured | >= 95% | P5 / WSUS compliance report |
| KPI-08 Open KEV vulnerabilities | not measured | 0 | P5 prioritizer dashboard |
| KPI-09 Findings overdue by tier | not measured | 0 | P5 prioritizer dashboard |
| KPI-11 High-severity alerts | not measured | trend | P7 Wazuh dashboard |
| KPI-13 MTTD / MTTR | not measured | trend down | P7 IR register |
| KPI-14 Uptime of critical services | not measured | >= 99.5% | Uptime Kuma (P9) |
| KPI-15 Restore tests passed | not measured | 100% | P8 restore-test history |
| KPI-16 SLA compliance | not measured | >= 90% | P9 GLPI reporting |
| KPI-20 Change success rate | not measured | >= 95% | change log + P9 incidents |
| KPI-21 Unauthorised changes detected | not measured | 0 | P9 config-as-code drift report |

The KPI definitions (formula, target, RAG rule, owner) are in `configs/kpi-definitions.csv`; the snapshot behind this table is `reports/kpi-snapshot-2026-10-02.json`.

## 3. Notable events and business impact

No incidents, outages or major changes have occurred: the lab has not been executed. The one governance event is the programme itself.

| Date | Event | Services/users affected | Business impact | Reference |
|---|---|---|---|---|
| 2026-09-29 | Change raised: P1 core infrastructure build (Tier 0) | 85 users (all) | None yet — awaiting approval | `data/change-log.csv` (CHG-2026-001) |

Changes recorded in the register: **1** (of which 1 awaiting approval). See section 5 of the CAB agenda for the approval workflow.

## 4. Risks and issues needing management attention

The risk register is **empty on purpose**: no risk has been formally assessed yet, and inventing plausible risks would be worse than showing the register's shape. The methodology (scoring, ownership, treatment) is documented in `business/p10-risk-register.md`. The first population will be the CIS IG1 gaps once the assessment is run.

**Decision requested:** appoint a business owner for each risk on the register and confirm whether the CIS IG1 gap-closure (the 56 safeguards not yet scored) is funded as a 90-day roadmap or deferred.

## 5. Actions

The action tracker is empty. Actions appear when the project reviews, findings registers, tabletop exercise and DR drill produce them (P3, P7, P8, P10); none of those have run yet.

## 6. Next month's plan

- **Start lab execution at P1 Phase 1** (snapshot the DC first) so the operational KPIs can be measured and this report gains real numbers.
- **Run the CIS IG1 self-assessment** after each project completes a phase, scoring only what has evidence (`scripts/cis_assessment.py`).
- **Hold the first CAB** using the generated agenda (`scripts/change_log.py --cab-agenda`) and record real decisions.
- **Close the Control 14 gap** (security awareness training) — the largest expected gap, since no awareness programme exists yet.

---

*Generated by `projects/p10-governance/scripts/monthly_report.py`. Rendering refuses when a cited evidence file is missing, so a management report can never point at a source that does not exist.*

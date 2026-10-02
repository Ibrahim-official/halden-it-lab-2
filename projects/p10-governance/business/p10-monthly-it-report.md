# Halden Distribution Ltd. — Monthly IT report (first edition)

**Period:** 2026-10 · **Prepared by:** IT · **For:** the management team · **Date:** 2026-10-02
**Status of the programme:** build kits complete, lab execution pending

> Halden Distribution Ltd. is a **fictional** 85-user company used for a home-lab portfolio. Every
> number below is labelled with where it came from. Operational KPIs that need a running lab are
> reported as **not measured** — this is the honest first edition, not a mocked-up report. The
> repository-derived figures are real measurements of the project repository at the date above and
> can be reproduced with the command named beside them.

## 1. Summary in three sentences

1. **What went well:** all ten project build kits — P1 to P9 plus this governance capstone — are
   written, internally consistent and reviewable as code, with a governance process (assessment,
   change control, policy pack, reporting) wrapped around them.
2. **What did not:** nothing has been executed in the lab yet, so no operational KPI (identity,
   patching, backup, service desk) has a measured value — that is the whole of what is missing.
3. **What we need:** a decision to begin lab execution, and a named **business** owner for each risk
   and action once they exist.

## 2. KPI table

### 2a. Repository-derived (real measurements of the repository today)

These are genuine counts and states of the project repository. They are **not** lab results. Reproduce
them with `python3 projects/p10-governance/scripts/collect_kpis.py`.

| KPI | Value | Source |
|---|---|---|
| Projects with measured results | 0 of 10 | `projects/*/README.md` results tables |
| Projects whose README still says "not measured" | 10 of 10 | `projects/*/README.md` |
| Projects by showcase status | 0 done · 10 in-progress · 0 planned | `projects/*/showcase.md` frontmatter |
| Acceptance tests not yet run | 95 of 97 recorded ("not run") | `projects/*/README.md` acceptance-test tables |
| Open Definition-of-Done items | 8 | `PROGRESS.md` DoD table |
| Business artifacts authored (Markdown) | 61 across the ten projects | `projects/*/business/*.md` |
| Automation scripts committed | 146, with a Python test suite in 9 of 10 projects | `projects/*/scripts/**` |
| CIS IG1 safeguards with expected evidence present | 16 of 56 | `configs/cis-ig1-evidence-map.csv` |
| CIS IG1 safeguards scored | 0 of 56 | `data/cis-ig1-safeguards.csv` |
| Changes recorded | 1 (awaiting approval) | `data/change-log.csv` |
| Emergency change share | 0% (no emergency changes recorded) | `data/change-log.csv` |
| Age of the oldest open change | 3 days | `data/change-log.csv` |
| Policies approved | 0 of 10 | `data/policy-register.csv` |
| Open actions in the tracker | 0 (none recorded yet) | `data/action-tracker.csv` |

### 2b. Lab-measured (not measured yet)

These need the lab to be executed. They are the numbers management will care about most, and they
are deliberately blank rather than estimated.

| KPI | Value | Target | Where it will come from |
|---|---|---|---|
| MFA coverage | not measured | 100% | P2 MFA coverage report |
| Leavers revoked within SLA | not measured | 100% | P2 JML audit log |
| Stale enabled accounts | not measured | 0 | P2 hygiene report |
| PingCastle risk score | not measured | ≤20 | P3 monthly run |
| Endpoint compliance | not measured | ≥95% | P4 compliance report |
| Unsupported OS devices | not measured | 0 | P4 / P9 |
| Patch compliance within 14 days | not measured | ≥95% | P5 / WSUS |
| Open known-exploited vulnerabilities | not measured | 0 | P5 dashboard |
| High-severity alerts | not measured | trend | P7 Wazuh |
| Uptime of critical services | not measured | ≥99.5% | Uptime Kuma (P9) |
| Restore tests passed | not measured | 100% | P8 restore-test history |
| Service desk SLA compliance | not measured | ≥90% | P9 GLPI |
| Change success rate | not measured | ≥95% | change log + P9 incidents |
| Unauthorised changes detected | not measured | 0 | P9 config drift report |

## 3. Notable events and business impact

| Date | Event | Services/users affected | Business impact | Reference |
|---|---|---|---|---|
| 2026-09-29 | Change raised: P1 core infrastructure build (Tier 0) | 85 users (all) | None yet — awaiting approval | `data/change-log.csv` CHG-2026-001 |

No incidents, outages or completed major changes have occurred, because the lab has not been executed.

## 4. Risks and issues needing management attention

The risk register is **empty on purpose**: no risk has been formally assessed, and inventing
plausible risks would be worse than showing the register's shape. The methodology (scoring, ownership,
treatment) is documented in `business/p10-risk-register.md`. The register is first populated from the
CIS IG1 gaps once the assessment runs.

**Decision requested today:** appoint a **business** owner for each risk once the register is
populated, and confirm whether closing the CIS IG1 gaps is funded as a 90-day roadmap or deferred.
The recommended treatment for the largest expected gap — security awareness training (Control 14, 8
safeguards) — is to **fund** a low-cost training platform and phishing simulation, because the same
controls are what the cyber-insurance questionnaire asks about.

## 5. Actions

| Action | Owner | Due | Status | Notes |
|---|---|---|---|---|
| Begin lab execution at P1 Phase 1 | IT Lead | next month | upcoming | A programme action; tracked in `PROGRESS.md` |

The consolidated action tracker (`data/action-tracker.csv`) is empty: actions appear when the project
reviews, findings registers, tabletop exercise and DR drill produce them (P3, P7, P8, P10), and none
of those have run yet.

## 6. Next month's plan

- **Start lab execution at P1 Phase 1**, snapshotting DC01 first, so the operational KPIs gain real
  values.
- **Run the CIS IG1 self-assessment** after each project completes a phase, scoring only what has
  evidence (`scripts/cis_assessment.py`).
- **Hold the first CAB** using the generated agenda (`scripts/change_log.py --cab-agenda`) and record
  real decisions.
- **Close the Control 14 gap** — the largest expected gap, since no awareness programme exists.
- **Produce the second monthly report** so the KPI table finally has a trend column.

---

*Generated from the governance pipeline (`scripts/monthly_report.py`) with the structure in
`configs/report-template.md`. A report with a cited evidence file missing will not render — the
tooling refuses, so no management report can point at a source that does not exist.*

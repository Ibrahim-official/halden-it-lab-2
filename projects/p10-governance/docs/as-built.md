# P10 as-built — Halden Distribution Ltd. IT governance

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> governance configuration from [`00-design.md`](./00-design.md), written so that *measured* facts
> can be pasted straight in. Nothing here is presented as a captured result: the **Verified ☐**
> column stays empty until the matching script has actually been run and its output seen.
>
> **How to finish this document:** run `scripts/cis_assessment.py`, `scripts/evidence_index.py` and
> `scripts/collect_kpis.py`, then paste the real outputs into the tables below, replacing *(designed)*
> with *(verified)* and ticking Verified. Sanitize anything that leaves `evidence/raw/` first
> (AGENTS.md Section 4.6).

## 1. Documents and tools *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Assessment framework | CIS Controls v8.1, Implementation Group 1 — 56 safeguards | ☐ |
| Scoring scale | 0 not implemented · 1 partial · 2 implemented on some systems · 3 fully implemented and evidenced | ☐ |
| Evidence rule | a score of 3 requires a named evidence source that resolves to a real file; enforced in code | ☐ |
| Change types | standard · normal · emergency | ☐ |
| CAB cadence | weekly, 15 minutes | ☐ |
| Policy pack | ten policies, 1–2 pages each, version `v0.1`, owner IT Lead | ☐ |
| Report frequency | monthly, 2 pages maximum | ☐ |
| Repository root | `projects/p10-governance` | ☐ |
| Field technology | plain Python 3 (standard library), no external dependency | ☐ |

## 2. CIS IG1 scope *(designed)*

| Metric | Designed value | Verified |
|---|---|---|
| Safeguards in scope | 56 | ☐ |
| Controls covered | 1–12, 14, 15, 17 | ☐ |
| Controls with no IG1 safeguards (excluded) | 13, 16, 18 | ☐ |
| Safeguards already scored | 0 (assessment not run) | ☐ |
| Expected evidence artifacts present today | 16 of 56 (see §7) | ☐ |
| Percent implemented (before) | not measured | ☐ |
| Percent implemented (after) | not measured | ☐ |
| Primary gap | Control 14 security awareness (8 safeguards, no programme exists) | ☐ |

## 3. Change register *(designed)*

| Fact | Designed value | Verified |
|---|---|---|
| Register file | `data/change-log.csv` | ☐ |
| Change records | 1 seeded (CHG-2026-001, copied from P1's change record) | ☐ |
| Awaiting approval | 1 | ☐ |
| Approved | 0 — approvals are recorded only after a real review | ☐ |
| Emergency share | 0% | ☐ |
| Oldest open change | 3 days at build time (CHG-2026-001, raised 2026-09-29) | ☐ |
| Validation state | 0 errors, 0 warnings (`scripts/change_log.py --validate`) | ☐ |
| Rollback rule enforced | yes — a change with no rollback plan errors | ☐ |

## 4. Policy pack *(designed)*

| Fact | Designed value | Verified |
|---|---|---|
| Policies authored | 10 | ☐ |
| Version | v0.1 | ☐ |
| Approved | 0 — every approval block is visibly unsigned | ☐ |
| Acknowledged | not measured — no staff have read them yet | ☐ |
| Review date | 2027-10-02 (12 months from authoring) | ☐ |
| Exceptions register | `business/p10-policy-pack.md` §Exceptions (empty until real exceptions are granted) | ☐ |

## 5. KPI pipeline *(designed)*

| Fact | Designed value | Verified |
|---|---|---|
| KPI definitions | 27 (`configs/kpi-definitions.csv`) | ☐ |
| Repository-derived KPIs | 17 — real measurements of this repository | ☐ |
| Lab-measured KPIs | 16 — `not measured` until the lab runs | ☐ |
| Snapshot output | `reports/kpi-snapshot-<date>.json` and `.md` | ☐ |
| History file | `data/kpi-history.csv` (appended each period) | ☐ |
| Dashboard data | `reports/governance-dashboard.json` | ☐ |
| Report refusal rule | rendering stops if any cited evidence file is missing | ☐ |

## 6. Risk register and action tracker *(designed)*

| Fact | Designed value | Verified |
|---|---|---|
| Risk register rows | 0 (empty on purpose; methodology documented) | ☐ |
| Risk owner rule | `business_owner` must be a business owner, never IT | ☐ |
| Treatment options | mitigate · accept · transfer · avoid | ☐ |
| Scoring | likelihood (unlikely/possible/likely) × impact (minor/moderate/major) | ☐ |
| Action tracker rows | 0 (empty until reviews produce actions) | ☐ |
| On-time target | ≥ 90% of actions closed on or before their due date | ☐ |

## 7. Evidence index *(designed state at build time)*

The evidence index maps each safeguard to the artifact that will evidence it. The counts below are
what the repository contained when this document was written; re-run
`scripts/evidence_index.py` to refresh them.

| Source project | Safeguards expected to evidence | Artifacts present today |
|---|---|---|
| P1 | 7 | 5 |
| P2 | 5 | 1 |
| P3 | 4 | 3 |
| P4 | 8 | 1 |
| P5 | 4 | 1 |
| P6 | 5 | 1 |
| P7 | 5 | 0 |
| P8 | 4 | 1 |
| P9 | 7 | 1 |
| P10 | 7 | 7 |
| Gap — 90-day roadmap (Control 14) | 8 | 0 |
| **Total** | **56 mappings** | **16 of 56 (29%)** |

> The 29% figure is the share of expected evidence **artifacts that exist in the repository**, not a
> CIS implementation score. It is low because nothing has been executed in the lab; the artifacts are
> the sanitized outputs that a real run produces. It is reported here, clearly labelled, because it
> is a genuine repository measurement — and it is *not* the headline CIS metric.

## 8. Deliverables *(designed)*

| Deliverable | Path | Verified |
|---|---|---|
| Executive summary (1 page) | `business/p10-exec-summary.md` | ☐ |
| Policy pack (governance framework) | `business/p10-policy-pack.md` | ☐ |
| CIS IG1 assessment report (structure) | `business/p10-cis-ig1-assessment-report.md` | ☐ |
| Monthly IT report (first edition) | `business/p10-monthly-it-report.md` | ☐ |
| CAB minutes | `business/p10-cab-minutes.md` | ☐ |
| Risk register and methodology | `business/p10-risk-register.md` | ☐ |
| "State of IT" talk notes | `business/p10-state-of-it-talk.md` | ☐ |
| Governance architecture diagram | `docs/diagrams/p10-architecture.svg` (+ `.drawio`) | ☐ |
| CIS IG1 before/after chart (empty template) | `docs/diagrams/p10-cis-ig1-chart-template.svg` | ☐ |

## 9. Known gaps and accepted limitations

| Item | Note |
|---|---|
| Nothing is scored yet | The assessment measures the *lab*, and the lab has not been executed. Every score is blank by design. |
| Control 14 (security awareness) | No awareness programme exists in the build kit. It is the largest expected gap and the first item on the 90-day roadmap. |
| Framework version | P10 assesses v8.1. The focus of CIS work in the wider industry is v8.1 today; v8 had 153 safeguards versus v8.1's 171. The workbook records the version so a future re-baseline is explicit. |
| KPI history is one period | Trend columns are empty until at least two monthly runs exist. |
| Policy approval is simulated | The fictional Managing Director "approves" in the lab. This is labelled as a lab decision, not a real customer sign-off (AGENTS.md R8). |

## 10. Next steps

1. Run the CIS IG1 assessment after each project completes a phase, scoring only what has evidence.
2. Hold the first CAB using `scripts/change_log.py --cab-agenda` and record real decisions.
3. Populate the risk register from the P3/P4/P5/P8 findings once those projects run.
4. Produce the second monthly report so trends become meaningful.

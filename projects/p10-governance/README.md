# P10: IT Governance Capstone — CIS IG1 Scorecard, Change Control, Policy Pack and Management Reporting

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd.").
> Presented as a home lab on the portfolio site — never as employment experience.
> The company, its staff and its approvals are **fictional**; the configurations, scripts and
> measurements are real. See [`data/README.md`](./data/README.md).

**Status:** build kit complete — **lab execution pending** · **Build order:** 10 of 10 · **Depends on:** P1–P9 (it measures and reports on them)
**Plan:** [`docs/plan/P10-governance-cis-ig1-change-reporting.md`](../../docs/plan/P10-governance-cis-ig1-change-reporting.md) · **Design:** [`docs/00-design.md`](./docs/00-design.md) · **As-built:** [`docs/as-built.md`](./docs/as-built.md) · **Site page source:** [`showcase.md`](./showcase.md)

## Problem

Nine good technical projects are worthless if nobody can answer the questions management actually
asks: *are we secure, are we getting better, what does IT need money for, and what changed last week —
and who approved it?* At Halden, IT work happened but was invisible. Changes were made on a Friday
afternoon without telling anyone. There were no written policies, which the cyber-insurance renewal
questionnaire now asks for, and no baseline against which "better" could even be measured.

CIS describes **IG1 (56 safeguards)** as essential cyber hygiene and an emerging minimum standard for
every enterprise, aimed at small businesses with limited IT and security expertise
(`docs/plan/00-research-and-selection.md`). Halden had no way to know where it stood against it — and
a score nobody can evidence is not a score.

## What I built

- **A CIS Controls v8.1 IG1 self-assessment** covering all **56** safeguards across 15 controls,
  scored before and after, where a score of "fully implemented" **requires a named evidence source** —
  enforced in code, not by trust.
- **An evidence map** that traces every safeguard to the artifact from P1–P9 that will evidence it, and
  an indexer that checks which of those artifacts actually exist today.
- **ITIL-style change management**: standard / normal / emergency types, a risk-classified RFC, a
  weekly CAB agenda generated from the register, a change calendar with freeze periods, and a
  retrospective for emergency changes. **A change with no rollback plan cannot be approved.**
- **A ten-policy IT policy pack** written for a small company to actually adopt — 1–2 pages each,
  plain English, with an owner, a version, a review date, an acknowledgement process and an exceptions
  register.
- **A KPI pipeline** (27 definitions) that separates **repository-derived** KPIs — genuine, reproducible
  measurements of this repository — from **lab-measured** KPIs, which report as `not measured` until
  the lab has run and are never estimated.
- **A monthly IT report generator** that **refuses to render** if any evidence file it would cite is
  missing, so a management report can never point at a source that does not exist.
- **A governance dashboard data generator** producing JSON for a static dashboard (no backend, no live
  system exposed).
- **A risk register and consolidated action tracker**, with a documented methodology and the rule that
  a business risk is owned by a **business** owner, never by IT.
- **A 10-minute "State of IT" talk outline** with speaker notes, a costed 90-day roadmap and a decision
  request written for a non-technical audience.
- **Lab collection tooling**: a read-only PowerShell collector for the AD evidence, a bash pre-flight
  gate, and a bash evidence collector — all lab-guarded and all writing nothing back to the lab.

## Architecture

![P10 governance architecture](docs/diagrams/p10-architecture.svg)

The governance loop: business objectives set the controls and policy; the nine projects supply
evidence; the evidence is scored against CIS IG1; gaps become risks and roadmap items; change
management controls how the environment changes; a KPI dashboard and monthly report turn results into
a management decision; and management review feeds improvement back into the controls. Every stage
names its data source, and the diagram carries a footnote stating that Halden is fictional.

## How to reproduce

Work through these in order. Everything runs from the repository root; the scripts write only inside
`projects/p10-governance/`. The two lab-facing scripts are guarded and abort outside
`ad.halden.internal` / a host carrying `/etc/halden-lab`.

| Order | Where | Script / document | Does |
|---|---|---|---|
| 0 | Anywhere | `docs/00-design.md` | The design: why governance is the capstone, the IG1 scope decision, the evidence chain, the KPI set |
| 1 | Governance workstation | `scripts/cis_assessment.py` | Builds the CIS IG1 assessment report from `data/cis-ig1-safeguards.csv`; refuses a `3` with no evidence |
| 2 | Governance workstation | `scripts/evidence_index.py` | Maps each safeguard to its expected artifact and reports which exist today |
| 3 | Halden lab host | `scripts/00-governance-preflight.sh` | Read-only pre-flight: are the P9 services up, are the inputs present |
| 4 | DC01 / RSAT | `scripts/00-Collect-GovernanceEvidence.ps1` | Read-only: collects account, dormant-account, privileged-group and password-policy evidence |
| 5 | Halden lab host | `scripts/01-collect-kpi-evidence.sh` | Copies a project's KPI evidence into `evidence/raw/`, then `evidence/public/` after sanitization |
| 6 | Governance workstation | `scripts/collect_kpis.py` | Computes the repository-derived KPIs and writes the monthly snapshot |
| 7 | Governance workstation | `scripts/change_log.py` | Validates the change register and generates the CAB agenda |
| 8 | Governance workstation | `scripts/monthly_report.py` | Renders the monthly report; refuses if a cited evidence file is missing |
| 9 | Governance workstation | `scripts/governance_dashboard.py` | Produces the static dashboard data (JSON) |
| 10 | Governance workstation | `python3 scripts/tests/test_*.py` | Runs the unit tests (65 tests) |

**Prerequisites:** Python 3.11+ (standard library only — no third-party packages). PowerShell 7 + RSAT
for the AD collector. The lab scripts additionally need the P9 stack running on OPS01 and a Halden lab
host.

**Snapshot before any lab-facing step** (`snap-p10-<change>-before`). **Rollback:** everything this
project generates lives in `projects/p10-governance/` — delete the generated files in `reports/` and
restore `data/*.csv` from Git. The lab collectors are read-only and have nothing to roll back. Scoring
changes are plain CSV edits and revert with `git checkout data/cis-ig1-safeguards.csv`.

## Results

**Not measured yet.** This build kit is written but not yet executed in the lab, so this table is
deliberately empty rather than filled with plausible-looking numbers. Each row is a real measurement
with a file in `evidence/public/` as its source, added when the assessment and the phases run.

| Metric | Before | After | Source |
|---|---|---|---|
| CIS IG1 implementation, % evidenced (56 safeguards) | not measured | not measured | — |
| CIS IG1 safeguards scored | not measured | not measured | — |
| Safeguards at full score (3) | not measured | not measured | — |
| Change success rate | not measured | not measured | — |
| Emergency change share | not measured | not measured | — |
| Unauthorised changes detected (config drift) | not measured | not measured | — |
| Actions closed on time, % | not measured | not measured | — |
| Policies approved and acknowledged, % | not measured | not measured | — |

### Repository-derived counts (a separate, reproducible class)

These are **not** lab results. They are genuine measurements of this repository, computed by running
`python3 projects/p10-governance/scripts/collect_kpis.py` from the repository root, and they change as
the repository changes. They are listed separately so nobody can mistake them for CIS or KPI results.

| Repository-derived count | Value at 2026-10-02 | How it is derived |
|---|---|---|
| CIS IG1 safeguards in the assessment input | 56 | rows in `data/cis-ig1-safeguards.csv` |
| Safeguards scored (before / after) | 0 / 0 | non-empty `before_status` / `after_status` cells |
| Safeguards whose expected evidence artifact exists today | 16 of 56 | `configs/cis-ig1-evidence-map.csv` joined against the repository |
| Projects with any measured result | 0 of 10 | `projects/*/README.md` results tables |
| Projects by showcase status | 0 done · 10 in-progress · 0 planned | `projects/*/showcase.md` frontmatter |
| Acceptance tests recorded / still "not run" | 97 / 95 | `projects/*/README.md` acceptance-test tables |
| Open Definition-of-Done items | 8 | `PROGRESS.md` DoD table |
| Business artifacts authored (Markdown) | 61 | `projects/*/business/*.md` |
| Automation scripts committed | 146 | `projects/*/scripts/**` (9 of 10 projects ship a Python test suite) |
| Change records / awaiting approval | 1 / 1 | `data/change-log.csv` |
| Policies registered / approved | 10 / 0 | `data/policy-register.csv` |
| Actions open in the tracker | 0 | `data/action-tracker.csv` |

## Acceptance tests

| Test | Expected | Actual | Pass |
|---|---|---|---|
| Run `cis_assessment.py --open-errors` on the shipped workbook | Exit 0: 56 unique safeguards, no score outside 0–3 | not run | ☐ |
| Score a safeguard 3 with no evidence source | Rejected with a clear error | not run | ☐ |
| Score a safeguard 3 citing a repository file that does not exist | Rejected: the evidence source must resolve to a real file | not run | ☐ |
| `monthly_report.py` with a cited evidence file removed | Refuses to render, names the missing file | not run | ☐ |
| `change_log.py --validate` with a change missing its rollback plan | Validation error; the change cannot be approved | not run | ☐ |
| `collect_kpis.py` with the lab not executed | Every lab-measured KPI reads "not measured", never a number | not run | ☐ |
| Run the unit tests `python3 scripts/tests/test_*.py` | All 65 pass | not run | ☐ |
| Score all 56 safeguards from real evidence | The report prints a real before/after percentage | not run | ☐ |
| CAB agenda generated from the register | Decisions table shows every change as "pending" | not run | ☐ |

## Business deliverables

| Artifact | For | File |
|---|---|---|
| Executive summary (1 page) — IT at a glance | Management / board | `business/p10-exec-summary.md` |
| IT policy pack — ten short policies for adoption, with an acknowledgement process and exceptions register | Management approval; all staff | `business/p10-policy-pack.md` |
| CIS IG1 self-assessment report — the structure, with the status column empty and how it will be filled | Management / insurer questionnaire | `business/p10-cis-ig1-assessment-report.md` |
| Monthly IT report — the real first edition, repository-derived values only | Management monthly review | `business/p10-monthly-it-report.md` |
| CAB minutes — agenda, decisions and actions, with decisions marked pending | The change control audit trail | `business/p10-cab-minutes.md` |
| Risk register and methodology — empty rows, documented scoring and ownership rules | Management risk decisions | `business/p10-risk-register.md` |
| "State of IT" talk outline — 12 slides with speaker notes and a costed 90-day roadmap | Management briefing / recorded talk | `business/p10-state-of-it-talk.md` |

## Lessons learned

- **Governance is what makes the other nine projects credible.** A technical build with no scorecard,
  no change record and no report is a hobby. The moment a number has to survive "where did that come
  from?", the work becomes accountable — and that is the difference between a lab and an IT function.
- **Tooling is the honest way to enforce honesty.** Writing the rule "a score of 3 requires evidence"
  into `cis_assessment.py`, and "a report cannot cite a missing file" into `monthly_report.py`, removes
  the temptation that a spreadsheet template always leaves open.
- **The hardest part was deciding what *not* to measure.** A KPI nobody can act on is noise. Splitting
  the set into repository-derived (real today) and lab-measured (honestly blank) was the single most
  useful design decision in this project.
- **A policy pack is a design exercise, not a writing exercise.** Cutting ten policies to 1–2 pages
  each, with an owner and a review date, was harder than writing long ones and far more likely to
  actually be read.
- **Approval blocks should stay unsigned.** It was tempting to fill the CAB and policy approvals with a
  plausible signature. Leaving them visibly empty, with the reason written down, is the more
  professional artefact.

## Interview notes

**"How do you know your controls are actually working?"** Not by trusting the design — by requiring
evidence. Every safeguard scored 3 names a file that proves it, the assessment tool rejects a 3 with
no source, and the monthly report will not render if a cited evidence file is missing. On top of that,
controls are re-assessed quarterly and the P9 config drift check catches a control that quietly
stopped working, because a configuration change with no matching approved change record is treated as
an unauthorised change.

**"How do you get management to care about CIS controls?"** Translate them into their language. A
manager does not care about safeguard 14.2; they care that the insurer's questionnaire asks about
security awareness, that phishing is the most likely way they get breached, and that the fix costs a
training platform rather than a new server. So the report gives them one page: a RAG status, the top
risks with a **recommended decision**, and a costed roadmap with the consequence of deferral. The
framework is the *how*; the board buys the *risk reduction*.

**"What is the difference between a KPI and a KRI?"** A KPI measures how well a process performs
against a target — SLA compliance at 92% against a 90% target. A KRI measures exposure that predicts
trouble: open known-exploited vulnerabilities, the emergency-change share, stale privileged accounts.
KPIs tell you whether you are doing the work well; KRIs warn you that you are about to have a bad
month. This project reports both, and the risk register is where the KRIs get a named owner and a
treatment decision.

**"You scored yourself at X% — prove it."** This is the question the whole project is built to answer.
Pick any safeguard and I will show you the scored row, the evidence source named in it, and the file
itself. Safeguards I could not evidence are not scored at all — Control 14 (security awareness) is the
honest example, because our build kit has no awareness programme, so it stays a roadmap gap rather
than a claimed control. An honest lower number is worth more than an inflated one, and the tooling
makes the inflated version harder to produce than the honest one.

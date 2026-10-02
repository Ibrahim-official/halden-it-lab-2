# Runbook — Perform the quarterly CIS IG1 self-assessment

**Applies to:** the governance workstation · **Time:** 2–4 hours (first run longer) · **Owner:** IT Lead · **Runs:** quarterly, and after any major change

The self-assessment is the monthly report's headline. It is quarterly because scoring honestly takes
real effort, and because controls change slowly. The one rule that matters: **only count what has
evidence**. An honest 70% beats an inflated 95%, and a probing interviewer or auditor will find the
difference (plan §8).

## Before you start

- Snapshot the clock: note the assessment date. The report is stamped with it.
- Have the projects' `evidence/public/` folders and `README.md` results tables open — these are the
  raw material.

## Steps

1. **Read the scope.** Open `docs/00-design.md` §4. It records why the scope is IG1 (56 safeguards),
   which controls have no IG1 safeguards (13, 16, 18), and why Control 14 is included but expected to
   score low.

2. **Refresh the evidence index.** See what evidence actually exists right now:
   ```bash
   cd projects/p10-governance
   python3 scripts/evidence_index.py
   ```
   Read `reports/cis-evidence-index-<date>.md`. Anything marked *expected - not present* cannot
   support a score.

3. **Score the workbook, safeguard by safeguard.** Open `data/cis-ig1-safeguards.csv`.
   - `before_status` — the inherited Halden state, taken from the problem statement in that
     safeguard's source project (for example, before P2 there was no MFA, so 6.3 is `0`).
   - `after_status` — the state today, **only** counting what the evidence index shows as present.
   - `evidence_source` — the file that proves it, relative to the project that produced it.
   - `owner` and `target_date` — for anything still below 3.

   Score honestly:
   | Score | When |
   |---|---|
   | 0 | nothing is in place |
   | 1 | partly in place, or documented but not applied |
   | 2 | in place on some systems, not all |
   | 3 | fully in place **and** evidenced |

4. **Let the tool check your work.**
   ```bash
   python3 scripts/cis_assessment.py --open-errors --gaps-csv reports/cis-ig1-gaps-<date>.csv
   ```
   It will refuse any `3` with no evidence source, reject an out-of-scale score, and check the
   workbook still holds 56 unique safeguards. Fix every error.

5. **Read the gap list.** Every safeguard below 3 in `reports/cis-ig1-gaps-<date>.csv` becomes:
   - a **risk** in `data/risk-register.csv` if it carries real business exposure, with a **business**
     owner; and
   - a **roadmap item** in the "State of IT" talk if it cannot be closed inside 90 days.

6. **Update the chart.** `docs/diagrams/p10-cis-ig1-chart-template.svg` is an **empty** before/after
   template. When the scores are real, a script (or a careful manual pass) fills the bars from the
   `after_status` column per control. Until then it stays empty — it is never given placeholder
   numbers.

7. **Publish the report.** `reports/cis-ig1-assessment-<date>.md` is the assessment; convert it to
   PDF for the website via the central pipeline, and use it in the monthly report.

## Done when

- `python3 scripts/cis_assessment.py --open-errors` exits 0.
- Every safeguard scored 3 names a file that exists in the repository.
- Every remaining gap has an owner and a target date, or a documented reason it cannot.
- The report's headline percentages come from the tool's output, not from a spreadsheet by hand.

**Rollback:** scoring is just CSV edits — `git checkout data/cis-ig1-safeguards.csv` reverts it. The
generated reports in `reports/` are disposable and can be re-generated.

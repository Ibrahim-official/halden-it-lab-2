# Runbook — Produce the management report

**Applies to:** the governance workstation · **Time:** 30 minutes · **Owner:** IT Lead · **Runs:** monthly, before the management meeting

The report is two pages, and its job is to end in a **decision request**. A page of technical numbers
with no "so what" fails (plan §8). This runbook assumes the monthly governance cycle has already run
and the KPI snapshot exists.

## Before you start

- The month's snapshot: `reports/kpi-snapshot-<YYYY-MM>.json`.
- The month's evidence: everything you collected in the monthly cycle, sanitized into
  `evidence/public/`.
- The risk register and action tracker, current as of today.

## Steps

1. **Generate the report.**
   ```bash
   cd projects/p10-governance
   python3 scripts/monthly_report.py --period <YYYY-MM>
   ```
   **If it refuses to render**, a cited evidence file is missing. Do not reach for `--allow-missing`
   first: either the evidence has not been produced yet (then the KPI is *not measured* and the
   definition should say so), or a path is wrong. Fix the cause.

2. **Fill the parts that need judgement.** The script writes the structure and the KPI tables. You
   write, in plain business language:
   - **Section 1 — three sentences:** what went well, what did not, what we need.
   - **Section 3 — notable events:** incidents, major changes, outages, with their business impact (not
     their technical detail).
   - **Section 4 — the decision request.** Every risk needs a **recommended decision**
     (accept / mitigate / fund / defer), not just a description.
   - **Section 6 — next month's plan:** up to five items, each with a business reason.

3. **Check it as a manager would.**
   - Can a non-technical reader understand the summary in 30 seconds?
   - Is every number either a real measurement with a source, or clearly labelled *not measured*?
   - Is there exactly one clear ask, or a small number of clear asks?
   - Are the risk owners business people, not IT?

4. **Add the risk heat map** (when the register has real risks): likelihood × impact grid, with the
   register IDs plotted. The register methodology is in `business/p10-risk-register.md`.

5. **Send it before the meeting**, ideally 24 hours ahead, so the meeting is a decision rather than a
   briefing.

6. **Record the decisions.** Management's decisions become actions in `data/action-tracker.csv` with
   an owner and a due date. Next month's report opens by reporting on them — that is what makes the
   report a cycle rather than a broadcast.

## Done when

- `reports/monthly-it-report-<month>.md` renders with no missing-evidence warning.
- Section 4 contains at least one recommended decision, or explicitly says none is needed.
- Every action from last month's report appears in this month's action list with a status.

**Rollback:** the report is a generated file in `reports/`. Delete it and re-run the generator; no
lab system is affected.

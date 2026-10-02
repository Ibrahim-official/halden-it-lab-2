# Runbook — Run the monthly governance cycle

**Applies to:** the governance workstation (any host with the repo checked out) · **Time:** about 60 minutes · **Owner:** IT Lead · **Runs:** monthly

The monthly cycle turns raw outputs from P1–P9 into the numbers management sees. It is the routine
that makes P10 a process rather than a one-off report. **Nothing in this runbook changes a lab
system** — the only scripts that touch the lab are read-only collectors, and they are guarded.

## Before you start

- Confirm the mode. In **Mode A** you run everything and paste the output back. In **Mode B** the
  agent runs it, but only against hosts listed in `LAB-INVENTORY.md`.
- The month being reported (`<YYYY-MM>`).
- Last month's snapshot, so trends can be computed: `reports/kpi-snapshot-<previous>.json`.

## Steps

1. **Pre-flight (lab host only).** On a Halden lab host carrying `/etc/halden-lab`, confirm the
   services the KPIs read from are up:
   ```bash
   projects/p10-governance/scripts/00-governance-preflight.sh
   ```
   Fix any FAIL before continuing. The script changes nothing.

2. **Collect the Windows/AD evidence.** On DC01 (or a management workstation with RSAT):
   ```powershell
   .\projects\p10-governance\scripts\00-Collect-GovernanceEvidence.ps1 -StaleDays 45 -Verbose
   ```
   This is read-only. It writes account, dormant-account, privileged-group and password-policy CSVs
   into `projects/p10-governance/evidence/raw/`.

3. **Collect the Linux/service evidence.** For each lab-measured KPI with a fresh export (GLPI SLA
   report, restore-test result, patch compliance), copy it in:
   ```bash
   projects/p10-governance/scripts/01-collect-kpi-evidence.sh --source ~/exports/glpi-sla-<month>.csv --kpi KPI-16
   ```
   It lands in `evidence/raw/`. **Sanitize it** (AGENTS.md 4.6) then re-run with `--publish` to place
   a copy in `evidence/public/`.

4. **Run the repository-derived collector.** This computes the numbers that describe the repository
   itself — project readiness, evidence coverage, change and policy counts:
   ```bash
   cd projects/p10-governance
   python3 scripts/collect_kpis.py
   ```
   It writes `reports/kpi-snapshot-<date>.json` and `.md`, and appends the period to
   `data/kpi-history.csv`.

5. **Enter the lab-measured values by hand.** Open `data/kpi-history.csv` and fill the lab-measured
   rows for the period **only from the evidence files** you collected in steps 2 and 3. Do not
   estimate: if a value is missing, leave it as `not measured` and note why. This is the one step
   that needs a human, because a person must decide that the evidence really shows the value.

6. **Refresh the evidence index** (so the CIS coverage count is current):
   ```bash
   python3 scripts/evidence_index.py
   ```

7. **Re-run the CIS assessment** if any safeguard's evidence now exists:
   ```bash
   python3 scripts/cis_assessment.py --open-errors
   ```
   Update `data/cis-ig1-safeguards.csv` scores first; the tool will refuse a 3 with no evidence.

8. **Build the management report and dashboard data.**
   ```bash
   python3 scripts/monthly_report.py --period <YYYY-MM>
   python3 scripts/governance_dashboard.py
   ```
   If the report refuses to render, a cited evidence file is missing — fix that rather than
   overriding it with `--allow-missing`.

9. **Read the report as a manager would.** Does the summary section answer "what went well, what
   didn't, what do we need"? Does every risk have a recommended decision? If not, fix it before it
   goes out.

10. **Publish nothing without a decision.** The report goes to management for their monthly review;
    risks and the roadmap become CAB and management-review items.

## Done when

- `reports/kpi-snapshot-<month>.json`, `reports/monthly-it-report-<month>.md` and
  `reports/governance-dashboard.json` exist for the month.
- Every lab-measured row in `data/kpi-history.csv` traces to a file in `evidence/public/`.
- The monthly report renders with no missing-evidence warning.

**Rollback:** this cycle writes only inside `projects/p10-governance/`. Delete the month's files in
`reports/` and restore `data/kpi-history.csv` from Git to undo it. No lab system is touched.

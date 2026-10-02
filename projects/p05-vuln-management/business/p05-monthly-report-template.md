# Halden Distribution Ltd. — monthly patch and vulnerability report

**Reporting month:** ____________ · **Prepared by:** IT · **Date:** ____________
**Distribution:** Managing Director, department heads · **Source data:** the prioritised work list
and the verification report for the month (file names below)

> **Template.** Every figure in this report must come from a real scan and a real verification run,
> with the source file named beside it. Where a figure has not been measured yet, write
> **"not measured"** — never an estimate. This is a home-lab artefact for a fictional company.

---

## 1. One-paragraph summary

> *(Two or three sentences. What changed this month, what is the biggest open risk, and what we are
> asking for. Example structure: "We closed X of the Y urgent findings; Z remain open with reasons.
> The largest remaining risk is ... . We need ... from the business.")*

## 2. Findings by tier

| Tier | Open at start of month | Closed this month | Open at end of month | Overdue (past target) |
|---|---|---|---|---|
| P0 — Emergency (3 days) | not measured | not measured | not measured | not measured |
| P1 — Critical (7 days) | not measured | not measured | not measured | not measured |
| P2 — High (30 days) | not measured | not measured | not measured | not measured |
| P3 — Medium (60 days) | not measured | not measured | not measured | not measured |
| P4 — Low (next cycle) | not measured | not measured | not measured | not measured |
| **Total** | **not measured** | **not measured** | **not measured** | **not measured** |

**Source:** `reports/prioritized-work-list-<date>.csv` (work list), `evidence/public/p05-verify-closure-result.csv` (closure).

## 3. Exploited-vulnerability (KEV) exposure

| Metric | This month | Source |
|---|---|---|
| Findings that are known-exploited (KEV) | not measured | work list, `in_kev` column |
| KEV findings on internet-exposed assets | not measured | work list, `exposure` = internet |
| KEV findings overdue | not measured | work list, `overdue` column |

## 4. Remediation performance

| Metric | Target | This month | Source |
|---|---|---|---|
| P0 remediated within 3 days | 100% of P0 | not measured | verification report |
| P1 remediated within 7 days | ≥ 95% of P1 | not measured | verification report |
| Mean time to remediate (MTTR), all urgent findings | *informational* | not measured (needs two real scans) | derived from the before/after work lists |
| Patch compliance, workstations, within 14 days | ≥ 95% | not measured | WSUS console export |
| Patch compliance, servers, within the window | ≥ 95% | not measured | WSUS console export |

## 5. Patch ring performance

| Ring | Devices | Within deadline | Failed or rolled back | Notes |
|---|---|---|---|---|
| Ring0-Pilot | not measured | not measured | not measured | |
| Ring1-Broad | not measured | not measured | not measured | |
| Ring2-Servers | not measured | not measured | not measured | |

## 6. Exceptions and accepted risks

| Metric | Count | Source |
|---|---|---|
| Live exceptions | not measured | exception register |
| Expiring in the next 30 days | not measured | exception register |
| Expired without review | not measured | exception register |

## 7. What we are asking of management

| # | Ask | From whom | Decision needed by |
|---|---|---|---|
| 1 | *(e.g. approve the Saturday maintenance window for <system>)* | Department head | |
| 2 | *(e.g. approve replacement budget for the end-of-life firewall)* | Finance / Management | |
| 3 | *(e.g. sign the risk acceptance for <finding>)* | Finance Director | |

## 8. Actions carried forward

| # | Action | Owner | Due | Status |
|---|---|---|---|---|
| 1 | | | | |

---

**How this report is produced:** the figures come from `scripts/14-weekly-report.sh`, which reads the
prioritizer's work list and the closure verification output. Nothing in it is typed in by hand except
the summary and the asks. If a number is not in the source file, it does not go in the report.

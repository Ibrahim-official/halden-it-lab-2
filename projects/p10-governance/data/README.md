# P10 input and register data

> Everything here is for the **fictional** company Halden Distribution Ltd. (85 staff) and is
> either derived from public CIS Controls v8.1 safeguard titles or is deliberately empty until a
> real assessment is run. **No measured result is stored here yet**, and no real person,
> customer or employer data appears in this folder (AGENTS.md rules R2 and R3).

## Files

| File | What it is | Status |
|---|---|---|
| `cis-ig1-safeguards.csv` | The **authoritative input** for the assessment: all **56** CIS Controls v8.1 Implementation Group 1 safeguards, with control, title, asset type, security function and an `in_scope` flag. The `before_status`, `after_status`, `evidence_source`, `owner` and `target_date` columns are **empty on purpose** and are filled only during a real assessment run. | 56 rows, statuses empty |
| `change-log.csv` | The change register the change-management script validates and the CAB agenda is built from. Seeded with **one** change record, `CHG-2026-001`, copied from [`../../p01-core-infrastructure/business/p01-change-record.md`](../../p01-core-infrastructure/business/p01-change-record.md) (its `source` column cites that file). Its approval is **pending** and unsigned. | 1 seeded row |
| `risk-register.csv` | The risk register table (header only). The methodology and the columns' meaning are in [`../business/p10-risk-register.md`](../business/p10-risk-register.md). Risk owners must be **business** owners, not IT. | empty |
| `action-tracker.csv` | The consolidated action tracker (header only): one row per action drawn from every project's reviews, findings and drills. | empty |
| `policy-register.csv` | The ten-policy register with approval and acknowledgement columns. Every `approved_by` / `approval_date` cell is **blank** until a real review happens (the approval blocks in the policy pack are visibly unsigned). | 10 policies, unsigned |
| `kpi-history-template.csv` | The shape of the monthly KPI history. The collector writes a dated snapshot to `../reports/`, and appends a new period to a real history file — this template is never overwritten. | template only |

## How this data is used

- `../scripts/cis_assessment.py` reads `cis-ig1-safeguards.csv` and builds the assessment report.
- `../scripts/change_log.py` reads `change-log.csv`, enforces the required fields and builds the CAB agenda.
- `../scripts/collect_kpis.py` reads the whole repository (including these files) and produces the repository-derived KPI snapshot.
- `../scripts/evidence_index.py` joins the safeguards to the expected artifacts in `../configs/cis-ig1-evidence-map.csv` and checks which of those artifacts actually exist today.

## Honesty notes

- The 56 safeguard **titles** are the public CIS Controls v8.1 IG1 titles. The short descriptions in
  the config files are paraphrases for internal planning; the authoritative text is the official
  CIS Controls v8.1 document or the free CIS CSAT tool.
- A status of `0`–`3` is only ever written after the matching artifact has been seen. An honest
  lower score is worth more than a generous one (plan file, Section 8).

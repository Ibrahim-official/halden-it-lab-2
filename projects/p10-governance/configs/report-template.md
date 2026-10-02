# P10 monthly IT report template

<!-- Applies to projects/p10-governance. scripts/monthly_report.py renders this structure from the
     KPI snapshot and refuses to write the report if any evidence link it would include is missing.
     Audience: the fictional Halden management team. Maximum two pages. -->

**Period:** `<YYYY-MM>` · **Prepared by:** IT · **For:** Management team
**Status of the lab:** `<one line: e.g. "projects are build kits; lab execution pending">`

## 1. Summary in three sentences

1. What went well this period: `<one sentence>`
2. What did not: `<one sentence>`
3. What we need from management: `<one sentence>`

## 2. KPI table (RAG)

| KPI | Previous | This period | Target | RAG | Source |
|---|---|---|---|---|---|
| `<kpi name>` | `<value or not measured>` | `<value or not measured>` | `<target>` | `<green/amber/red/not measured>` | `<evidence file>` |

Rules: a KPI with no real value is shown as **not measured** with a grey/blank RAG, never a guess.
Every value in the table must trace to a file in `evidence/public/` (lab-measured) or to a named
repository file (repository-derived, labelled).

## 3. Notable events and business impact

| Date | Event | Services/users affected | Business impact | Reference |
|---|---|---|---|---|
| `<date>` | `<incident, major change or outage>` | `<scope>` | `<plain English>` | `<ticket or change id>` |

## 4. Risks and issues needing management attention

For each: the risk in business language, the current rating, and a **recommended decision**.

| Risk | Rating | Recommended decision | Owner (business) |
|---|---|---|---|
| `<risk id and statement>` | `<high/medium/low>` | `<accept / mitigate / fund / defer>` | `<business owner>` |

## 5. Actions

| Action | Owner | Due | Status | Notes |
|---|---|---|---|---|
| `<action>` | `<owner>` | `<date>` | `<done / overdue / upcoming>` | `<why, if overdue>` |

## 6. Next month's plan

- `<up to five items, each with a business reason>`

---

> Honesty footer: Halden Distribution Ltd. is a fictional company used for a home-lab portfolio.
> Numbers in this report come from real lab runs or from the repository; anything not yet measured
> is written as "not measured".

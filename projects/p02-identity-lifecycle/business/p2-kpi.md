# KPI report — identity lifecycle and access governance

**Owner:** IT (Muhammad Ibrahim Akmal) · **For:** management · **Cycle:** monthly, with a quarterly access-review section
**Source:** every number below names the file that produces it. **Nothing here is filled in until it
has been measured.**

> **Status: not measured yet.** This is the reporting template the project fills in from real lab
> runs. It deliberately shows "not measured" rather than plausible-looking figures — a report that
> cannot be traced to a measurement is worse than an empty one.

---

## 1. Before and after

| # | Measure | Before | After | Better | Source |
|---|---|---|---|---|---|
| 1 | Joiner lead time (HR record to account ready) | not measured | not measured | lower | timed during the Phase 5 joiner scenario |
| 2 | Leaver revocation time (HR record to sessions revoked) | not measured | not measured | lower | the leaver audit entry and ticket timestamp |
| 3 | Enabled accounts with no HR record ("orphans") | not measured | not measured | lower | `reports/orphans.csv` |
| 4 | Enabled accounts with no logon in 90+ days | not measured | not measured | lower | `reports/identity-hygiene-<date>.csv` |
| 5 | Managed accounts' group count vs the role matrix (excess permissions) | not measured | not measured | lower | the access-review export |
| 6 | MFA coverage (% of users required to use MFA by policy) | not measured (no MFA) | not measured | higher | the CA001 policy scope and the sign-in logs |
| 7 | Blocked legacy-authentication attempts | not measured | not measured | — (context) | the Entra sign-in logs |
| 8 | CISA ScubaGear passing checks (whole tenant; aad/exo/teams) | not measured | not measured | higher | `evidence/public/p02-ph3-scubagear-before.json` and `-after.json` |
| 9 | Actions closed from the last access review | not measured | not measured | higher | `business/p2-access-review-pack.md` action tracker |

**How each number is produced** (so a reader can check it rather than trust it):

| # | Method |
|---|---|
| 1 | Record the HR change time and the account-created time from the audit log for the test joiner |
| 2 | Record the HR change time and the leaver audit entry time for the test leaver |
| 3 | Run the hygiene report over the managed accounts and count the "No HR record" findings |
| 4 | Run the hygiene report with a 90-day window and count the "Stale account" findings |
| 5 | Compare each managed account's current groups against the role matrix in the access-review export |
| 6 | Read the CA001 include/exclude scope; corroborate with a test sign-in that is challenged |
| 7 | Filter the Entra sign-in logs for the blocked legacy client app type |
| 8 | Read the ScubaGear summary JSON written by `09-Invoke-ScubaGear.ps1` |
| 9 | Count Closed rows in the action tracker against the total raised |

## 2. Monthly summary (template)

| Month | Joiners | Movers | Leavers | Joiner lead time | Leaver revocation time |
|---|---|---|---|---|---|
|  |  |  |  |  |  |

| Month | Stale accounts found | Stale accounts resolved | Orphans found | Orphans resolved |
|---|---|---|---|---|
|  |  |  |  |  |

| Month | MFA coverage | Legacy auth blocked | ScubaGear passes (aad/exo/teams) | Review actions open |
|---|---|---|---|---|
|  |  |  |  |  |

## 3. How to read this report as a manager

- **Trend, not a snapshot.** One month's joiner lead time means little; if it is drifting up, the HR
  record is being updated late, and that is where the fix belongs.
- **Zero is not always good.** Zero leavers in a month is normal. Zero leavers *ever* means the HR
  file's `Status` column is not being maintained, and the leaver timer never starts.
- **MFA coverage is a policy scope, not a feeling.** The figure is the share of user accounts the
  policy covers, not "most people seem to have set it up".
- **ScubaGear passes move slowly.** Tenancy configuration is a set of dozens of settings, so expect
  single-figure movements per month, not a leap to 100%.

## 4. What the business decides from this

| If the report shows | The decision needed |
|---|---|
| Leaver revocation time above the 15-minute target | Whether HR is recording leavers promptly (a process issue, not a technical one) |
| Stale accounts unresolved for two months | Whether to disable the accounts automatically, with the department head consulted |
| Review actions staying open | Whether the department heads' review deadline is realistic |
| MFA coverage below 100% | Whether the remaining accounts are genuinely exempt or simply missed |

> **Lab note:** Halden Distribution Ltd. is a **fictional company** and the 85-person HR file is
> **synthetic**. This report template is real; the figures appear only after the lab run, and each one
> is traceable to the file named in the Source column.

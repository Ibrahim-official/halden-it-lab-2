# Runbook — Operate the JML engine safely (and recover from a bad HR file)

**Applies to:** DC01 · **Owner:** IT / Systems · **Runs:** scheduled daily, and on demand
**Script:** `scripts/01-Invoke-HaldenJML.ps1`

> Why this runbook exists: an automated job that can disable the whole company is a bigger risk than
> the manual process it replaced. The controls below — dry run, circuit breaker, protected accounts
> and the audit log — are what make the automation safe enough to schedule.

## Before the first run of a session

1. **Snapshot DC01** — `snap-p2-ph1-before` (and FS01 if home folders change).
2. **Validate the HR export** (catches a truncated or mis-encoded file before the engine sees it):
   ```bash
   ./scripts/00-Validate-HrExport.sh ../data/hr-export.csv
   ```
   The validator fails on a missing column, a duplicate `EmployeeID`, an unknown status, or a
   duplicate `first.last` name. A non-zero exit means **do not run the engine**.

## The three modes

| Mode | Command | Changes anything? |
|---|---|---|
| Dry run (whole file) | `.\scripts\01-Invoke-HaldenJML.ps1 -WhatIf` | No |
| One person, dry run | `.\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '1042' -WhatIf` | No |
| Apply | `.\scripts\01-Invoke-HaldenJML.ps1` | Yes |
| Urgent leaver | `.\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '1042' -Urgent` | Yes (skips the date check) |

Always run the dry run and read the plan before the apply. The plan lists every create, disable,
group change and move it intends to make.

## What the engine decides

- **Joiner** — `Status = Active`, no AD account with that `EmployeeID`, and `StartDate` inside the
  joiner window (default 7 days). Creates the account, role groups and home folder.
- **Mover** — an AD account exists and its `Department` or `Title` differs from the export.
  Recomputes desired groups from the matrix and removes/adds in one run.
- **Leaver** — `Status = Leaver` and `EndDate` is today or earlier. Disables, strips groups, snapshots
  memberships, moves to `OU=Disabled`.
- **Orphan report** — enabled AD accounts with no matching HR record are listed to `reports/orphans.csv`
  and are **not** changed automatically. Orphans are a data-quality problem for a human to resolve.

## The circuit breaker

Before applying anything, the engine counts the leavers it would process. If that is more than **10%**
of the accounts it manages, it **aborts the entire run**, changes nothing, and writes an alert line to
the audit log and to `reports/circuit-breaker-<date>.txt`. This is the defence against a bad HR export
(for example one where the status column was overwritten) disabling most of the company.

When the circuit breaker trips:

1. **Do not** re-run with a raised threshold to "get past it".
2. Open the HR file and check the `Status` and `EndDate` columns — this is almost always a data
   problem, not a real mass resignation.
3. Fix the export, re-validate it, and run the dry run again.
4. Only raise the threshold deliberately and temporarily if the batch of leavers is genuinely real,
   and say so in the change record.

## Verification after any apply

1. **Read the audit log** — every action has a dated line with before/after values:
   ```powershell
   Import-Csv .\logs\jml-audit.csv | Select-Object -Last 20
   ```
2. **Re-run the dry run.** A correct, idempotent run now reports **no planned changes** — this is the
   single best proof the environment matches the HR file.
3. **Check the leaver snapshots** for any leaver processed:
   ```powershell
   Get-ChildItem .\logs\leavers\ | Sort-Object LastWriteTime -Descending | Select-Object -First 5
   ```
4. **Spot-check one account of each type** in ADUC or with `Get-ADUser` (see the joiner, mover and
   leaver runbooks for the exact commands).

## Recovering from a wrong run

1. **Stop the schedule** so the engine does not run again mid-recovery:
   ```powershell
   Disable-ScheduledTask -TaskName 'Halden-JML-Daily'
   ```
2. **Identify what changed** from the audit log, filtered to the run's timestamp.
3. **Restore leavers from their snapshots** — re-enable, move back, re-add the groups listed in
   `logs/leavers/<EmployeeID>.json`.
4. **Correct the HR export** so the next run does not repeat the mistake. The HR file, not AD, is the
   thing to fix.
5. **Re-enable the schedule** and run the dry run once more to confirm the plan is empty.

**Rollback (whole phase):** revert `snap-p2-ph1-before` and re-run the previous phase's scripts. The
audit log and the leaver snapshots are the record of what the reverted run did, and are worth keeping
even after a rollback.

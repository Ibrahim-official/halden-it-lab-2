# Runbook — Monthly patch-cycle verification

**Applies to:** all Windows and Linux servers and workstations · **Duty:** IT / Systems
**Time:** about half a day across the cycle · **Prepared by:** IT, approved by the IT manager

## Why this runbook exists

Patching without verification is a claim, not a control. This is the routine that turns "we patched"
into "we can show that the finding is gone and the service is healthy". It also produces the trend
the monthly report needs: what closed, what is overdue, and where effort is being spent.

## 0. The routine, in order

| # | Step | When | Tool |
|---|---|---|---|
| 1 | Publish the maintenance window to departments | 1 week before | `business/p05-monthly-report-template.md` notification block |
| 2 | Patch the pilot ring | Day 0–2 | `09-Invoke-WsusRingSetup.ps1` ring0 automatically |
| 3 | Check the pilot, then approve the broader rings | Day 3 | `10-Approve-WsusUpdates.ps1` (pilot gate ≥ 90%) |
| 4 | Patch member servers and Linux | Saturday window | `11-Invoke-ServerPatch.ps1`; `13-patch-linux.yml` |
| 5 | Patch the domain controllers in order | Saturday window | `11-Invoke-ServerPatch.ps1 -Order DC02,DC01` |
| 6 | Verification scan | Saturday 23:00 | `03-schedule-scan.sh` monthly task |
| 7 | Priority the new scan and compare closure | Sunday | `05-prioritize.py`; `07-verify-closure.sh` |
| 8 | Write the monthly report | First working day after | `14-weekly-report.sh`; monthly template |
| 9 | WSUS hygiene | Monthly | `12-Invoke-WsusMaintenance.ps1` |

## 1. Pre-flight checks (before any patching)

- [ ] Every host to be patched is snapped (`snap-p5-<cycle>-before-<host>`).
- [ ] `11-Invoke-ServerPatch.ps1 -WhatIf` shows the order and changes nobody expects.
- [ ] No change freeze in force (e.g. a business period) and the window is communicated.
- [ ] The last scan's report is exported, so "before" is on record before anything changes.

## 2. The pilot gate (this is the control, not a formality)

```powershell
.\scripts\10-Approve-WsusUpdates.ps1 -Simulate
```

The script refuses to approve the broader rings unless the pilot reports at least 90% installed.
**If the pilot shows a break, the cycle stops there.** That is the entire point of the pilot ring:
a broken update is cheap in two machines and expensive in eighty-five.

## 3. Server patching rules (do not deviate)

1. **DC02 first, then DC01** — never together. If DC02 fails a post-check, DC01 is not touched.
2. Pre-check: free space, pending reboot, DC health.
3. Post-check: services running, `dcdiag /q` clean on a DC, `repadmin /replsummary` clean.
4. Linux: `serial: 1`, reboot only if `/var/run/reboot-required` exists, SSH asserted afterwards.
5. Any host that fails a post-check **stops the run**; it is investigated, not skipped.

## 4. Verification scan and closure

```bash
cd projects/p05-vuln-management
./scripts/04-export-report.sh
python3 scripts/05-prioritize.py run --findings data/scans/latest.csv \
  --assets configs/p05-asset-criticality.csv --enrichment data/kev-epss-cache.json \
  --rules configs/p05-tier-rules.yml --out-csv reports/prioritized-work-list-after.csv
./scripts/07-verify-closure.sh \
  --before reports/prioritized-work-list-before.csv \
  --after  reports/prioritized-work-list-after.csv \
  --out    evidence/public/p05-verify-closure-result.csv
```

- **Closed** rows → close the tickets.
- **Still open** rows → keep the ticket, note why, and re-check the tier (a missed patch often means
  a dependency or a service that needs downtime).
- **New** rows → triage with `docs/runbooks/triage-critical-finding.md`.

## 5. Report and follow-up

```bash
./scripts/14-weekly-report.sh --as-of "$(date +%F)" --out reports/p05-monthly-status.md
```

The report states open-by-tier, overdue-by-tier, KEV exposure and closure progress. **MTTR stays
"not measured" until there are at least two real scans** — do not estimate it. Send the report to
management with the asks section filled in (approve downtime, replace an end-of-life device, sign an
exception).

## 6. What "done" looks like for the month

| Check | Expected |
|---|---|
| Pilot gate reached before broader approval | ≥ 90% of the pilot installed |
| All rings within their deadline | Servers by the 14-day mark, workstations by the 5-day mark |
| Verification scan completed | Both workstation and server target sets |
| Closure report written | `evidence/public/p05-verify-closure-result.csv` |
| Monthly report sent | With the asks section completed |
| WSUS maintenance run | Superseded updates declined, cleanup completed |

> **Lab practice:** the deadlines and the 90% gate are *targets and controls* here. Do not publish a
> compliance percentage or an SLA achievement figure until the cycle has actually run and the numbers
> are captured.

# Runbook — Nightly backup check (and what to do when one fails)

**Duty:** IT Service Desk / Systems · **Time:** 5 minutes each morning · **Applies to:** BKP01, DC01, DC02, FS01
**Target:** confirm last night's jobs produced a restorable restore point, not just a green tick.

## 0. What "healthy" looks like

| Check | Command (on BKP01) | Healthy answer |
|---|---|---|
| Repository reachable and intact | `restic snapshots --last` | at least one snapshot per protected Tier 0–2 host, latest within 24 h |
| Job results | `systemctl --failed` and `journalctl -u halden-backup --since yesterday` | no failed units, no error lines |
| Offsite copy present | `restic -r "$OFFSITE_REPOSITORY" snapshots --last` | latest on-site snapshot also present offsite |
| Disk free | `df -h /srv/backup` | below the free-space alert threshold (default 15%) |
| Immutable bucket reachable | `mc ls --versions halden/backup-immutable | tail` | objects present; no unexpected mass delete markers |
| Restore heartbeat | Uptime Kuma monitor "Halden — backup restore test" | up (last weekly test passed) |

The one-line summary comes from the reporting script:

```bash
sudo ./10-Get-BackupReport.sh --days 1
```

It prints a per-host table (last successful snapshot, age, offsite present) and exits non-zero if any
Tier 0/1 host has no snapshot within its RPO. Exit code is the alert condition.

## 1. If a Tier 0/1 host has no fresh snapshot

1. **Do not rerun the whole backup set.** Backups are independent; find the one that missed.
2. Check the job log for that host:
   ```bash
   sudo journalctl -u halden-backup --since "24 hours ago" | grep -i "<host>"
   ```
3. Check the source is reachable and awake. A powered-off VM that was meant to run is the most common
   cause — confirm with the hypervisor rather than assuming.
4. Re-run **only that host's job**:
   ```bash
   sudo ./02-Backup-HyperVVMs.ps1 -Name <host>     # from HOST01 for VM-level
   sudo ./restic-backup.sh <host>                  # from BKP01 for file-level
   ```
5. Confirm a fresh snapshot now exists (`restic snapshots --last`) and that the offsite copy ran.
6. Record the miss: host, duration without a restore point, cause, fix. If a Tier 1 host exceeded its
   1-hour RPO, raise an incident (not a service request) and note the actual data-loss window.

## 2. If the repository fails `restic check`

1. Treat as **High**. Do not prune, delete or "fix" anything until you understand the failure.
2. Capture the full output to a file before doing anything else:
   ```bash
   restic check --read-data-subset=10% 2>&1 | tee /srv/backup/reports/check-$(date +%F).log
   ```
3. If the error names specific packs, restic can often repair from the offsite copy:
   `restic copy` from Copy 2 restores missing data. The offline USB is the fallback of last resort.
4. Notify: the on-call systems owner, and — if Copy 2 looks affected — the incident channel.

## 3. If disk is filling

1. Confirm the growth is real (`du -sh /srv/backup/*`), not a runaway log.
2. Check prune is actually running (`journalctl -u halden-prune`). A failed prune is usually the
   cause; fix prune rather than deleting snapshots by hand.
3. Never delete a repository by hand to free space. `restic forget --prune` is the only supported
   path; manual deletion can corrupt the repository and destroy every dependent snapshot.

## 4. Weekly, in addition to the daily check

- The automated restore test runs weekly (`06-Test-BackupRestore.sh`); confirm the Uptime Kuma
  heartbeat is **up** and open the JSON/HTML report.
- A **failed restore test is the highest-priority backup alert there is** — it means the backups may
  not work. Treat it as an incident, not a ticket, and capture the report as evidence.

## 5. Escalation

| Situation | Action |
|---|---|
| One nightly job missed, re-run succeeded | Note in the service desk ticket; no escalation |
| Tier 1 host beyond its 1 h RPO | Incident; inform the affected department head |
| `restic check` failure | High alert (P7) + ticket (P9); start the recovery procedure |
| Restore test failed | Incident; do not wait for the next scheduled run |
| Any deletion attempt on the immutable bucket | Security alert (P7); treat as possible compromise |

> **Lab practice:** this runbook is written for the two-tier design above. Do not claim the routine
> works until it has been run against a real missed job and a real restore test.

# P8 restore-test plan — Halden Distribution Ltd.
# Where it applies: the weekly automated restore verification run on BKP01 (scripts/06-Test-BackupRestore.sh)
# and the sandbox VLAN 99. This defines WHAT is tested; measured outcomes are recorded only after a real
# run, in the report JSON and the history CSV (data/p08-restore-test-history-template.csv is the format).

## 1. Purpose

A backup that has never been restored is a hope, not a control. This plan defines a repeatable,
scheduled test that answers one question every week: **can we actually restore, and does the restored
data match?** A failed test is a High alert and a ticket, not a footnote.

## 2. Scope and rotation

| Frequency | File-level test | VM-level test |
|---|---|---|
| Weekly | 20 random files from the latest snapshot of the week's host, SHA-256 compared | one VM restored to sandbox VLAN 99, booted, service health check |
| Continuous | `restic check --read-data-subset=5%` weekly | — |
| Rotation | FS01 (Tier 1), OPS01 (Tier 2) alternate for the file sample | DC01 → FS01 → LNX01 → OPS01 → repeat |
| History target | 12 consecutive weekly results | same |

## 3. File-level test (steps)

1. Take a rotating sample of **20 files** from `restic ls latest --json` for the chosen host.
2. Restore them to `/srv/restore-test/<date>/` with `restic restore`.
3. Compute SHA-256 and compare against the **source hash manifest** written at backup time by the
   pre-backup step (`--source-manifest`). Where the live file is unchanged, the live hash is a valid
   fallback; a mismatch is a **failure** and is captured, not hidden.
4. Run `restic check --read-data-subset=5%` for repository integrity.
5. Record: files tested, files matched, mismatches, duration.

## 4. VM-level test (steps)

1. Restore the week's VM into **sandbox VLAN 99** (isolated bridge, no uplink) as a scratch VM.
2. Boot it and wait for it to settle (allow up to the designed settle time, default 180 s).
3. Run the service health check for that system:

   | System | Check |
   |---|---|
   | DC01/DC02 | `Get-Service NTDS,DNS,Netlogon` all Running; `dcdiag /q` clean |
   | FS01 | each share reachable as a test user; ACLs as designed |
   | LNX01 | app answers on its port; database readable |
   | OPS01 | GLPI and Uptime Kuma web UIs respond |

4. **Destroy** the scratch VM and its disk. This is the rollback for the test — production is untouched.
5. Record: VM booted (yes/no), service checks passed (count), duration.

## 5. Output and hand-off

| Output | Location | Consumer |
|---|---|---|
| Machine-readable result | `reports/restore-test-<date>.json` | history CSV, reporting |
| Human summary | `reports/restore-test-<date>.html` | the operator, evidence |
| One history row | history CSV (format in `data/`) | P10 monthly KPI ("restore success rate") |
| Monitoring heartbeat | push to Uptime Kuma (P9) | "Halden — backup restore test" monitor |
| Failure alert | High alert (P7) + ticket (P9) | incident response |

## 6. Pass/fail rule

- **PASS** — all sampled files hash-match, repository check clean, VM boots, all service checks pass.
- **FAIL** — any hash mismatch, a repository check error, a VM that fails to boot, or a failed service
  check. A fail is never downgraded to a warning: it means the backups may not work.

## 7. What this plan deliberately does not claim

- It does not claim a restore has succeeded until the test has actually been run.
- It does not test every file (a 5% read-data subset plus 20 files is a sample, not a full verification).
- It does not replace the full DR drill, which also measures the *rebuild* time, not just the restore.
- It does not test the offline USB every week (that is a monthly manual check in
  `docs/runbooks/nightly-backup-check.md`).

# Synthetic and support data — P8 backup and disaster recovery

**Nothing in this folder is a measured result.** The files here are either the *designed* schedule
and retention matrix or an *empty template* for results that do not exist yet. Fabricating a history of
successful restores would break AGENTS.md rule R2; the restore-test history file is therefore an empty
template, and it stays empty until `scripts/06-Test-BackupRestore.sh` has actually run in the lab.

| File | What it is | Status |
|---|---|---|
| `p08-backup-schedule-matrix.csv` | The designed backup schedule and retention per system/tier (the machine-readable view of `../configs/p08-backup-jobs.yaml`) | design, not measured |
| `p08-restore-test-history-template.csv` | The **empty** column header for the weekly restore-test history. Real rows are appended by the restore-test script after each real run | template — no data yet |
| `p08-dr-drill-timing-template.csv` | The **empty** timing table shell for a DR drill (matches the runbook's timing table) | template — no data yet |

## Notes on the templates

- The column names in `p08-restore-test-history-template.csv` are exactly those produced by
  `scripts/lib/restore_report.py` (`HISTORY_COLUMNS`), so the header is guaranteed to match the real
  output rather than being hand-typed.
- A real history file on BKP01 lives at `/srv/backup/reports/restore-test-history.csv`. It is **not**
  committed here while it contains nothing, and when it does contain real results it is copied into
  `../evidence/public/` only after the sanitization checklist (AGENTS.md 4.6) — in practice a
  screenshot or a sanitized extract, not a live log.
- If any row in these files were ever presented as a real measurement, it would be a rule R2 breach.
  The empty templates exist precisely so that the real ones have a fixed shape to fill in.

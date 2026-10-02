# Halden Distribution Ltd. — Restore-test register

| Field | Value |
|---|---|
| **Register ID** | REG-RST-001 |
| **Owner** | IT Lead |
| **Maintained by** | Automated weekly test, reviewed by the Service Desk |
| **Purpose** | The evidence that backups are **periodically verified**, as required by the backup policy and the backup/recovery job responsibility |

> **This register is empty.** No restore test has been run yet, so there is no history to publish.
> Fabricating weeks of "PASS" rows would breach the project's honesty rule (AGENTS.md R2). The rows
> below are the fixed **format**; the real rows are appended by `../scripts/06-Test-BackupRestore.sh`
> after each real run and copied here (sanitized) once they exist.

---

## 1. How a row is produced

1. The weekly timer runs `06-Test-BackupRestore.sh` on BKP01 (Sunday, 05:00).
2. It restores a sample of files and a virtual machine, checks hashes and service health, and writes:
   - `reports/restore-test-<date>-<host>.json` (machine-readable result)
   - an HTML summary for humans
   - one row in the history CSV (format below)
3. It pushes the outcome to the monitoring system; a failure raises a high alert and a ticket.
4. Once a quarter, the sanitized history is copied to `../evidence/public/` as evidence for the
   portfolio and for the monthly management report.

## 2. Register format (what a real row looks like)

| Date | Host | Files tested | Files matched | Mismatches | Repository check | Duration (s) | Result | Reviewed by | Notes |
|---|---|---|---|---|---|---|---|---|---|
| *(none yet)* | | | | | | | | | |
| | | | | | | | | | |
| | | | | | | | | | |
| | | | | | | | | | |

**Rules for filling it in**

- **PASS** only when every sampled file hash-matched *and* the repository check passed. Anything else
  is **FAIL**.
- **FAIL is reported, never suppressed.** A failed test is the most valuable row in the register,
  because it means the backups may not work.
- Duration is the measured restore duration for that test, in seconds.
- Notes record what was tested, what broke, and the ticket reference for any failure.

## 3. Targets for this register

| Measure | Target | Basis |
|---|---|---|
| Tests run per year | 52 (weekly) | Backup policy §8 |
| Success rate | 100% of scheduled tests passing | The "0" in 3-2-1-1-0 |
| Consecutive passing weeks | 12 consecutive weeks as the first milestone | Plan §Phase 3 |
| Time to report a failure | Same day, as a high alert and a ticket | Backup policy §8 |

> These are targets. The first achieved figures will appear in the rows above and in the measured
> performance table of `p08-service-levels.md`.

## 4. Empty template

The machine-readable empty template, with the exact column set the automated test produces, is
`../data/p08-restore-test-history-template.csv`. It contains a header and no rows, by design.

---

*Halden Distribution Ltd. is a fictional company. This register is a home-lab artifact; every row in it
will come from a real run in the isolated lab.*

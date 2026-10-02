# P8 retention and immutability policy — Halden Distribution Ltd.
# Where it applies: the on-site restic repository and the offsite MinIO/S3 bucket used by P8.
# This file is the policy of record; the machine-readable form is p08-backup-jobs.yaml
# (`retention:` block). Measured results are never recorded here.

## 1. Why retention and immutability are two different controls

- **Retention** decides how many restore points you keep. It protects against *time* — a mistake you
  noticed a week later is still recoverable.
- **Immutability** decides that a restore point cannot be deleted before its time. It protects against
  *an attacker with your credentials*. Both are required: a locked copy with a two-day retention is
  useless, and a 12-month retention on a writable copy is gone the moment the attacker logs in.

A rule to remember: **retention must be greater than or equal to the recovery window promised to the
business.** If the business is told "we can go back 30 days", the immutable floor must be at least
30 days.

## 2. On-site repository (Copy 1) — restic forget policy

| Tier | Systems | Hourly | Daily | Weekly | Monthly | Longest restore point |
|---|---|---|---|---|---|---|
| 0 Foundation | DC01, DC02, FW01 config | — | 30 | — | 12 | ~12 months |
| 1 Critical | FS01, LNX01 | 24 | 14 | 8 | 12 | ~12 months |
| 2 Important | OPS01, SIEM01 | — | 14 | 8 | — | ~2 months |
| 3 Deferrable | workstations | n/a — re-imaged from the standard build | | | | — |

**Why Tier 2 keeps eight weeks and not four.** The immutable floor and the promised recovery window
are both 30 days, so retention must reach at least 30 days. Four weekly points reach only 28 days —
short of the promise. Eight weekly points reach 56 days and keep the policy consistent. This is
exactly the check the `retention_policy.py` audit performs, so the inconsistency cannot creep back in
unnoticed.

Command per tier (Tier 1 shown):

```bash
restic forget --keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
```

Do not delete snapshots by hand. `forget --prune` is the only supported way to reclaim space; manual
deletion can corrupt the repository and destroy every snapshot that depends on the same pack files.

## 3. Offsite bucket (Copy 2) — S3 Object Lock

| Setting | Value | Why |
|---|---|---|
| Bucket | `halden/backup-immutable` | created **with** Object Lock at creation (cannot be added later) |
| Versioning | enabled | required by Object Lock |
| Default retention | **COMPLIANCE, 30 days** | cannot be shortened or cleared before expiry — not even by root |
| Lifecycle rule | expire non-current versions after 35 days | keeps the bucket from growing forever once locks lapse |
| Access keys | separate from domain credentials; in the uncommitted env file | least privilege; rotate on any suspicion |

```bash
mc mb --with-lock halden/backup-immutable
mc retention set --default COMPLIANCE 30d halden/backup-immutable
```

**How it behaves with restic:** Object Lock needs versioning, so a "delete" adds a delete marker and
the locked versions survive. restic's `prune` appears to succeed while storage only shrinks after the
locks expire. Lifecycle expiry clears the non-current versions **after** the lock, which is why the
lifecycle window (35 d) is slightly longer than the lock (30 d).

## 4. Offline copy (Copy 3) — air gap

| Setting | Value |
|---|---|
| Medium | encrypted USB (LUKS or VeraCrypt) |
| Content | latest restic repository export + latest VM export |
| Frequency | monthly |
| Handling | disconnect, store off-site, log the rotation (date, carrier, return date) |
| Restore | requires the passphrase from the sealed envelope stored with the disk |

The offline copy is the only copy no network credential can reach. It is the last line of defence
against a compromise of both BKP01 and the object store. Because it is manual, it is also the copy most
likely to be forgotten — hence the rotation log and the monthly check in `nightly-backup-check.md`.

## 5. Immutability proof (first-class evidence, not a footnote)

`../scripts/05-Test-Immutability.sh` runs, with the **backup user's own credentials**:

| Attempt | Expected result |
|---|---|
| `mc rm --recursive --force <bucket>/fs01` | "succeeds", adds delete markers only |
| `mc rm --recursive --force --versions <bucket>/fs01` | **fails** — object is WORM protected |
| `mc retention clear --recursive <bucket>/fs01` | **fails** — COMPLIANCE retention cannot be cleared |
| `mc retention set --default GOVERNANCE 1d <bucket>/fs01` | **fails** — cannot shorten |
| `mc cp --rewind 1h` to a scratch folder, then `restic snapshots` | repository intact, snapshots listed |

A failed deletion is the evidence. Capture the exact error text and the successful rewind as the
project's immutability evidence (AGENTS.md 4.5).

## 6. Exceptions and review

- Retention changes are **change-managed**: a longer retention increases cost, a shorter one reduces
  the recovery window and must be re-agreed with the business.
- The immutable floor must never be set below the recovery window promised in
  `p08-rpo-rto-targets.md`.
- Review this policy at least annually, or after any drill that exposed a gap.

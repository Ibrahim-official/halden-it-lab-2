# P8 offsite / object-store configuration — Halden Distribution Ltd.
# Where it applies: the MinIO VM that simulates the offsite provider (lab) and, in production,
# an S3-compatible provider such as Backblaze B2 or Wasabi. Used by 04-Backup-OffsiteCopy.sh
# and 05-Test-Immutability.sh. All credentials are PLACEHOLDERS here — the real values live in
# the uncommitted env file /etc/halden-lab/backup.env and the owner's password manager. NEVER commit them.

## 1. Why an object store with Object Lock

The offsite copy must be somewhere a compromised on-site account cannot reach, and it must be
**immutable**: a delete must be refused. S3-compatible object storage with Object Lock in COMPLIANCE
mode gives both. In the lab, MinIO on a separate VM/disk stands in for the cloud provider; in
production the same commands work against B2/Wasabi/S3.

## 2. Lab endpoint

| Setting | Value |
|---|---|
| Service | MinIO (S3-compatible) |
| Host (design) | `minio.halden.internal` (lab VM/disk, separate from BKP01) |
| S3 API port | 9000 |
| Console port | 9001 |
| Bucket | `halden/backup-immutable` |
| TLS | static self-signed cert in the lab; real provider cert in production |
| Simulated provider | a separate VM/disk — **not** physically independent of the host (see docs/00-design.md §17) |

## 3. Bucket creation with lock (order matters)

Object Lock **must be enabled at bucket creation** — it cannot be added to an existing bucket:

```bash
mc alias set halden "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --with-lock halden/backup-immutable
mc retention set --default COMPLIANCE 30d halden/backup-immutable
mc version enable halden/backup-immutable
```

The keys above are placeholders on purpose. Operator sets real values in the shell environment from
the env file; they are never written into this file or into Git.

## 4. Application keys (least privilege)

| Principal | Purpose | Scope |
|---|---|---|
| root / admin | bucket creation, retention default, lifecycle rule | used once, then not for daily jobs |
| `halden-backup-writer` | restic `copy` into the bucket | write + list only, no delete of locked versions |
| `halden-backup-reader` | restore operations | read + list only |

Restrict the writer to `s3:PutObject`/`s3:ListBucket`; do **not** grant `s3:BypassGovernanceRetention`
(would let it defeat GOVERNANCE locks) and do not grant admin. In COMPLIANCE mode even admin cannot
shorten retention, but least privilege still limits the blast radius.

## 5. restic configuration (on BKP01)

```bash
# from /etc/halden-lab/backup.env — placeholders in configs/backup.env.example
export AWS_ACCESS_KEY_ID="$MINIO_BACKUP_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$MINIO_BACKUP_SECRET_KEY"
export RESTIC_REPOSITORY="s3:${MINIO_ENDPOINT}/backup-immutable/fs01"
export RESTIC_PASSWORD_FILE=/etc/halden-lab/restic.pass
restic init                      # first time only
restic copy --from-repo /srv/backup/restic   # copy on-site snapshots offsite
```

## 6. Lifecycle rule

| Rule | Value | Why |
|---|---|---|
| Expire non-current versions | after 35 days | cleans up delete markers/versions once locks lapse |
| Abort incomplete multipart uploads | after 7 days | avoids orphaned parts from interrupted copies |

## 7. What this configuration does NOT do

- It does **not** make MinIO physically offsite — it is a separate VM on the same host. Only the offline
  USB is genuinely independent.
- It does **not** protect against a wrong restore point or a lost passphrase. Retention must stay ≥ the
  recovery window, and the passphrase is escrowed offline.
- It does **not** remove the need to test. `05-Test-Immutability.sh` proves the refusal, and
  `06-Test-BackupRestore.sh` proves the data can be read back.

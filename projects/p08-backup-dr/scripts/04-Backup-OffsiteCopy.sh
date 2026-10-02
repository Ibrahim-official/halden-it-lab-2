#!/usr/bin/env bash
# Phase 2: copy the on-site repository to the offsite object store (Copy 2) and apply the bucket
# lifecycle rule. Where it runs: BKP01. Snapshot first: snap-p8-ph2-before.
# Rollback: nothing in production changes; deleting a copied snapshot needs Object Lock to lapse.
# Idempotent: restic copy only sends what is missing.
# Secrets: object-store keys and RESTIC_PASSWORD_FILE come from the uncommitted env file. Never printed.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
APPLY_LIFECYCLE=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: sudo $0 [--apply-lifecycle] [--dry-run]
  Copy on-site restic snapshots to the offsite repository (Copy 2) and list the result.
  --apply-lifecycle   add the non-current-version expiry rule to the bucket (mc ilm)
  --dry-run           show what would run, change nothing
  -h, --help
EOF
}
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

check_lab() {
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
}
load_env() {
  [[ -f "$ENV_FILE" ]] || die "env file $ENV_FILE not found"
  set -a; source "$ENV_FILE"; set +a
  : "${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY}"
  : "${RESTIC_PASSWORD_FILE:?set RESTIC_PASSWORD_FILE}"
  : "${OFFSITE_REPOSITORY:?set OFFSITE_REPOSITORY}"
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
  export AWS_ACCESS_KEY_ID="${MINIO_BACKUP_ACCESS_KEY:?set MINIO_BACKUP_ACCESS_KEY}"
  export AWS_SECRET_ACCESS_KEY="${MINIO_BACKUP_SECRET_KEY:?set MINIO_BACKUP_SECRET_KEY}"
}
copy_offsite() {
  log "copying on-site repository -> $OFFSITE_REPOSITORY"
  if ((DRY_RUN)); then restic -r "$OFFSITE_REPOSITORY" copy --from-repo "$RESTIC_REPOSITORY" --dry-run
  else restic -r "$OFFSITE_REPOSITORY" copy --from-repo "$RESTIC_REPOSITORY"; fi
}
verify_offsite() {
  log "offsite snapshots (latest per host):"
  restic -r "$OFFSITE_REPOSITORY" snapshots --last
}
lifecycle() {
  command -v mc >/dev/null 2>&1 || die "mc (MinIO client) not installed"
  local bucket="${MINIO_BUCKET:-halden/backup-immutable}"
  log "applying lifecycle: expire non-current versions after 35 days on $bucket"
  if ((DRY_RUN)); then echo "mc ilm rule add --expire-noncurrent-days 35 --noncurrent-expire-delete-marker $bucket"
  else mc ilm rule add --expire-noncurrent-days 35 --noncurrent-expire-delete-marker "$bucket"; fi
}

main() {
  while (($#)); do
    case "$1" in
      --apply-lifecycle) APPLY_LIFECYCLE=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  check_lab; load_env; copy_offsite; verify_offsite
  ((APPLY_LIFECYCLE)) && lifecycle || true
  echo "Verify: restic -r \$OFFSITE_REPOSITORY snapshots --last ; then run 05-Test-Immutability.sh"
}

main "$@"

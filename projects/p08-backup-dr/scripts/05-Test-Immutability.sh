#!/usr/bin/env bash
# Phase 2: PROVE immutability — attempt to destroy the offsite copy with the backup user's own
# credentials and confirm the deletion is REFUSED. The failure is the evidence.
# Where it runs: BKP01. Snapshot first: snap-p8-ph2-before. Change nothing else.
# Output: a report under reports/ and a clear PASS/FAIL exit code. Never touches anything outside the
# lab MinIO bucket (AGENTS.md R1/R6).
# Secrets: object-store keys come from the uncommitted env file. Never printed.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
BUCKET_PATH=""
DRY_RUN=0
REPORT_DIR=""
REPORT=""

usage() {
  cat <<EOF
Usage: sudo $0 [--bucket halden/backup-immutable/fs01] [--report-dir DIR] [--dry-run]
  Try to delete the immutable offsite repository and confirm it is refused.
  Exit 0 = the control holds (deletion refused). Exit 1 = a deletion unexpectedly succeeded.
  --bucket       full path of the protected prefix (default: \$MINIO_BUCKET/fs01)
  --report-dir   where to write the report (default /srv/backup/reports)
  --dry-run      print the attempts, run nothing
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
  : "${MINIO_ENDPOINT:?set MINIO_ENDPOINT}"
  : "${MINIO_BACKUP_ACCESS_KEY:?set MINIO_BACKUP_ACCESS_KEY}"
  : "${MINIO_BACKUP_SECRET_KEY:?set MINIO_BACKUP_SECRET_KEY}"
  export AWS_ACCESS_KEY_ID="$MINIO_BACKUP_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$MINIO_BACKUP_SECRET_KEY"
  BUCKET_PATH="${BUCKET_PATH:-${MINIO_BUCKET:-halden/backup-immutable}/fs01}"
  REPORT_DIR="${REPORT_DIR:-${BACKUP_ROOT:-/srv/backup}/reports}"
}
mc_alias() { mc alias set halden "$MINIO_ENDPOINT" "$MINIO_BACKUP_ACCESS_KEY" "$MINIO_BACKUP_SECRET_KEY" >/dev/null; }

# run_attempt LABEL EXPECTED(fail|ok) -- command...
run_attempt() {
  local label="$1" expect="$2"; shift 2; [[ "$1" == "--" ]] && shift
  local out rc=0
  if ((DRY_RUN)); then out="(dry-run) $*"; rc=0
  else out="$("$@" 2>&1)" || rc=$?; fi
  local verdict
  if [[ "$expect" == "fail" ]]; then
    ((rc != 0)) && verdict="REFUSED (as designed)" || verdict="UNEXPECTEDLY SUCCEEDED (control broken)"
  else
    ((rc == 0)) && verdict="succeeded (as designed)" || verdict="failed (investigate)"
  fi
  printf '%s\t%s\t%s\n' "$label" "$verdict" "$out" | tee -a "$REPORT"
  [[ "$expect" == "fail" && "$rc" == 0 ]] && return 1 || return 0
}

main() {
  while (($#)); do
    case "$1" in
      --bucket) shift; BUCKET_PATH="$1" ;;
      --report-dir) shift; REPORT_DIR="$1" ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  check_lab; load_env
  command -v mc >/dev/null 2>&1 || die "mc (MinIO client) not installed"
  install -d -m 0755 "$REPORT_DIR"
  REPORT="$REPORT_DIR/immutability-test-$(date +%Y%m%d-%H%M%S).tsv"
  printf 'attempt\tverdict\tdetail\n' > "$REPORT"

  local rc=0
  [[ "$DRY_RUN" == "1" ]] || mc_alias
  log "immutability test against $BUCKET_PATH (credentials: backup user, not root)"
  run_attempt "1 rm objects (delete markers)"      ok   -- mc rm --recursive --force "$BUCKET_PATH" || rc=1
  run_attempt "2 rm --versions (must be refused)" fail -- mc rm --recursive --force --versions "$BUCKET_PATH" || rc=1
  run_attempt "3 retention clear (must be refused)" fail -- mc retention clear --recursive "$BUCKET_PATH" || rc=1
  run_attempt "4 shorten retention (must be refused)" fail -- mc retention set --default GOVERNANCE 1d "$BUCKET_PATH" || rc=1

  log "recovering the 'deleted' repository via rewind (proves versions survive)"
  if ((DRY_RUN)); then log "(dry-run) mc cp --recursive --rewind 1h $BUCKET_PATH /srv/restore-scratch/fs01-repo/";
  else mc cp --recursive --rewind 1h "$BUCKET_PATH" /srv/restore-scratch/fs01-repo/ >/dev/null && log "rewind recovered"; fi

  log "report: $REPORT"
  ((rc == 0)) && echo "RESULT: PASS — the immutable copy refused deletion" || { echo "RESULT: FAIL — investigate immediately" >&2; }
  exit "$rc"
}

main "$@"

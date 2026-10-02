#!/usr/bin/env bash
# Phase 3 hand-off: push the backup/restore-test heartbeat to Uptime Kuma (installed in P9 on OPS01).
# Where it runs: BKP01. Called by 06-Test-BackupRestore.sh and usable on its own from cron/timer.
# Idempotent and safe: it only reports status; it changes nothing.
# Secrets: the push URL contains a token and lives only in the uncommitted env file. Never printed.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
STATUS=""
MSG="Halden backup heartbeat"
PING=""
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --status {up|down} [--msg TEXT] [--ping MS] [--dry-run]
  Push one status to the Uptime Kuma monitor 'Halden — backup restore test' (P9).
  up   = last restore test passed / backups healthy
  down = restore test failed or backups missed their RPO  -> raises a P7 alert
  --dry-run   print the URL (token redacted) and send nothing
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
  : "${UPTIME_KUMA_PUSH_URL:?set UPTIME_KUMA_PUSH_URL in $ENV_FILE}"
}
push() {
  local url="${UPTIME_KUMA_PUSH_URL}?status=${STATUS}&msg=$(printf '%s' "$MSG" | jq -sRr @uri)"
  [[ -n "$PING" ]] && url="${url}&ping=${PING}"
  if ((DRY_RUN)); then log "(dry-run) would push status=$STATUS to ${UPTIME_KUMA_PUSH_URL%%\?*}?token=REDACTED"; return 0; fi
  command -v curl >/dev/null 2>&1 || die "curl not installed"
  curl -fsS --max-time 10 "$url" >/dev/null && log "heartbeat pushed: $STATUS" || die "heartbeat push failed"
}

main() {
  while (($#)); do
    case "$1" in
      --status) shift; STATUS="$1" ;;
      --msg) shift; MSG="$1" ;;
      --ping) shift; PING="$1" ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  [[ "$STATUS" == "up" || "$STATUS" == "down" ]] || usage
  check_lab; load_env; push
}

main "$@"

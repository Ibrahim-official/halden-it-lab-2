#!/usr/bin/env bash
# Reporting/monitoring: summarise backup health for the daily check and the P10 monthly KPI.
# Where it runs: BKP01. Read-only. Exit code is the alert condition (0 healthy, 1 attention needed).
# Secrets: repository passphrase from the uncommitted env file. Never printed.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/backup}"
DAYS="1"
HISTORY_CSV=""
# Designed RPO (hours) per tier 0/1 host — from configs/p08-rpo-rto-targets.md.
declare -A RPO_HOURS=( [DC01]=24 [DC02]=24 [FS01]=1 [LNX01]=1 [OPS01]=24 [SIEM01]=24 )

usage() {
  cat <<EOF
Usage: sudo $0 [--days N] [--history-csv FILE]
  Print per-host last-snapshot age, offsite presence, disk free and the last restore-test result.
  Exit 0 = every Tier 0/1 host is inside its RPO. Exit 1 = at least one is not, or a test failed.
  --days          only consider snapshots from the last N days for the "recent" count (default 1)
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
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
}

age_hours() { # ISO time -> whole hours ago
  local t="$1"; local secs; secs=$(( $(date +%s) - $(date -d "$t" +%s) )); echo $(( secs / 3600 ));
}

report_hosts() {
  local rc=0
  printf '%-8s %-6s %-18s %-7s %-6s %s\n' HOST TIER LAST-SNAPSHOT AGE-H RPO-H STATUS
  local hosts; hosts=$(restic snapshots --json | jq -r '[.[].host]|unique|.[]')
  for h in $hosts; do
    [[ -n "${RPO_HOURS[$h]:-}" ]] || continue
    local last age rpo status
    last=$(restic snapshots --host "$h" --last --json | jq -r '.[0].time // empty')
    if [[ -z "$last" ]]; then status="NO-SNAPSHOT"; age=""; rc=1
    else age=$(age_hours "$last"); rpo=${RPO_HOURS[$h]}
      if (( age <= rpo )); then status=ok; else status="STALE"; rc=1; fi
    fi
    printf '%-8s %-6s %-18s %-7s %-6s %s\n' "$h" "?" "$last" "$age" "${RPO_HOURS[$h]}" "$status"
  done
  return "$rc"
}

report_offsite() {
  local last; last=$(restic -r "${OFFSITE_REPOSITORY:?set OFFSITE_REPOSITORY}" snapshots --last --json 2>/dev/null | jq -r '.[0].time // "none"')
  printf 'offsite latest snapshot: %s\n' "$last"
}
report_disk()  { printf 'disk: '; df -h "$BACKUP_ROOT" | tail -1; }
report_test()  {
  HISTORY_CSV="${HISTORY_CSV:-$BACKUP_ROOT/reports/restore-test-history.csv}"
  if [[ -s "$HISTORY_CSV" ]]; then
    printf 'last 3 restore tests:\n'; tail -3 "$HISTORY_CSV"
    grep -q ',FAIL$' <(tail -3 "$HISTORY_CSV") && return 1 || return 0
  else printf 'restore-test history: (none yet)\n'; fi
}

main() {
  while (($#)); do
    case "$1" in
      --days) shift; DAYS="$1" ;;
      --history-csv) shift; HISTORY_CSV="$1" ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  check_lab; load_env
  command -v restic >/dev/null 2>&1 || die "restic not installed"
  command -v jq >/dev/null 2>&1 || die "jq not installed"
  local rc=0
  report_hosts || rc=1
  report_offsite || true
  report_disk
  report_test || rc=1
  log "report complete (exit $rc)"
  exit "$rc"
}

main "$@"

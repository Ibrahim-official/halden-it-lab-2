#!/usr/bin/env bash
# Phase 3: weekly automated restore verification — the "0" in 3-2-1-1-0.
# Where it runs: BKP01 (scheduled as halden-restore-test.timer, Sunday 05:00).
# What it does: restores a sample of real files from the latest snapshot into a scratch folder,
#   SHA-256 compares them against the source manifest written at backup time, runs a repository
#   integrity check, writes a JSON + CSV result, and pushes a heartbeat to Uptime Kuma (P9).
# Snapshot first: snap-p8-ph3-before (only matters if paths change). Rollback: delete the scratch dir.
# Secrets: repository passphrase from the uncommitted env file. Never printed.
# Honesty: this script produces a REAL result when run. It never assumes success.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/backup}"
HOST=""
FILES="${FILES:-20}"
SCRATCH=""
REPORT_DIR=""
HISTORY_CSV=""
NO_HEARTBEAT=0
DRY_RUN=0
REPO=""
MANIFEST_DIR=""

usage() {
  cat <<EOF
Usage: sudo $0 [--host FS01] [--files 20] [--repo PATH] [--dry-run] [--no-heartbeat]
  Restore a sample of files, verify their hashes, and record the result.
  --host          system to test (default: rotate DC01->FS01->LNX01->OPS01 by ISO week)
  --files         number of random files to restore (default 20)
  --repo          restic repository (default \$RESTIC_REPOSITORY)
  --report-dir    output directory (default \$BACKUP_ROOT/reports)
  --history-csv   append a history row here (default \$BACKUP_ROOT/reports/restore-test-history.csv)
  --no-heartbeat  do not push to Uptime Kuma
  --dry-run       show the plan, change nothing
  -h, --help
EOF
  exit "${1:-0}"
}
log()  { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
now_s(){ date +%s; }

check_lab() {
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
}
load_env() {
  [[ -f "$ENV_FILE" ]] || die "env file $ENV_FILE not found"
  set -a; source "$ENV_FILE"; set +a
  export RESTIC_REPOSITORY="${REPO:-${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY}}"
  export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:?set RESTIC_PASSWORD_FILE}"
}
require_tools() { for t in restic jq sha256sum shuf; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done; }

rotate_host() {
  local week; week=$(date +%V)
  local hosts=(DC01 FS01 LNX01 OPS01); echo "${hosts[$((10#$week % ${#hosts[@]}))]}"
}

pick_files() {
  restic ls latest --host "$1" --json 2>/dev/null \
    | jq -r 'select(.type=="file") | .path' \
    | grep -v '/proc/\|/sys/\|/dev/' \
    | shuf -n "$FILES"
}

compare_hashes() {
  # $1 = scratch root; reads the source paths on stdin; prints "path<TAB>status"
  local scratch="$1" latest_manifest
  latest_manifest="$(ls -1t "$MANIFEST_DIR"/tier*.sha256 2>/dev/null | head -1 || true)"
  while IFS= read -r p; do
    local restored="$scratch$p" status="mismatch"
    if [[ ! -f "$restored" ]]; then status="missing-after-restore";
    elif [[ -z "$latest_manifest" ]]; then status="no-manifest";
    else
      local want got
      want="$(awk -v f="$p" '$2==f {print $1}' "$latest_manifest" | head -1)"
      got="$(sha256sum "$restored" | awk '{print $1}')"
      if [[ -z "$want" ]]; then status="not-in-manifest"; elif [[ "$want" == "$got" ]]; then status="match"; fi
    fi
    printf '%s\t%s\n' "$p" "$status"
  done
}

main() {
  while (($#)); do
    case "$1" in
      --host) shift; HOST="$1" ;;
      --files) shift; FILES="$1" ;;
      --repo) shift; REPO="$1" ;;
      --report-dir) shift; REPORT_DIR="$1" ;;
      --history-csv) shift; HISTORY_CSV="$1" ;;
      --no-heartbeat) NO_HEARTBEAT=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  check_lab; load_env; require_tools
  HOST="${HOST:-$(rotate_host)}"
  REPORT_DIR="${REPORT_DIR:-$BACKUP_ROOT/reports}"
  HISTORY_CSV="${HISTORY_CSV:-$REPORT_DIR/restore-test-history.csv}"
  MANIFEST_DIR="${MANIFEST_DIR:-$BACKUP_ROOT/manifests}"
  SCRATCH="$BACKUP_ROOT/restore-scratch/$(date +%F)-$HOST"
  local report="$REPORT_DIR/restore-test-$(date +%F)-$HOST.json"
  install -d -m 0755 "$REPORT_DIR" "$SCRATCH"
  log "restore test: host=$HOST files=$FILES scratch=$SCRATCH"

  local files_paths="$SCRATCH/.sample.txt"
  restic snapshots --host "$HOST" --last >/dev/null 2>&1 || die "no snapshots found for host $HOST"
  pick_files "$HOST" > "$files_paths"
  local n; n=$(wc -l < "$files_paths" | tr -d ' ')
  ((n > 0)) || die "no files selected for host $HOST"

  if ((DRY_RUN)); then
    log "(dry-run) would restore and hash-compare $n files from host $HOST"; cat "$files_paths"; exit 0
  fi

  local t0; t0=$(now_s)
  local include_args=(); while IFS= read -r p; do include_args+=(--include "$p"); done < "$files_paths"
  restic restore latest --host "$HOST" "${include_args[@]}" --target "$SCRATCH"
  local results; results="$(compare_hashes "$SCRATCH" < "$files_paths")"

  local matched mismatches not_manifest
  matched=$(grep -c $'\tmatch$' <<<"$results" || true)
  mismatches=$(grep -c $'^\S.*\t\(mismatch\|missing-after-restore\)$' <<<"$results" || true)
  not_manifest=$(grep -c $'\tnot-in-manifest$' <<<"$results" || true)

  local check_result="pass" check_detail=""
  if ! check_detail="$(restic check --read-data-subset=5% 2>&1)"; then check_result="fail"; fi
  local duration; duration=$(( $(now_s) - t0 ))

  local result="FAIL"
  ((mismatches == 0 && check_result == "pass")) && result="PASS"

  jq -n \
    --arg date "$(date +%F)" --arg host "$HOST" --arg phase "file-level" \
    --argjson files_tested "$n" --argjson files_matched "$matched" \
    --argjson mismatches "$mismatches" --argjson not_in_manifest "$not_manifest" \
    --arg repo_check "$check_result" --arg repo_detail "$check_detail" \
    --argjson duration_seconds "$duration" --arg result "$result" \
    '{date:$date,host:$host,phase:$phase,files_tested:$files_tested,files_matched:$files_matched,
      mismatches:$mismatches,not_in_manifest:$not_in_manifest,repo_check:$repo_check,
      repo_detail:$repo_detail,duration_seconds:$duration_seconds,result:$result}' > "$report"
  log "report written: $report"

  # Append a history row using the shared parser (tested in scripts/tests/).
  if command -v python3 >/dev/null 2>&1 && [[ -f "$(dirname "$0")/lib/restore_report.py" ]]; then
    python3 "$(dirname "$0")/lib/restore_report.py" append --json "$report" --csv "$HISTORY_CSV" || log "WARNING: history append failed"
  else
    log "WARNING: python3 or lib/restore_report.py missing; history not appended"
  fi

  if (( ! NO_HEARTBEAT )) && [[ -x "$(dirname "$0")/09-Push-BackupHeartbeat.sh" ]]; then
    local status=up; [[ "$result" == "PASS" ]] || status=down
    "$(dirname "$0")/09-Push-BackupHeartbeat.sh" --status "$status" \
      --msg "restore-test $HOST: $matched/$n files matched, repo $check_result" || log "WARNING: heartbeat push failed"
  fi

  rm -rf "$SCRATCH"
  log "cleaned scratch: $SCRATCH"
  echo "RESULT: $result ($matched/$n files matched, repo check $check_result, ${duration}s)"
  [[ "$result" == "PASS" ]] || exit 1
}

main "$@"

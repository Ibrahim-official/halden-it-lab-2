#!/usr/bin/env bash
# Phase 5: DR drill timer and checklist — turns the runbook into measured steps.
# Where it runs: BKP01 (the recovery console). It does NOT recover anything itself; it holds the
# clock, checks the preconditions, and records each step's start/end into a CSV for the drill report.
# Snapshot first: snap-p8-ph5-before. Rollback for a drill: destroy the scratch environment
#   (Remove-VM -Force + delete /srv/restore-scratch/<host>). Nothing in production is changed by this
#   script; the actual restore steps are run from docs/runbooks/dr-drill-full-recovery.md.
# Secrets: never read or printed here.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/backup}"
OUT=""
STEP=""
SCENARIO="ransomware-full-recovery"
LIST=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: sudo $0 --start [--scenario NAME] | --step NAME | --end | --list
  Hold the stopwatch for a DR drill and append each step's timing to a CSV.
  --start           begin a drill (checks preconditions, records the start time)
  --step NAME       record the end of a named step (prints elapsed seconds)
  --end             close the drill and print the summary table
  --scenario NAME   label for this drill (default $SCENARIO)
  --out FILE        CSV path (default \$BACKUP_ROOT/reports/dr-drill-<date>.csv)
  --list            print the canonical step names from the runbook
  --dry-run         show the plan without writing anything
  -h, --help
EOF
}
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
now() { date +%s; }

check_lab() {
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
}
preconditions() {
  log "checking preconditions"
  local ok=1
  if [[ -f "$ENV_FILE" ]]; then log "env file present"; else log "WARN env file missing ($ENV_FILE)"; ok=0; fi
  command -v restic >/dev/null 2>&1 && log "restic present" || { log "WARN restic missing"; ok=0; }
  if restic snapshots --last >/dev/null 2>&1; then log "repository reachable"; else log "WARN repository unreachable"; ok=0; fi
  if [[ "${OFFSITE_REPOSITORY:-}" ]] && restic -r "$OFFSITE_REPOSITORY" snapshots --last >/dev/null 2>&1; then log "offsite reachable"; else log "NOTE offsite not checked/reachable"; fi
  printf 'CONFIRM BEFORE CONTINUING: snapshots taken of every VM, sandbox VLAN 99 has no uplink, printed runbook to hand.\n'
  ((ok)) || log "WARNING: some preconditions failed — fix them before timing a drill"
}

canonical_steps() {
  cat <<'EOF'
0-declare-and-isolate
1-clean-infrastructure
2-bkp01-health-and-restore-point
3-dc01-restore
4-credential-reset
5-fs01-restore
6-lnx01-restore
7-ops01-siem01-restore
8-workstation-reimage
9-handback-and-review
EOF
}

start_drill() {
  OUT="${OUT:-$BACKUP_ROOT/reports/dr-drill-$(date +%F).csv}"
  [[ "$(basename "$OUT")" == *"$(date +%F)"* ]] || OUT="$OUT-$(date +%F).csv"
  install -d -m 0755 "$(dirname "$OUT")"
  if ((DRY_RUN)); then log "(dry-run) would start drill '$SCENARIO' writing to $OUT"; exit 0; fi
  printf 'scenario\tstep\tstarted\tended\tseconds\tnotes\n' > "$OUT"
  printf '%s\t%s\t%(%Y-%m-%dT%H:%M:%S)T\t\t\t%s\n' "$SCENARIO" "0-declare-and-isolate" -1 "" >> "$OUT"
  export HALDEN_DRILL_START="$(now)"; export HALDEN_DRILL_STEP_START="$(now)"
  log "drill started: $SCENARIO -> $OUT"
  log "the stopwatch is in the CSV times; re-run with --start to reset if needed"
}

record_step() {
  local name="$1"
  [[ -n "$name" ]] || die "--step needs a name (see --list)"
  [[ -f "$OUT" ]] || die "no drill in progress (run --start first)"
  local step_start="${HALDEN_DRILL_STEP_START:-$(now)}" elapsed=$(( $(now) - step_start ))
  if ((DRY_RUN)); then log "(dry-run) step '$name' = ${elapsed}s"; return 0; fi
  printf '%s\t%s\t\t%(%Y-%m-%dT%H:%M:%S)T\t%d\t%s\n' "$SCENARIO" "$name" -1 "$elapsed" "" >> "$OUT"
  export HALDEN_DRILL_STEP_START="$(now)"
  log "step '$name' recorded: ${elapsed}s"
}

end_drill() {
  [[ -f "$OUT" ]] || die "no drill in progress"
  local total="${HALDEN_DRILL_START:-}"; local secs=""
  [[ -n "$total" ]] && secs=$(( $(now) - total ))
  log "drill ended${secs:+ after ${secs}s}"
  printf 'TOTAL\tfull-recovery\t\t\t%s\t\n' "${secs:-}" >> "$OUT"
  column -t -s $'\t' "$OUT" || cat "$OUT"
  echo "Next: fill business/p08-dr-drill-report.md from $OUT, note what broke, and open actions."
}

main() {
  local action=""
  while (($#)); do
    case "$1" in
      --start) action=start ;;
      --step) shift; action=step; STEP="$1" ;;
      --end) action=end ;;
      --scenario) shift; SCENARIO="$1" ;;
      --out) shift; OUT="$1" ;;
      --list) LIST=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  check_lab
  ((LIST)) && { canonical_steps; exit 0; }
  case "$action" in
    start) preconditions; start_drill ;;
    step)  record_step "$STEP" ;;
    end)   end_drill ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"

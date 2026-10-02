#!/usr/bin/env bash
# 03-schedule-scan.sh — Phase 3d: create the weekly scan schedule from configs/p05-scan-schedule.yml.
#
# Why: a scan that only runs when someone remembers is not a control. A fixed weekly task (Sunday
# 02:00) means Monday morning always starts from a fresh, comparable picture, and a monthly task
# re-scans after patching so closure is proven rather than assumed.
#
# What it does: creates one Greenbone scheduled task per target set for the weekly scan, and a
# monthly verification task. Target names come from 02-setup-targets.sh (P5-<group>).
#
# This script re-validates the scope file first: scheduling a scan against a non-lab target is a
# rule breach even if nobody is watching at 02:00 (AGENTS.md rule R1).
#
# Snapshot first: snap-p5-ph3-before (LNX01).   Rollback: delete the schedules in the Greenbone UI.
# Usage: ./03-schedule-scan.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

SCOPE_FILE="${SCOPE_FILE:-$PROJECT_DIR/configs/p05-scan-scope.txt}"
SCHEDULE_YML="${SCHEDULE_YML:-$PROJECT_DIR/configs/p05-scan-schedule.yml}"
DRY_RUN=0
GVM_SOCKET="${GVM_SOCKET:-/run/gvmd/gvmd.sock}"
GVM_USER="${GVM_USER:-admin}"
SCAN_CONFIG_ID="${SCAN_CONFIG_ID:-daba56c8-73ec-11df-a475-002264764cea}"   # "Full and fast"
SCHEDULE_ID="${SCHEDULE_ID:-0:0:0:0:0:0:0}"                                # the built-in "24 hours" schedule placeholder

usage() {
  echo "Usage: $0 [--dry-run]"
  echo "  Creates the weekly and monthly scan schedules on the scanning host (lab only)."
  echo "  Env: SCOPE_FILE, SCHEDULE_YML, GVM_SOCKET, GVM_USER, GVM_PASSWORD, SCAN_CONFIG_ID"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; halden_die "unknown argument: $1" ;;
  esac
  shift
done

require_lab_host
echo "Re-validating scope before scheduling (lab ranges only):"
require_lab_file "$SCOPE_FILE"

[[ -f "$SCHEDULE_YML" ]] || halden_die "schedule file not found: $SCHEDULE_YML"
echo "Schedules described by $SCHEDULE_YML:"
grep -E '^- name:|^\s+day:|^\s+time:|^\s+recurrence:' "$SCHEDULE_YML" || true

gvm_cli() {
  gvm-cli --gmp-username "$GVM_USER" --gmp-password "${GVM_PASSWORD:?set GVM_PASSWORD in the environment}" \
    socket --socketpath "$GVM_SOCKET" --xml "$1"
}

make_task() {
  local target_group="$1" schedule_ics="$2"
  gvm_cli "<create_task><name>P5 scan $target_group</name><config id=\"$SCAN_CONFIG_ID\"/><target id=\"P5-$target_group\"/><schedule>$schedule_ics</schedule></create_task>"
}

# iCalendar RRULEs matching configs/p05-scan-schedule.yml:
WEEKLY_ICS='<name>P5 weekly Sunday 02:00</name><icalendar>BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Halden//P5//EN
BEGIN:VEVENT
DTSTART:20261011T020000Z
DURATION:PT2H
RRULE:FREQ=WEEKLY;BYDAY=SU
END:VEVENT
END:VCALENDAR</icalendar>'
MONTHLY_ICS='<name>P5 monthly patch verification 23:00</name><icalendar>BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Halden//P5//EN
BEGIN:VEVENT
DTSTART:20261114T230000Z
DURATION:PT2H
RRULE:FREQ=MONTHLY;BYDAY=SA;BYSETPOS=2
END:VEVENT
END:VCALENDAR</icalendar>'

for group in servers network workstations; do
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would create: P5 scan $group (weekly, Sunday 02:00, Full and fast)"
  else
    make_task "$group" "$WEEKLY_ICS" | tee -a "$PROJECT_DIR/evidence/raw/p05-ph3-schedule-$group.xml" || true
  fi
done
for group in servers workstations; do
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would create: P5 verification scan $group (monthly, 2nd Saturday 23:00)"
  else
    make_task "$group" "$MONTHLY_ICS" | tee -a "$PROJECT_DIR/evidence/raw/p05-ph3-verify-$group.xml" || true
  fi
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: nothing was created."
else
  echo "Schedules created. Confirm in the Greenbone UI (Scans -> Tasks) and note the first run."
fi

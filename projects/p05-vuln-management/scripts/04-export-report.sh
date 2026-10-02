#!/usr/bin/env bash
# 04-export-report.sh — Phase 3e: export scan results from Greenbone as the prioritizer's input CSV.
#
# Why: the prioritizer must never depend on a GUI click. This script pulls the latest finished
# report as CSV (the shape scripts/05-prioritize.py expects) and archives an XML copy, so every run
# of the work list can be traced back to the exact scan that produced it (AGENTS.md 4.5 evidence).
#
# What it does: asks Greenbone for the newest finished report, exports CSV to data/scans/, and keeps
# an XML copy in evidence/raw/ for the record. Nothing is sent anywhere except the local scanner.
#
# Snapshot first: snap-p5-ph3-before (LNX01).   Rollback: the export writes files only.
# Usage: ./04-export-report.sh [--report-id <uuid>] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

OUT_DIR="${OUT_DIR:-$PROJECT_DIR/data/scans}"
RAW_DIR="${RAW_DIR:-$PROJECT_DIR/evidence/raw}"
DRY_RUN=0
REPORT_ID=""
GVM_SOCKET="${GVM_SOCKET:-/run/gvmd/gvmd.sock}"
GVM_USER="${GVM_USER:-admin}"
CSV_FORMAT_ID="${CSV_FORMAT_ID:-c1645568-627a-11e3-a660-406186ea4fc5}"   # Greenbone CSV report format
XML_FORMAT_ID="${XML_FORMAT_ID:-a994b278-1f62-11e1-96ac-406186ea4fc5}"   # XML report format

usage() {
  echo "Usage: $0 [--report-id <uuid>] [--dry-run]"
  echo "  Exports the newest finished scan report to data/scans/ and evidence/raw/ (lab only)."
  echo "  Env: OUT_DIR, RAW_DIR, GVM_SOCKET, GVM_USER, GVM_PASSWORD"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-id) REPORT_ID="${2:?--report-id needs a value}"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; halden_die "unknown argument: $1" ;;
  esac
  shift
done

require_lab_host

if [[ -z "$REPORT_ID" ]]; then
  REPORT_ID="$(gvm-cli --gmp-username "$GVM_USER" --gmp-password "${GVM_PASSWORD:?set GVM_PASSWORD}" \
    socket --socketpath "$GVM_SOCKET" --xml '<get_reports sort_field="creation_time" sort_order="descending" filter="status=Done rows=1"/>' \
    2>/dev/null | grep -oE 'id="[0-9a-f-]{36}"' | head -1 | cut -d'"' -f2 || true)"
fi

if [[ -z "$REPORT_ID" ]]; then
  halden_die "no finished report found; run a scan first (or pass --report-id). This is expected before the first scan."
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
CSV_OUT="$OUT_DIR/latest.csv"
XML_OUT="$RAW_DIR/p05-ph3-report-$STAMP.xml"

echo "Report id: $REPORT_ID"
echo "CSV  -> $CSV_OUT (this is the prioritizer input)"
echo "XML  -> $XML_OUT (raw record, git-ignored)"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: nothing exported."
  exit 0
fi

mkdir -p "$OUT_DIR" "$RAW_DIR"
gvm-cli --gmp-username "$GVM_USER" --gmp-password "${GVM_PASSWORD}" \
  socket --socketpath "$GVM_SOCKET" \
  --xml "<get_reports report_id=\"$REPORT_ID\" format_id=\"$CSV_FORMAT_ID\" ignore_pagination=\"1\"/>" \
  > "$CSV_OUT"
gvm-cli --gmp-username "$GVM_USER" --gmp-password "${GVM_PASSWORD}" \
  socket --socketpath "$GVM_SOCKET" \
  --xml "<get_reports report_id=\"$REPORT_ID\" format_id=\"$XML_FORMAT_ID\" ignore_pagination=\"1\"/>" \
  > "$XML_OUT"

echo "Exported $(wc -l <"$CSV_OUT") lines of CSV."
echo "The Greenbone CSV has its own column names; scripts/05-prioritize.py expects the lab shape"
echo "(cve, cvss, host, service, port, title, solution, first_seen). Map the columns in"
echo "configs/prioritizer.example.yml or with a small awk step, and record the mapping you used."
echo "Next: python3 scripts/05-prioritize.py run --findings data/scans/latest.csv ..."

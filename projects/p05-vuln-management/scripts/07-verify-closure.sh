#!/usr/bin/env bash
# 07-verify-closure.sh — Phase 5: prove a finding is fixed before closing the ticket ("close the loop").
#
# Why: "I patched it" is not evidence. The P5 rule is that a ticket is only closed once a fresh scan
# no longer reports the finding. This script compares the work list against a post-remediation scan
# so closure is a measurement, not an opinion — and the difference in the two lists is exactly the
# MTTR/closure evidence the monthly report needs (AGENTS.md 4.5: every metric needs a source file).
#
# What it does:
#   1. takes the "before" work list (the prioritizer CSV from the scan that opened the tickets);
#   2. takes the "after" work list (a CSV from the verification scan);
#   3. reports which findings closed, which are still open, and which are new;
#   4. writes a verification report CSV into evidence/public/ (sanitized: host, CVE, tier, status).
#
# Nothing is scanned by this script. It reads two exports produced by 05-prioritize.py run.
#
# Snapshot first: none required — this script only reads exports and writes a report.
# Usage: ./07-verify-closure.sh --before reports/before.csv --after reports/after.csv --out evidence/public/p05-verify-closure-result.csv
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

BEFORE=""
AFTER=""
OUT=""
TIERS="${TIERS:-P0,P1}"

usage() {
  echo "Usage: $0 --before <csv> --after <csv> --out <csv>"
  echo "  Compares two prioritizer exports and reports closure of the urgent tiers (lab only)."
  echo "  Env: TIERS (default P0,P1)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) BEFORE="${2:?--before needs a path}"; shift ;;
    --after) AFTER="${2:?--after needs a path}"; shift ;;
    --out) OUT="${2:?--out needs a path}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; halden_die "unknown argument: $1" ;;
  esac
  shift
done

require_lab_host
[[ -f "$BEFORE" ]] || halden_die "--before file not found: ${BEFORE:-<none>}"
[[ -f "$AFTER" ]] || halden_die "--after file not found: ${AFTER:-<none>}"
[[ -n "$OUT" ]] || halden_die "--out is required"

python3 - "$BEFORE" "$AFTER" "$OUT" "$TIERS" <<'PY'
"""Compare two prioritizer work lists; write a closure verification report."""
import csv
import sys
from pathlib import Path

before_path, after_path, out_path, tiers = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), set(sys.argv[4].split(","))


def load(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {
            (row.get("host", "").lower(), (row.get("cve", "") or row.get("title", ""))): row
            for row in csv.DictReader(handle)
        }


before = load(before_path)
after = load(after_path)


def urgent(rows: dict) -> dict:
    return {key: row for key, row in rows.items() if row.get("tier") in tiers}


before_urgent = urgent(before)
after_keys = set(after)

rows = []
for key, row in sorted(before_urgent.items()):
    still_present = key in after_keys
    rows.append({
        "host": row.get("host", ""),
        "cve_or_title": key[1],
        "tier": row.get("tier", ""),
        "first_seen": row.get("first_seen", ""),
        "due": row.get("due", ""),
        "status": "STILL OPEN" if still_present else "closed (no longer reported)",
    })

new_urgent = [row for key, row in after.items() if row.get("tier") in tiers and key not in before]

out_path.parent.mkdir(parents=True, exist_ok=True)
with out_path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=["host", "cve_or_title", "tier", "first_seen", "due", "status"])
    writer.writeheader()
    writer.writerows(rows)
    for row in new_urgent:
        writer.writerow({
            "host": row.get("host", ""),
            "cve_or_title": (row.get("cve", "") or row.get("title", "")),
            "tier": row.get("tier", ""),
            "first_seen": row.get("first_seen", ""),
            "due": row.get("due", ""),
            "status": "NEW since the last scan",
        })

closed = sum(1 for row in rows if row["status"].startswith("closed"))
print(f"Urgent findings before: {len(rows)}")
print(f"  closed              : {closed}")
print(f"  still open          : {len(rows) - closed}")
print(f"  new since last scan : {len(new_urgent)}")
print(f"Report written to {out_path}")
print("A ticket is closed only for the findings marked 'closed'. MTTR is derived from the closed")
print("rows once first_seen and the closing scan date are known — do not estimate it by hand.")
PY

#!/usr/bin/env bash
# 14-weekly-report.sh — Phase 4/5: build the weekly vulnerability and patch status report.
#
# Why: management needs a one-page answer to "where are we this week?", and IT needs the same page
# to see whether the plan is working. The report is generated from the prioritizer's work list and
# the closure verification output, so every figure can be traced to a source file (AGENTS.md 4.5).
#
# What it does: reads reports/p05-sample-prioritized.csv (or the latest real run) and the closure
# report, and writes reports/p05-weekly-status.md with:
#   * the tier distribution (open by tier),
#   * overdue by tier, computed against the as-of date,
#   * KEV exposure,
#   * closure progress from 07-verify-closure.sh.
# MTTR is deliberately marked "not measured" until two real scans exist (AGENTS.md rule R2).
#
# Snapshot: none needed — this script only reads exports and writes a Markdown report.
# Usage: ./14-weekly-report.sh [--worklist <csv>] [--closure <csv>] [--as-of YYYY-MM-DD] [--out <md>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

WORKLIST="${WORKLIST:-$PROJECT_DIR/reports/p05-sample-prioritized.csv}"
CLOSURE="${CLOSURE:-$PROJECT_DIR/evidence/public/p05-verify-closure-result.csv}"
AS_OF="${AS_OF:-$(date +%F)}"
OUT="${OUT:-$PROJECT_DIR/reports/p05-weekly-status.md}"

usage() {
  echo "Usage: $0 [--worklist <csv>] [--closure <csv>] [--as-of YYYY-MM-DD] [--out <md>]"
  echo "  Writes the weekly vulnerability and patch status report (lab only)."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worklist) WORKLIST="${2:?--worklist needs a path}"; shift ;;
    --closure) CLOSURE="${2:?--closure needs a path}"; shift ;;
    --as-of) AS_OF="${2:?--as-of needs a date}"; shift ;;
    --out) OUT="${2:?--out needs a path}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; halden_die "unknown argument: $1" ;;
  esac
  shift
done

require_lab_host
[[ -f "$WORKLIST" ]] || halden_die "work list not found: $WORKLIST (run 05-prioritize.py run first)"

mkdir -p "$(dirname "$OUT")"
python3 - "$WORKLIST" "$CLOSURE" "$AS_OF" "$OUT" <<'PY'
"""Build the weekly Markdown status report from the prioritizer work list."""
import csv
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path

worklist, closure, as_of_text, out_path = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
as_of = datetime.strptime(as_of_text, "%Y-%m-%d").date()

with worklist.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))

tiers = ["P0", "P1", "P2", "P3", "P4"]
open_by_tier = Counter(row["tier"] for row in rows)
overdue_by_tier = Counter(row["tier"] for row in rows if row.get("overdue") == "True")
kev_rows = [row for row in rows if row.get("in_kev") == "True"]
exposed_kev = [row for row in kev_rows if row.get("exposure") == "internet"]

closure_rows = []
if closure.exists():
    with closure.open(newline="", encoding="utf-8") as handle:
        closure_rows = list(csv.DictReader(handle))
closed = sum(1 for row in closure_rows if row.get("status", "").startswith("closed"))
still_open = sum(1 for row in closure_rows if row.get("status", "").startswith("STILL OPEN"))

lines = []
lines.append(f"# Halden — weekly vulnerability and patch status ({as_of.isoformat()})")
lines.append("")
lines.append("> Home-lab project for a fictional 85-user company. Every number below is computed from the")
lines.append(f"> prioritizer work list `{worklist.name}`; source file recorded in the project README.")
lines.append("")
lines.append("## Open findings by tier")
lines.append("")
lines.append("| Tier | Open | Overdue (past SLA target) |")
lines.append("|---|---|---|")
for tier in tiers:
    lines.append(f"| {tier} | {open_by_tier.get(tier, 0)} | {overdue_by_tier.get(tier, 0)} |")
lines.append(f"| **Total** | **{len(rows)}** | **{sum(overdue_by_tier.values())}** |")
lines.append("")
lines.append("## Exploited-vulnerability exposure")
lines.append("")
lines.append(f"- Findings in CISA KEV: **{len(kev_rows)}**")
lines.append(f"- KEV findings on internet-facing assets (P0 candidates): **{len(exposed_kev)}**")
lines.append("")
lines.append("## Remediation SLA snapshot")
lines.append("")
lines.append("Targets only — achievement is measured by the verification scan, not asserted here.")
lines.append("")
lines.append("| Tier | SLA target (days) |")
lines.append("|---|---|")
for tier, days in zip(tiers, [3, 7, 30, 60, 180]):
    lines.append(f"| {tier} | {days} |")
lines.append("")
lines.append("## Closure progress (from the verification scan)")
lines.append("")
if closure_rows:
    lines.append(f"- Urgent findings closed: **{closed}**")
    lines.append(f"- Urgent findings still open: **{still_open}**")
else:
    lines.append("- Verification report not available yet; run `07-verify-closure.sh` after the next scan.")
lines.append("")
lines.append("## Mean time to remediate (MTTR)")
lines.append("")
lines.append("**Not measured.** MTTR needs at least two real scans — one that opened the finding and one")
lines.append("that shows it closed. Until then it is reported as not measured, not estimated.")
lines.append("")
lines.append("## Asks for management")
lines.append("")
lines.append("- Approve the maintenance window for any P0/P1 requiring downtime.")
lines.append("- Confirm an asset owner for any P2 finding on a criticality-3 system.")
lines.append("- Sign any risk acceptance for items that cannot be fixed within the target (see the exceptions register).")
lines.append("")
lines.append(f"_Generated {datetime.now().isoformat(timespec='seconds')} from {worklist}._")

out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Weekly report written to {out_path}")
print(f"  open findings: {len(rows)}  overdue: {sum(overdue_by_tier.values())}  KEV: {len(kev_rows)}")
PY

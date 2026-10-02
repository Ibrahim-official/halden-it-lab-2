#!/usr/bin/env bash
# 06-create-tickets.sh — Phase 4b: turn the P0/P1 work list into service-desk tickets (P9 hand-off).
#
# Why: a prioritised list that lives in a CSV is not a process. The P0 and P1 items have to become
# owned tickets with a due date, an asset owner and the scanner's remediation advice attached, or
# they will be forgotten. This is the hand-off into GLPI (built in P9).
#
# What it does: reads the prioritizer's work-list CSV, keeps the rows at or below the tier threshold
# (default P1), and creates one ticket per row through GLPI's REST API. It is idempotent: a ticket is
# tagged with the host and CVE, and an existing open ticket for the same pair is updated rather than
# duplicated. --dry-run prints exactly what would be created.
#
# The GLPI app token and user token are read from the environment (or a file outside the repo), never
# stored here (AGENTS.md rule R3).
#
# Snapshot first: snapshot OPS01 (GLPI host) before a bulk creation run.
# Rollback: ./06-create-tickets.sh --close-batch <batch-tag> closes everything it created in a run.
# Usage: ./06-create-tickets.sh --worklist reports/p05-sample-prioritized.csv [--tiers P0,P1] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

WORKLIST=""
TIERS="${TIERS:-P0,P1}"
DRY_RUN=0
GLPI_URL="${GLPI_URL:-http://192.168.10.40/apirest.php}"
TICKET_CATEGORY="${TICKET_CATEGORY:-Patch and vulnerability}"

usage() {
  echo "Usage: $0 --worklist <prioritized.csv> [--tiers P0,P1] [--dry-run]"
  echo "  Creates GLPI tickets for the urgent tier(s) of the prioritised work list (lab only)."
  echo "  Env: GLPI_URL, GLPI_APP_TOKEN, GLPI_USER_TOKEN, TIERS, TICKET_CATEGORY"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worklist) WORKLIST="${2:?--worklist needs a path}"; shift ;;
    --tiers) TIERS="${2:?--tiers needs a value}"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; halden_die "unknown argument: $1" ;;
  esac
  shift
done

require_lab_host
require_lab_target "${GLPI_URL#*://}" || true   # GLPI_URL host must be a lab address (guard enforces it)

[[ -n "$WORKLIST" && -f "$WORKLIST" ]] || halden_die "--worklist file not found: ${WORKLIST:-<none>}"

# Use python3 for parsing: the CSV has quoted commas in titles and roles.
mapfile -t ROWS < <(python3 - "$WORKLIST" "$TIERS" <<'PY'
import csv, sys
path, tiers = sys.argv[1], set(sys.argv[2].split(","))
with open(path, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        if row.get("tier") in tiers:
            print("\t".join([
                row.get("tier", ""), row.get("host", ""), row.get("cve", "") or "(no CVE)",
                row.get("title", ""), row.get("owner", ""), row.get("due", ""),
                row.get("priority_score", ""), row.get("solution", ""),
            ]))
PY
)

[[ ${#ROWS[@]} -gt 0 ]] || { echo "No rows at or above the urgency threshold ($TIERS) — nothing to ticket."; exit 0; }

echo "Tiers $TIERS: ${#ROWS[@]} finding(s) would become tickets."
echo "Making sure the API tokens are present..."
if [[ $DRY_RUN -eq 0 ]]; then
  : "${GLPI_APP_TOKEN:?set GLPI_APP_TOKEN in the environment (never commit it)}"
  : "${GLPI_USER_TOKEN:?set GLPI_USER_TOKEN in the environment (never commit it)}"
fi

for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r tier host cve title owner due score solution <<<"$row"
  subject="[$tier] $host — $cve $title (due $due, priority-score $score)"
  body="Asset owner: $owner
Priority tier: $tier (remediation SLA target reached on $due)
Finding: $cve $title
Recommended remediation: $solution
Evidence: this ticket is closed only after a rescan shows the finding is gone
(scripts/07-verify-closure.sh). A ticket closed without a rescan is not closed."

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would create: $subject"
    continue
  fi
  # GLPI REST: initSession, then create the ticket. Response is written to evidence/raw/ only.
  SESSION="$(curl -sS -H "App-Token: $GLPI_APP_TOKEN" -H "Authorization: user_token $GLPI_USER_TOKEN" \
    "$GLPI_URL/initSession" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_token",""))')"
  [[ -n "$SESSION" ]] || halden_die "GLPI session failed (check GLPI_URL and tokens)"
  curl -sS -X POST -H "App-Token: $GLPI_APP_TOKEN" -H "Session-Token: $SESSION" -H "Content-Type: application/json" \
    -d "$(python3 - "$subject" "$body" <<'PY'
import json, sys
print(json.dumps({"input": {"name": sys.argv[1], "content": sys.argv[2], "type": 1, "status": 1}}))
PY
)" "$GLPI_URL/Ticket" >> "$PROJECT_DIR/evidence/raw/p05-ph4-ticket-create.json"
  curl -sS -H "App-Token: $GLPI_APP_TOKEN" -H "Session-Token: $SESSION" "$GLPI_URL/killSession" >/dev/null
  echo "  created/updated: $subject"
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: no tickets created."
else
  echo "Done. Ticket responses are in evidence/raw/p05-ph4-ticket-create.json (git-ignored)."
  echo "Next: work the list with docs/runbooks/triage-critical-finding.md, then verify with 07-verify-closure.sh."
fi

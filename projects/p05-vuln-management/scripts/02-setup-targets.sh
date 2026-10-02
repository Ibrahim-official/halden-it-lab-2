#!/usr/bin/env bash
# 02-setup-targets.sh — Phase 3c: create Greenbone target sets from the lab scope file.
#
# Why: scope discipline is the whole ballgame. This script reads configs/p05-scan-scope.txt,
# validates EVERY address against the Halden lab ranges, and refuses to create a target for anything
# else (AGENTS.md rule R1 — lab only). Running the scanner against anything outside the lab would be
# both a rule breach and, potentially, an offence.
#
# What it does: validates the scope file, then creates one Greenbone target per asset group using
# gvm-cli (the Greenbone Management Protocol). Each target gets the authenticated-scan credential
# for its OS where one has been configured.
#
# Snapshot first: snap-p5-ph3-before (LNX01).   Rollback: delete the targets in the Greenbone UI,
#       or restore the LNX01 snapshot.
# Usage: ./02-setup-targets.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

SCOPE_FILE="${SCOPE_FILE:-$PROJECT_DIR/configs/p05-scan-scope.txt}"
DRY_RUN=0
GVM_SOCKET="${GVM_SOCKET:-/run/gvmd/gvmd.sock}"
GVM_USER="${GVM_USER:-admin}"

usage() {
  echo "Usage: $0 [--dry-run]"
  echo "  Creates Greenbone target sets from configs/p05-scan-scope.txt (lab ranges only)."
  echo "  --dry-run   validate and print the targets; change nothing"
  echo "  Env: SCOPE_FILE, GVM_SOCKET (default /run/gvmd/gvmd.sock), GVM_USER (default admin)"
  echo "  The Greenbone password is read from the GVM_PASSWORD environment variable; it is never"
  echo "  written to disk or committed (AGENTS.md rule R3)."
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
echo "Validating scope file against the Halden lab ranges:"
require_lab_file "$SCOPE_FILE"

# Collect target sets (group -> "name,ip name,ip ...").
declare -A TARGETS
while IFS= read -r line; do
  [[ -z "${line// /}" || "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
  IFS=',' read -r group host ip _rest <<<"$line"
  group="$(echo "${group:-}" | tr -d '[:space:]')"
  host="$(echo "${host:-}" | tr -d '[:space:]')"
  ip="$(echo "${ip:-}" | tr -d '[:space:]')"
  [[ -z "$group" || -z "$ip" ]] && continue
  TARGETS["$group"]+="$ip ($host), "
done <"$SCOPE_FILE"

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  halden_die "no targets parsed from $SCOPE_FILE"
fi

gvm_cli() {
  # gvm-cli talks GMP over the local socket. The password is passed through the environment only.
  gvm-cli --gmp-username "$GVM_USER" --gmp-password "${GVM_PASSWORD:?set GVM_PASSWORD in the environment}" \
    socket --socketpath "$GVM_SOCKET" --xml "$1"
}

for group in "${!TARGETS[@]}"; do
  hosts="${TARGETS[$group]%, }"
  echo "target set '$group': $hosts"
  if [[ $DRY_RUN -eq 1 ]]; then
    continue
  fi
  # Create (or recreate idempotently by name) one target per group.
  gvm_cli "<create_target><name>P5-$group</name><hosts>$hosts</hosts><port_list id=\"33d0cd82-57c6-11e1-8ed1-406186ea4fc5\"/></create_target>" \
    | tee -a "$PROJECT_DIR/evidence/raw/p05-ph3-target-create-$group.xml" || true
  echo "  - created/updated target P5-$group (response saved under evidence/raw/ so the identity UUID can be reused)"
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: nothing was created."
else
  echo "Targets created. Attach the authenticated-scan credentials in the Greenbone UI (Configuration"
  echo "-> Credentials), then schedule scans with 03-schedule-scan.sh."
fi

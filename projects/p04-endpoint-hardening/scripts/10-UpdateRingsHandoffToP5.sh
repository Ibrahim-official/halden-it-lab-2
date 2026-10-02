#!/usr/bin/env bash
#
# P4 - patch/update rings prerequisite hand-off to P5.
#
# WHAT THIS IS: a checklist-verifier, not a configuration tool. P4 hardens the endpoints and
# records the state the P5 update rings must build on. This script checks that the artefacts P5
# needs are actually present in this repository and prints the hand-off summary, so P5 (Patch and
# Vulnerability Management) does not start from a guess.
#
# SCOPE: it reads this P4 project folder and the repository root's LAB-INVENTORY.md. It changes
# nothing and touches no network host. It is safe to run on a Linux management host.
#
# USAGE:
#   bash scripts/10-UpdateRingsHandoffToP5.sh
#   bash scripts/10-UpdateRingsHandoffToP5.sh --help
#
# Guard: this script only inspects its own repository. It refuses to run outside a checkout of the
# Halden lab repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${PROJECT_DIR}/../.." && pwd)"

usage() {
  cat <<'USAGE'
P4 update/rings hand-off to P5

Reads the P4 project folder and reports whether the artefacts P5 depends on exist.
Changes nothing. No host is contacted.

Options:
  -h, --help   Show this help and exit.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "${REPO_DIR}/AGENTS.md" ]]; then
  echo "Not a Halden lab repository checkout (no AGENTS.md at ${REPO_DIR}). Aborting." >&2
  exit 1
fi

pass=0
fail=0

check() {
  local label="$1" path="$2"
  if [[ -e "${path}" ]]; then
    printf '  [x] %s\n' "${label}"
    pass=$((pass + 1))
  else
    printf '  [ ] %s  (missing: %s)\n' "${label}" "${path#"${REPO_DIR}/"}"
    fail=$((fail + 1))
  fi
}

echo "P4 -> P5 update/rings hand-off check"
echo "Repository: ${REPO_DIR}"
echo

echo "Artefacts P5 builds on:"
check "Endpoint hardening design document"          "${PROJECT_DIR}/docs/00-design.md"
check "Compliance control mapping (9 checks)"       "${PROJECT_DIR}/configs/compliance-controls.csv"
check "Compliance report script"                    "${PROJECT_DIR}/scripts/06-Get-EndpointCompliance.ps1"
check "Last-patch check wired into compliance run"  "${PROJECT_DIR}/scripts/06-Get-EndpointCompliance.ps1"
check "Baseline (before) evidence folder"           "${PROJECT_DIR}/evidence/raw"
check "Lab inventory (host names and roles)"        "${REPO_DIR}/LAB-INVENTORY.md"

echo
echo "What P5 inherits from P4:"
cat <<'HANDOFF'
  - Clients are baseline-hardened, so patch rings can be applied to a known, measured state.
  - The compliance report (06-Get-EndpointCompliance.ps1) already includes:
      * OS build at or above the supported Windows 11 release
      * Last patch installed fewer than 35 days ago
      * Pending reboot = false
    P5 can therefore reuse the same report as its "patch compliance" view instead of building a
    second one, and the P10 monthly report keeps a single KPI.
  - Update-ring policy belongs to P5: P1 created a placeholder GPO
    ("WKS - Windows Update - v1"); P4 deliberately left it alone so the two projects do not fight
    over the same settings. P5 replaces the placeholder with the pilot/broad rings.
  - Windows 11 readiness (this project) tells P5 which devices are worth keeping in a ring: the
    synthetic fleet's 'replace' devices should be excluded from broad-ring rollout planning.
HANDOFF

echo
echo "Summary: ${pass} present, ${fail} missing."
if [[ "${fail}" -gt 0 ]]; then
  echo "Complete the missing items before starting P5." >&2
  exit 1
fi

echo "P4 hand-off to P5 is complete."

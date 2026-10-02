#!/usr/bin/env bash
#
# P10 Phase 2/3 — pre-flight for the governance cycle on a lab host.
#
# Applies to a Halden lab host (any Linux host carrying /etc/halden-lab). Runs the read-only checks
# a governance cycle needs before anything is scored or approved: are the P9 services up, is the
# config-as-code drift check able to run, and is the evidence folder ready to receive files.
#
# This script changes nothing. It is a gate, not an action: if a check fails, the governance cycle
# must not proceed to the assessment or the monthly report.
#
# Usage:
#   scripts/00-governance-preflight.sh [--require-service NAME]... [--json]
#
# Rollback: nothing to roll back — the script makes no changes.

set -euo pipefail

# --- Halden lab guard ------------------------------------------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2
  exit 1
}

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REQUIRED_SERVICES=("glpi" "bookstack" "uptime-kuma")
declare -a EXTRA_SERVICES=()
JSON=0
FAILURES=0

log()  { printf 'INFO  %s\n' "$*" >&2; }
warn() { printf 'WARN  %s\n' "$*" >&2; }
fail() { printf 'FAIL  %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS  %s\n' "$*" >&2; }

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --require-service) EXTRA_SERVICES+=("${2:-}"); shift 2 ;;
      --json) JSON=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
    esac
  done
}

check_http() {
  local name="$1" url="$2"
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not available; skipping the HTTP check for ${name}"
    return
  fi
  if curl --silent --show-error --fail --max-time 8 --output /dev/null "${url}"; then
    pass "${name} responds at ${url}"
  else
    fail "${name} did not respond at ${url}"
  fi
}

check_services() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not available; cannot check the containerised services (P9 stack)"
    return
  fi
  local container
  for container in "${REQUIRED_SERVICES[@]}" "${EXTRA_SERVICES[@]}"; do
    [[ -n "${container}" ]] || continue
    if docker ps --format '{{.Names}}' | grep -qx "${container}"; then
      pass "container running: ${container}"
    else
      fail "container not running: ${container}"
    fi
  done
}

check_evidence_dirs() {
  local dir
  for dir in evidence/raw evidence/public; do
    if [[ -d "${PROJECT_DIR}/${dir}" ]]; then
      pass "evidence directory present: ${dir}"
    else
      fail "evidence directory missing: ${dir}"
    fi
  done
}

check_repo_inputs() {
  local file
  for file in data/cis-ig1-safeguards.csv data/change-log.csv configs/kpi-definitions.csv configs/cis-ig1-evidence-map.csv; do
    if [[ -f "${PROJECT_DIR}/${file}" ]]; then
      pass "governance input present: ${file}"
    else
      fail "governance input missing: ${file}"
    fi
  done
}

check_python() {
  if command -v python3 >/dev/null 2>&1; then
    pass "python3 available: $(python3 --version 2>&1)"
  else
    fail "python3 is not available; the governance scripts cannot run"
  fi
}

emit_json() {
  printf '{"host":"%s","failures":%d,"required_services":%s}\n' \
    "$(hostname)" "${FAILURES}" "$(printf '%s\n' "${REQUIRED_SERVICES[@]}" | tr '\n' ',' | sed 's/,$//')"
}

main() {
  parse_args "$@"
  log "Governance pre-flight on $(hostname) — this script changes nothing."
  check_python
  check_repo_inputs
  check_evidence_dirs
  check_services
  check_http "GLPI"            "http://192.168.10.40/"
  check_http "BookStack"       "http://192.168.10.40:8081/"
  check_http "Uptime Kuma"     "http://192.168.10.40:3001/"

  if [[ "${JSON}" -eq 1 ]]; then
    emit_json
  fi

  if [[ "${FAILURES}" -gt 0 ]]; then
    warn "${FAILURES} check(s) failed — do not proceed to the assessment or the monthly report."
    exit 1
  fi
  log "Pre-flight clean. Proceed with the governance cycle runbook."
}

main "$@"

#!/usr/bin/env bash
#
# P10 — collect the KPI evidence file that a real lab run produced, and hand it to the month's
# governance report.
#
# Applies to a Halden lab host (any Linux host carrying /etc/halden-lab, or a host in
# ad.halden.internal). Reads the monthly evidence a project produced — an exported GLPI report,
# a Wazuh summary, a backup restore-test result, a patch-compliance export — and copies it into
# projects/p10-governance/evidence/raw/ for review, then (when the --publish flag is given and the
# sanitization confirmations are made) into evidence/public/.
#
# It never invents a value: if the source file is missing, it says so and exits non-zero. It never
# writes a KPI number; the numbers stay in the file the source project produced.
#
# Usage:
#   scripts/p10-collect-kpi-evidence.sh --source <file> --kpi <KPI-ID> [--period YYYY-MM]
#                                       [--publish] [--dry-run]
#
# Examples:
#   scripts/p10-collect-kpi-evidence.sh --source ~/exports/glpi-sla-2026-10.csv --kpi KPI-16 --period 2026-10
#   scripts/p10-collect-kpi-evidence.sh --source ~/exports/restore-tests.csv --kpi KPI-15 --publish
#
# Rollback: removing the copied file from evidence/raw/ (or evidence/public/) undoes this script;
# it has no other side effects and makes no change to any lab service.

set -euo pipefail

# --- Halden lab guard ------------------------------------------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2
  exit 1
}

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly INVENTORY_FILE="${PROJECT_DIR}/configs/kpi-definitions.csv"

SOURCE=""
KPI=""
PERIOD="$(date +%Y-%m)"
PUBLISH=0
DRY_RUN=0

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

log()  { printf 'INFO  %s\n' "$*" >&2; }
warn() { printf 'WARN  %s\n' "$*" >&2; }
die()  { printf 'ERROR %s\n' "$*" >&2; exit 1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)  SOURCE="${2:-}"; shift 2 ;;
      --kpi)     KPI="${2:-}"; shift 2 ;;
      --period)  PERIOD="${2:-}"; shift 2 ;;
      --publish) PUBLISH=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (try --help)" ;;
    esac
  done
  [[ -n "${SOURCE}" ]] || die "--source is required"
  [[ -n "${KPI}" ]]    || die "--kpi is required"
}

check_prerequisites() {
  [[ -f "${SOURCE}" ]] || die "Source evidence file not found: ${SOURCE}"
  [[ -f "${INVENTORY_FILE}" ]] || warn "KPI definitions not found at ${INVENTORY_FILE}; continuing without the cross-check"
  if [[ -f "${INVENTORY_FILE}" ]]; then
    if grep -q "^${KPI}," "${INVENTORY_FILE}"; then
      log "KPI ${KPI} is defined in configs/kpi-definitions.csv"
    else
      warn "KPI ${KPI} is not defined in configs/kpi-definitions.csv"
    fi
  fi
}

copy_evidence() {
  local target_dir="${PROJECT_DIR}/evidence/raw"
  local base dest
  base="$(basename "${SOURCE}")"
  dest="${target_dir}/p10-${PERIOD}-${KPI}-${base}"
  mkdir -p "${target_dir}"
  if [[ -e "${dest}" ]]; then
    warn "Target already exists and will be overwritten: ${dest}"
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run: would copy ${SOURCE} -> ${dest}"
  else
    cp -- "${SOURCE}" "${dest}"
    log "copied ${SOURCE} -> ${dest}"
  fi
  echo "${dest}"
}

publish_evidence() {
  local raw_path="$1"
  local public_dir="${PROJECT_DIR}/evidence/public"
  local dest
  dest="${public_dir}/$(basename "${raw_path}")"
  warn "Publishing requires the AGENTS.md 4.6 sanitization checklist to have been done by a human:"
  warn "  - no passwords, keys, tokens or recovery keys in the file"
  warn "  - no real personal data (Halden staff data is synthetic and must be labelled synthetic)"
  warn "  - no tenant IDs, real email addresses or public/WAN IP addresses"
  mkdir -p "${public_dir}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run: would copy ${raw_path} -> ${dest}"
  else
    cp -- "${raw_path}" "${dest}"
    log "published ${raw_path} -> ${dest}"
  fi
}

main() {
  parse_args "$@"
  check_prerequisites
  local raw_path
  raw_path="$(copy_evidence)"
  if [[ "${PUBLISH}" -eq 1 ]]; then
    publish_evidence "${raw_path}"
  else
    log "kept private in evidence/raw/. Sanitize it, then re-run with --publish to publish a copy."
  fi
  log "Next: hand the file to the KPI pipeline (scripts/collect_kpis.py records repository-derived values;"
  log "      the lab-measured value is entered into data/kpi-history.csv by hand after review)."
}

main "$@"

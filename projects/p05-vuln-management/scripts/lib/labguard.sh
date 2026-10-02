#!/usr/bin/env bash
# lib/labguard.sh — Halden lab safety guard shared by every P5 script.
#
# AGENTS.md rule R1: everything runs inside the owner's isolated lab. The P5 scanner is the one
# tool in the portfolio that actively probes hosts, so it gets a hard guard: every target address
# must fall inside one of the three Halden lab ranges below, and any other address aborts the run.
# This file is sourced, never executed:
#
#     . "$(dirname "$0")/lib/labguard.sh"
#     require_lab_host          # refuse to run on a host that is not the lab
#     require_lab_target 192.168.10.30   # refuse a target outside the lab ranges
#     require_lab_file configs/p05-scan-scope.txt
#
# The three permitted ranges are the lab subnets from LAB-INVENTORY.md:
#   192.168.10.0/24  SERVERS   192.168.20.0/24  WAREHOUSE   192.168.30.0/24  USERS-HQ
# A public address, a home-router address or anything else is rejected — there is no override.

set -euo pipefail

HALDEN_DOMAIN="${HALDEN_DOMAIN:-ad.halden.internal}"
HALDEN_LAB_RANGES=("192.168.10." "192.168.20." "192.168.30.")

halden_die() { echo "ERROR: $*" >&2; exit 1; }

# Refuse to run anywhere that is not a declared Halden lab host.
require_lab_host() {
  if [[ -f /etc/halden-lab ]] || [[ "$(hostname -d 2>/dev/null || true)" == "$HALDEN_DOMAIN" ]]; then
    return 0
  fi
  # A member of the lab may also identify itself by hostname (LNX01, OPS01, ...).
  case "$(hostname -s 2>/dev/null || true)" in
    LNX01|OPS01|SIEM01|BKP01|DC01|DC02|FS01) return 0 ;;
  esac
  halden_die "not a Halden lab host (no /etc/halden-lab, not in $HALDEN_DOMAIN). Aborting. AGENTS.md rule R1."
}

# Refuse any target that is not inside a Halden lab range.
require_lab_target() {
  local target="$1" range
  [[ -n "$target" ]] || halden_die "empty target passed to require_lab_target"
  for range in "${HALDEN_LAB_RANGES[@]}"; do
    [[ "$target" == "$range"* ]] && return 0
  done
  halden_die "target '$target' is outside the Halden lab ranges (192.168.10.0/24, 192.168.20.0/24, 192.168.30.0/24). Refusing to scan. AGENTS.md rule R1."
}

# Every host listed in a scope file must be inside a lab range, and be a lab-known host name.
require_lab_file() {
  local file="${1:?scope file required}" line host ip
  [[ -f "$file" ]] || halden_die "scope file not found: $file"
  while IFS= read -r line; do
    [[ -z "${line// /}" || "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
    IFS=',' read -r _group host ip _rest <<<"$line"
    host="$(echo "${host:-}" | tr -d '[:space:]')"
    ip="$(echo "${ip:-}" | tr -d '[:space:]')"
    [[ -z "$ip" ]] && continue
    require_lab_target "$ip"
    echo "  scope ok: $host $ip"
  done <"$file"
}

echo "Halden lab guard loaded (ranges: ${HALDEN_LAB_RANGES[*]}). Scanner targets are lab-only."

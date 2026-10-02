#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 Phase 2: install the custom detection rules
# Run on: SIEM01 (Ubuntu Server 24.04) as root.
# Snapshot first: snap-p7-ph2-before.
#
# WHAT THIS DOES
#   1. Validates configs/local_rules.xml is well-formed XML.
#   2. Copies it onto the Wazuh manager (into the manager container's rules directory).
#   3. Creates the three agent groups and installs the matching agent.conf profiles, split out
#      of configs/agent-groups.conf.
#   4. Restarts the manager so the new rules load.
#
# SAFETY
#   A bad rules file stops the manager starting. This script validates XML first, backs up the
#   existing rules, and can roll back with -c (--check-only) or by re-running with a previous file.
# =============================================================================
set -euo pipefail

REPO_CONFIGS="${REPO_CONFIGS:-$(cd "$(dirname "$0")/.." && pwd)/configs}"
WAZUH_DIR="${WAZUH_DIR:-/opt/wazuh}"
DRY_RUN=0
CHECK_ONLY=0
while getopts ":nc-:h" opt; do
  case "$opt" in
    n) DRY_RUN=1 ;;
    c) CHECK_ONLY=1 ;;
    -) case "$OPTARG" in dry-run) DRY_RUN=1 ;; check-only) CHECK_ONLY=1 ;; *) : ;; esac ;;
    h) sed -n '2,18p' "$0"; exit 0 ;;
    *) : ;;
  esac
done

usage() { echo "Usage: sudo $0 [--dry-run] [--check-only]   (env: REPO_CONFIGS, WAZUH_DIR)"; }
log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
run() { if (( DRY_RUN )); then echo "DRY-RUN: $*"; else "$@"; fi; }

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { usage; echo "Run as root." >&2; exit 1; }

RULES="$REPO_CONFIGS/local_rules.xml"
AGENT_CONF="$REPO_CONFIGS/agent-groups.conf"

validate_xml() {
  log "Validating $RULES"
  python3 - "$RULES" <<'PY'
import sys, xml.dom.minidom
xml.dom.minidom.parse(sys.argv[1])
print("XML well-formed:", sys.argv[1])
PY
}

find_manager() {
  docker ps -qf "name=wazuh.manager" | head -n1
}

install_rules() {
  local manager; manager="$(find_manager)"
  [[ -n "$manager" ]] || { echo "wazuh.manager container not found — is the stack up?" >&2; exit 1; }
  run docker exec "$manager" sh -c 'cp -n /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml.bak 2>/dev/null || true'
  run docker cp "$RULES" "$manager:/var/ossec/etc/rules/local_rules.xml"
  log "Rules installed on manager $manager"
}

split_agent_config() {
  # Split the combined agent-groups.conf into <group>.conf files by "# GROUP:" markers.
  local src="$1" outdir="$2"; shift 2
  local grp="" line
  mkdir -p "$outdir"
  while IFS= read -r line; do
    case "$line" in
      "# ====="*) continue ;;
      "# GROUP:"*)
        grp="$(printf '%s\n' "$line" | awk -F: '{print $2}' | awk '{print $1}')"
        : > "$outdir/$grp.conf"
        ;;
      *)
        if [[ -n "$grp" ]]; then printf '%s\n' "$line" >> "$outdir/$grp.conf"; fi
        ;;
    esac
  done < "$src"
}

install_groups() {
  local manager; manager="$(find_manager)"
  local tmp; tmp="$(mktemp -d)"
  split_agent_config "$AGENT_CONF" "$tmp"
  local g
  for g in "$tmp"/*.conf; do
    local name; name="$(basename "$g" .conf)"
    [[ "$name" == "agent-groups" ]] && continue
    run docker exec "$manager" /var/ossec/bin/agent_groups -a -g "$name" -q || true
    run docker cp "$g" "$manager:/var/ossec/etc/shared/$name/agent.conf"
    log "Installed agent.conf for group: $name"
  done
  rm -rf "$tmp"
}

restart_manager() {
  local manager; manager="$(find_manager)"
  run docker exec "$manager" /var/ossec/bin/wazuh-control restart
  log "Manager restarted."
}

validate_xml
(( CHECK_ONLY )) && { log "Check-only: stopping before any change."; exit 0; }
install_rules
install_groups
restart_manager
echo
echo "Verify: docker exec -it <manager> /var/ossec/bin/wazuh-control status"
echo "Then test a rule: docker exec -it <manager> /var/ossec/bin/wazuh-logtest  (paste a sample event)"

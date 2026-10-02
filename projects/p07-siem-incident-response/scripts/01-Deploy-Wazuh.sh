#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 Phase 1: deploy the Wazuh all-in-one stack
# Run on: SIEM01 (Ubuntu Server 24.04) as root, AFTER scripts/00-Prepare-SIEM01.sh.
# Snapshot first: snap-p7-ph1-before.
#
# WHAT THIS DOES
#   1. Generates the TLS certificates the stack needs (self-signed CA for the lab, via the
#      official wazuh-certs-tool).
#   2. Generates random passwords into an untracked .env (never committed — AGENTS.md R3).
#   3. Starts Wazuh manager + indexer + dashboard with configs/docker-compose.wazuh.yml.
#
# SECRETS
#   Nothing secret is written into the repository. The .env lives in /opt/wazuh with mode 0600 and
#   holds only locally-generated random strings; the real values belong in the owner's password
#   manager. The dashboard is never exposed beyond the lab.
# =============================================================================
set -euo pipefail

REPO_CONFIGS="${REPO_CONFIGS:-$(cd "$(dirname "$0")/.." && pwd)/configs}"
WAZUH_DIR="${WAZUH_DIR:-/opt/wazuh}"
COMPOSE_FILE="$WAZUH_DIR/docker-compose.yml"
DRY_RUN=0
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,20p' "$0"; exit 0; }
[[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]] && DRY_RUN=1

usage() { echo "Usage: sudo $0 [-n|--dry-run]   (env: REPO_CONFIGS, WAZUH_DIR)"; }

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { usage; echo "Run as root." >&2; exit 1; }

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
run() { if (( DRY_RUN )); then echo "DRY-RUN: $*"; else "$@"; fi; }

prepare_working_dir() {
  install -d -m 0750 "$WAZUH_DIR" "$WAZUH_DIR/certs"
  run cp -f "$REPO_CONFIGS/docker-compose.wazuh.yml" "$COMPOSE_FILE"
  run cp -f "$REPO_CONFIGS/local_rules.xml" "$WAZUH_DIR/local_rules.xml"
  log "Working dir prepared at $WAZUH_DIR"
}

generate_certs() {
  if [[ -s "$WAZUH_DIR/certs/root-ca.pem" ]]; then
    log "Certificates already present — skipping generation."
    return
  fi
  cd "$WAZUH_DIR"
  if (( DRY_RUN )); then echo "DRY-RUN: download and run wazuh-certs-tool.sh"; return; fi
  curl -sO https://packages.wazuh.com/4.9/wazuh-certs-tool.sh
  curl -sO https://packages.wazuh.com/4.9/config.yml
  # config.yml lists only the SIEM01 hostnames; edit if the hostnames differ.
  bash ./wazuh-certs-tool.sh -A
  tar -xf wazuh-certificates.tar -C "$WAZUH_DIR/certs" --strip-components=1
  log "Certificates generated in $WAZUH_DIR/certs (private keys stay on SIEM01)."
}

generate_env() {
  if [[ -s "$WAZUH_DIR/.env" ]]; then
    log ".env already exists — leaving it untouched."
    return
  fi
  if (( DRY_RUN )); then echo "DRY-RUN: generate random .env"; return; fi
  umask 077
  {
    echo "INDEXER_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')"
    echo "API_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')"
    echo "DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')"
  } > "$WAZUH_DIR/.env"
  chmod 0600 "$WAZUH_DIR/.env"
  log "Generated .env with random passwords (0600). Store copies in the password manager, not Git."
}

start_stack() {
  cd "$WAZUH_DIR"
  run docker compose --env-file "$WAZUH_DIR/.env" up -d
  log "Started. Give the indexer 60-90 seconds to become ready."
}

health() {
  if (( DRY_RUN )); then return; fi
  sleep 15
  docker compose --env-file "$WAZUH_DIR/.env" ps || true
  echo "Dashboard: https://$MANAGER_IP/  (from the MGMT network only)"
}

prepare_working_dir
generate_certs
generate_env
start_stack
health
echo
echo "Verify: docker compose ps (all healthy) ; curl -k https://localhost:9200 (indexer) ; open the dashboard."
echo "Change the default admin password in the dashboard on first login if you enabled the demo config."

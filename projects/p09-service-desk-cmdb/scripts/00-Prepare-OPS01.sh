#!/usr/bin/env bash
# Phase 1 (prep): prepare OPS01 to run the P9 service desk stack.
# What: installs Docker Engine + Compose plugin if missing, creates /opt/halden,
#       seeds .env from configs/.env.example, and opens nothing to the network.
# Where: OPS01 (Ubuntu Server 24.04, 192.168.10.40). Run as root.
# Snapshot first: snap-p9-ph1-before. Rollback: revert the OPS01 snapshot.
# Idempotent: safe to run twice. Lab marker: /etc/halden-lab
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/halden}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_SRC="${COMPOSE_SRC:-$SCRIPT_DIR/../configs/docker-compose.yml}"
ENV_SRC="${ENV_SRC:-$SCRIPT_DIR/../configs/.env.example}"

usage() {
  cat <<'USAGE'
Usage: sudo 00-Prepare-OPS01.sh [-h]
  Prepares OPS01 for the P9 service desk stack (docker + /opt/halden + .env).
  Env overrides: STACK_DIR, COMPOSE_SRC, ENV_SRC
  Prerequisite: /etc/halden-lab must exist (echo halden-lab | sudo tee /etc/halden-lab).
USAGE
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and the Compose plugin are already installed."
    return
  fi
  log "Installing Docker Engine and the Compose plugin from Docker's apt repo."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

prepare_layout() {
  log "Creating $STACK_DIR and the backup directory."
  install -d -m 0750 "$STACK_DIR"
  install -d -m 0750 "$STACK_DIR/backups"
  install -m 0640 "$COMPOSE_SRC" "$STACK_DIR/docker-compose.yml"
  if [[ -f "$STACK_DIR/.env" ]]; then
    log "$STACK_DIR/.env already exists; leaving it untouched."
  else
    install -m 0600 "$ENV_SRC" "$STACK_DIR/.env"
    log "Seeded $STACK_DIR/.env from .env.example — EDIT IT before deploying."
  fi
}

enable_service() {
  systemctl enable --now docker
  log "docker.service is enabled and running."
}

install_docker
prepare_layout
enable_service

log "Next: edit $STACK_DIR/.env (set real passwords and tokens; keep them in the password manager)."
log "Then run scripts/01-Deploy-ServiceDeskStack.sh. .env is git-ignored — never commit it."

#!/usr/bin/env bash
# 00-deploy-scanner.sh — Phase 3a: deploy Greenbone Community Edition on LNX01 (docker compose).
#
# Why: the scanner has to run somewhere always-on and close to the targets. LNX01 is the lab's
# Linux server and already hosts the scanner per LAB-INVENTORY.md. Everything runs in containers so
# the host stays clean and the stack can be removed with one command.
#
# What it does: checks the lab guard, installs Docker if missing, writes /opt/greenbone/
# docker-compose.yml (a sanitized copy of configs/p05-greenbone-compose.yml), starts the stack and
# waits for the feed sync. The Greenbone admin password is generated here and printed ONCE for the
# owner to store in the password manager — it is never written into the repository (AGENTS.md R3).
#
# Snapshot first: snap-p5-ph3-before (LNX01).   Rollback: docker compose down, then remove /opt/greenbone.
# Usage: sudo ./00-deploy-scanner.sh [--no-start]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

INSTALL_DIR="${INSTALL_DIR:-/opt/greenbone}"
COMPOSE_SRC="${COMPOSE_SRC:-$PROJECT_DIR/configs/p05-greenbone-compose.yml}"
START=1

usage() {
  echo "Usage: sudo $0 [--no-start]"
  echo "  Deploys the Greenbone CE scanner stack on LNX01 (lab only)."
  echo "  --no-start   write the compose file and finish; do not start containers"
  echo "  Env: INSTALL_DIR (default /opt/greenbone)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-start) START=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; halden_die "unknown argument: $1" ;;
  esac
  shift
done

require_lab_host
[[ $EUID -eq 0 ]] || halden_die "run with sudo"

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "Docker already present: $(docker --version)"
    return 0
  fi
  echo "Installing Docker from the distribution repository..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
  systemctl enable --now docker
}

write_compose() {
  [[ -f "$COMPOSE_SRC" ]] || halden_die "compose source not found: $COMPOSE_SRC"
  mkdir -p "$INSTALL_DIR"
  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak"
    echo "Existing compose file backed up to docker-compose.yml.bak"
  fi
  install -m 0644 "$COMPOSE_SRC" "$INSTALL_DIR/docker-compose.yml"
  chmod 0750 "$INSTALL_DIR"
  echo "Wrote $INSTALL_DIR/docker-compose.yml from $COMPOSE_SRC"
}

generate_admin_password() {
  # Generated locally, shown once, never committed. The owner stores it in the password manager.
  local pw
  pw="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | cut -c1-24)"
  echo "---------------------------------------------------------------"
  echo "Greenbone admin password (shown once, not saved to disk):"
  echo "  $pw"
  echo "Store it in your password manager now. This script does not keep it."
  echo "---------------------------------------------------------------"
}

start_stack() {
  cd "$INSTALL_DIR"
  docker compose pull
  docker compose up -d
  echo "Containers:"
  docker compose ps
  echo
  echo "The vulnerability feed syncs for several hours on first boot (it downloads the VT, SCAP,"
  echo "CERT and Notus data). Start this early in the day and check back with:"
  echo "  docker compose logs -f gvmd | grep -i feed"
}

install_docker
write_compose
generate_admin_password
if [[ $START -eq 1 ]]; then
  start_stack
else
  echo "--no-start given: compose file written, containers not started."
fi
echo
echo "Next: 01-harden-scanner.sh, then 02-setup-targets.sh (lab-ranges only)."

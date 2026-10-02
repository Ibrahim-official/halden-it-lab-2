#!/usr/bin/env bash
# Phase 1: deploy the P9 service desk stack on OPS01 (GLPI + MariaDB, Uptime Kuma,
# BookStack + MariaDB) with docker compose, then wait for health.
# Where: OPS01 (192.168.10.40). Run as root after scripts/00-Prepare-OPS01.sh.
# Snapshot first: snap-p9-ph1-before. Rollback: `docker compose down` (volumes kept);
#   a full rollback reverts the OPS01 snapshot.
# Idempotent: re-running pulls images and reconciles containers, touching no data.
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/halden}"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
ENV_FILE="$STACK_DIR/.env"

usage() {
  cat <<'USAGE'
Usage: sudo 01-Deploy-ServiceDeskStack.sh [-h]
  Deploys (or reconciles) the P9 docker compose stack on OPS01.
  Env override: STACK_DIR (default /opt/halden).
USAGE
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "Missing $COMPOSE_FILE — run 00-Prepare-OPS01.sh first." >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE — copy configs/.env.example and fill it in." >&2; exit 1; }
grep -q 'CHANGE_ME' "$ENV_FILE" && { echo "Refusing to deploy: $ENV_FILE still contains CHANGE_ME placeholders." >&2; exit 1; }

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

deploy() {
  log "Pulling images and bringing the stack up."
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans
}

wait_for_healthy() {
  local svc tries=0
  for svc in glpi-db bookstack-db glpi kuma bookstack; do
    log "Waiting for $svc to be running/healthy..."
    for _ in $(seq 1 30); do
      local state
      state="$(docker inspect -f '{{.State.Health.Status}}' "halden-$svc" 2>/dev/null || echo running)"
      if [[ "$state" == "healthy" || ( "$state" == "running" && "$svc" != *-db ) ]]; then break; fi
      tries=$((tries + 1)); sleep 5
    done
  done
  log "Container status:"
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
}

post_install_notes() {
  cat <<'NOTE'

== Post-deployment hardening (do this in the GLPI and BookStack UIs) ==
  1. GLPI: finish the installer, then DELETE install/install.php.
  2. GLPI: change or remove the default accounts (glpi, tech, normal, post-only).
  3. GLPI: enable LDAP (LDAPS 636) to ad.halden.internal and map groups:
       G_IT_ServiceDesk -> Technician, G_IT_SysAdmin -> Technician, everyone -> Self-Service.
  4. GLPI: Setup -> API -> create an API client and copy the app token into the
       git-ignored .env as GLPI_APP_TOKEN (used by scripts/02, 03, 04, 08).
  5. Kuma: create the admin user on first login and generate the P8 push token.
  6. BookStack: set LDAP auth in the UI and issue an API token (scripts/10-Seed-BookStack.sh).
  The reverse proxy + HTTPS certificate are applied in P6 (internal AD CS); until
  then the UIs bind to 127.0.0.1 only. The lab is never exposed to the internet.
NOTE
}

deploy
wait_for_healthy
post_install_notes

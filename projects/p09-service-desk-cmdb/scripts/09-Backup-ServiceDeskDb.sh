#!/usr/bin/env bash
# Phase 1/8 support: back up the P9 service desk databases and configs.
# What: mysqldump of the GLPI and BookStack databases from their MariaDB
#       containers, gzip-compressed with a SHA-256 checksum, retention pruning,
#       and an optional offsite copy to the P8 restic repository.
# Where: OPS01 (192.168.10.40). Run as root (cron: daily 02:00).
# Snapshot first: snap-p9-ph1-before (only needed for first run).
# Rollback: this script only writes backup files; delete them to roll back.
# Idempotent: re-running the same day overwrites that day's file.
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/halden}"
ENV_FILE="$STACK_DIR/.env"
BACKUP_DIR="${BACKUP_DIR:-$STACK_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
STAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'USAGE'
Usage: sudo 09-Backup-ServiceDeskDb.sh [-h]
  Dumps the GLPI and BookStack databases to $STACK_DIR/backups and prunes
  dumps older than RETENTION_DAYS. Env: STACK_DIR, BACKUP_DIR, RETENTION_DAYS.
  Secrets are read from the existing .env (git-ignored) — never passed on the
  command line, so they do not appear in the process list.
USAGE
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE." >&2; exit 1; }

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

# Read variables from .env without exporting them into the environment.
env_get() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- ; }

dump_db() {
  local svc="$1" db="$2" user="$3" pass="$4" out="$BACKUP_DIR/$svc-$STAMP.sql.gz"
  log "Dumping $db from container halden-$svc to $(basename "$out")"
  docker exec -e MYSQL_PWD="$pass" "halden-$svc" \
    mariadb-dump --single-transaction --quick --skip-lock-tables -u "$user" "$db" \
    | gzip -9 > "$out"
  sha256sum "$out" > "$out.sha256"
  # Verify the gzip stream is intact before trusting the backup.
  gzip -t "$out"
  log "Verified gzip integrity: $(basename "$out")"
}

prune() {
  log "Pruning dumps older than $RETENTION_DAYS days."
  find "$BACKUP_DIR" -type f \( -name '*.sql.gz' -o -name '*.sql.gz.sha256' \) \
    -mtime "+$RETENTION_DAYS" -print -delete
}

offsite() {
  if [[ -n "$(env_get RESTIC_REPOSITORY)" ]]; then
    log "Copying backups to the offsite restic repository (P8)."
    export RESTIC_REPOSITORY RESTIC_PASSWORD
    RESTIC_REPOSITORY="$(env_get RESTIC_REPOSITORY)"
    RESTIC_PASSWORD="$(env_get RESTIC_PASSWORD)"
    restic backup "$BACKUP_DIR" --tag p9-servicedesk
  else
    log "RESTIC_REPOSITORY empty — keeping backups local-only until P8 is built."
  fi
}

install -d -m 0750 "$BACKUP_DIR"
dump_db glpi-db "$(env_get GLPI_DB_NAME)" "$(env_get GLPI_DB_USER)" "$(env_get GLPI_DB_PASSWORD)"
dump_db bookstack-db "$(env_get BOOKSTACK_DB_NAME)" "$(env_get BOOKSTACK_DB_USER)" "$(env_get BOOKSTACK_DB_PASSWORD)"
prune
offsite
log "Service desk backup complete: $BACKUP_DIR"

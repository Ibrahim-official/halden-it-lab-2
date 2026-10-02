#!/usr/bin/env bash
# Phase 1/2: initialise the on-site restic repository on BKP01 and install the prune, verify and
# restore-test schedules. Optionally install Proxmox Backup Server (--with-pbs, Option A).
# Where it runs: BKP01 (192.168.10.42). Not domain-joined by design.
# Snapshot first: snap-p8-ph1-before.  Rollback: revert the snapshot; systemctl disable --now <unit>.
# Idempotent: re-running re-uses the existing repository and rewrites units only if changed.
# Secrets: read from the uncommitted /etc/halden-lab/backup.env and RESTIC_PASSWORD_FILE. Never printed.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
UNIT_DIR="/etc/systemd/system"
WITH_PBS=0
TIER1_KEEP="--keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12"
TIER0_KEEP="--keep-daily 30 --keep-monthly 12"

usage() {
  cat <<EOF
Usage: sudo $0 [--with-pbs] [--env FILE]
  Initialise the restic repository and install backup schedules.
  --with-pbs   also install Proxmox Backup Server (Option A) and create a datastore
  --env FILE   path to the env file (default $ENV_FILE)
  -h, --help   show this help
EOF
}
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

check_lab() {
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
}

load_secrets() {
  [[ $EUID -eq 0 ]] || die "run as root"
  [[ -f "$ENV_FILE" ]] || die "env file $ENV_FILE not found (copy configs/backup.env.example and fill it in)"
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
  RESTIC_REPOSITORY="${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY in $ENV_FILE}"
  RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:?set RESTIC_PASSWORD_FILE in $ENV_FILE}"
  [[ -s "$RESTIC_PASSWORD_FILE" ]] || die "passphrase file $RESTIC_PASSWORD_FILE is missing or empty"
  [[ "$(stat -c '%a' "$RESTIC_PASSWORD_FILE")" == "600" ]] || log "WARNING: chmod 600 $RESTIC_PASSWORD_FILE"
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
}

init_repo() {
  if restic snapshots >/dev/null 2>&1; then
    log "repository already initialised at $RESTIC_REPOSITORY"
  else
    log "initialising repository at $RESTIC_REPOSITORY"
    restic init
  fi
}

write_unit() {
  local name="$1" exec="$2" desc="$3" calendar="$4" want
  want="$(cat <<EOF
[Unit]
Description=$desc
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENV_FILE
ExecStart=$exec
EOF
)"
  if [[ ! -f "$UNIT_DIR/$name.service" || "$(cat "$UNIT_DIR/$name.service")" != "$want" ]]; then
    printf '%s\n' "$want" > "$UNIT_DIR/$name.service"
    cat > "$UNIT_DIR/$name.timer" <<EOF
[Unit]
Description=Timer for $desc

[Timer]
OnCalendar=$calendar
Persistent=true

[Install]
WantedBy=timers.target
EOF
    log "installed unit $name"
  fi
}

install_schedules() {
  local backup="${BACKUP_ROOT:-/srv/backup}"
  write_unit "halden-restic-backup"  "$(dirname "$0")/restic-backup.sh --tier 1 --repo $backup/restic" "Halden Tier 1 file backup" "hourly"
  write_unit "halden-restic-prune"   "restic forget $TIER1_KEEP --prune"                                    "Halden repository prune"      "*-*-* 03:00:00"
  write_unit "halden-restic-verify"  "bash -c 'restic check --read-data-subset=5%'"                          "Halden repository verify"     "Sun *-*-* 04:00:00"
  write_unit "halden-restore-test"   "$(dirname "$0")/06-Test-BackupRestore.sh"                             "Halden weekly restore test"   "Sun *-*-* 05:00:00"
  systemctl daemon-reload
  systemctl enable --now halden-restic-backup.timer halden-restic-prune.timer \
                           halden-restic-verify.timer halden-restore-test.timer
  log "schedules enabled (backup hourly, prune daily 03:00, verify Sun 04:00, restore test Sun 05:00)"
}

install_pbs() {
  log "Option A: installing Proxmox Backup Server (this modifies apt sources)"
  if ! command -v proxmox-backup-manager >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    wget -qO /etc/apt/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" \
      > /etc/apt/sources.list.d/pbs.list
    apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-backup-server
  fi
  proxmox-backup-manager datastore show backup-store >/dev/null 2>&1 \
    || proxmox-backup-manager datastore create backup-store "${BACKUP_ROOT:-/srv/backup}/pbs"
  log "PBS datastore 'backup-store' ready (client port 8007)"
}

main() {
  local args=()
  while (($#)); do
    case "$1" in
      --with-pbs) WITH_PBS=1 ;;
      --env) shift; ENV_FILE="$1" ;;
      -h|--help) usage; exit 0 ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  check_lab; load_secrets; init_repo; install_schedules
  ((WITH_PBS)) && install_pbs || true
  echo "Verify: systemctl list-timers 'halden-*' ; restic snapshots"
}

main "$@"

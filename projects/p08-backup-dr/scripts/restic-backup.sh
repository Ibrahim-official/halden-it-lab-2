#!/usr/bin/env bash
# Helper: run a restic file-level backup for a tier and write the source SHA-256 manifest that the
# weekly restore test compares against. Called by the halden-restic-backup timer and by hand.
# Where it runs: BKP01. Snapshot first: snap-p8-ph1-before (only if paths change). Idempotent.
# Secrets: RESTIC_PASSWORD_FILE from the uncommitted env file. No secret is ever printed.
set -euo pipefail

DOMAIN="ad.halden.internal"
ENV_FILE="${ENV_FILE:-/etc/halden-lab/backup.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/backup}"
MANIFEST_DIR="${MANIFEST_DIR:-$BACKUP_ROOT/manifests}"
TIER=""
REPO=""
PATHS=()

usage() {
  cat <<EOF
Usage: sudo $0 --tier {0|1|2} [--repo PATH] [--path DIR]...
  Run a restic backup for a tier and write the SHA-256 manifest of the backed-up files.
  --tier   backup tier (sets the restic --tag and default paths)
  --repo   restic repository (default \$RESTIC_REPOSITORY)
  --path   source path to back up (repeatable; defaults per tier)
  -h, --help
EOF
  exit "${1:-0}"
}
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

check_lab() {
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
}
load_env() {
  [[ -f "$ENV_FILE" ]] || die "env file $ENV_FILE not found"
  set -a; source "$ENV_FILE"; set +a
  export RESTIC_REPOSITORY="${REPO:-${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY}}"
  export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:?set RESTIC_PASSWORD_FILE}"
}
tier_paths() {
  case "$1" in
    0) printf '%s\n' "/srv/data/fw-config" ;;
    1) printf '%s\n' "/srv/data/Finance" "/srv/data/Sales" "/srv/data/order-app" ;;
    2) printf '%s\n' "/srv/data/glpi" "/srv/data/bookstack" "/srv/data/wazuh" ;;
    *) die "unknown tier '$1' (expected 0, 1 or 2)" ;;
  esac
}

write_manifest() {
  install -d -m 0750 "$MANIFEST_DIR"
  local out="$MANIFEST_DIR/tier${TIER}-$(date +%Y%m%d-%H%M%S).sha256"
  : > "$out"
  local p
  for p in "${PATHS[@]}"; do
    [[ -e "$p" ]] || { log "skip (missing): $p"; continue; }
    find "$p" -type f -print0 | sort -z | xargs -0 -r sha256sum >> "$out"
  done
  log "manifest written: $out"
}

main() {
  while (($#)); do
    case "$1" in
      --tier) shift; TIER="${1:-}" ;;
      --repo) shift; REPO="${1:-}" ;;
      --path) shift; PATHS+=("${1:-}") ;;
      -h|--help) usage 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  [[ -n "$TIER" ]] || usage 1
  check_lab; load_env
  if ((${#PATHS[@]} == 0)); then mapfile -t PATHS < <(tier_paths "$TIER"); fi
  write_manifest
  log "starting restic backup (tier $TIER, tag tier$TIER)"
  restic backup --tag "tier$TIER" --exclude-caches --exclude '*.tmp' "${PATHS[@]}"
  restic snapshots --last --tag "tier$TIER"
  echo "Verify: restic check --read-data-subset=1%"
}

main "$@"

#!/usr/bin/env bash
# Phase 1: prepare and harden BKP01 (Ubuntu Server 24.04) BEFORE it stores any backup.
# Where it runs: BKP01 (192.168.10.42). BKP01 is deliberately NOT domain-joined (docs/00-design.md §9).
# Why: a backup server that shares the domain's fate is not a backup server. If AD is compromised,
#      the backups must survive. So this host has local credentials, its own firewall and TOTP console.
# Snapshot first: snap-p8-ph1-before (hypervisor snapshot of BKP01).
# Rollback: revert snap-p8-ph1-before. Idempotent: safe to re-run.
# Secrets: none are handled here. Repository passphrases/keys live in the uncommitted env file
#          /etc/halden-lab/backup.env (see configs/backup.env.example) and the owner's password manager.
set -euo pipefail

DOMAIN="ad.halden.internal"
MGMT_NET="${MGMT_NET:-192.168.10.0/24}"      # P6 narrows this to the MGMT VLAN
PBS_PORT="${PBS_PORT:-8007}"                 # Proxmox Backup Server client port, if Option A is used
BACKUP_ROOT="${BACKUP_ROOT:-/srv/backup}"
SSH_CONF="/etc/ssh/sshd_config.d/10-halden-bkp.conf"
PACKAGES=(restic mc jq ufw fail2ban chrony rsync libpam-google-authenticator)

usage() {
  cat <<EOF
Usage: sudo $0 [options]
  Prepare and harden BKP01. Idempotent. Requires the lab marker: echo halden-lab | sudo tee /etc/halden-lab
Options:
  -h, --help            show this help
Environment overrides:
  MGMT_NET   management source network allowed to SSH (default 192.168.10.0/24)
  BACKUP_ROOT repository root (default /srv/backup)
EOF
}

log()  { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

check_lab() {
  # The standard Halden lab guard (AGENTS.md Section 2). BKP01 is not domain-joined, so it relies on
  # the marker file /etc/halden-lab.
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
}

check_root()   { [[ $EUID -eq 0 ]] || die "run as root (sudo $0)"; }

check_not_joined() {
  if command -v realm >/dev/null 2>&1 && realm list 2>/dev/null | grep -q "$DOMAIN"; then
    die "BKP01 appears to be joined to $DOMAIN. It must stay non-domain-joined (rollback = leave realm)."
  fi
  log "confirmed BKP01 is not domain-joined"
}

install_packages() {
  local missing=()
  for p in "${PACKAGES[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]})); then
    log "installing: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  else
    log "all packages already present"
  fi
}

create_storage() {
  install -d -m 0750 -o root -g root "$BACKUP_ROOT" \
    "$BACKUP_ROOT/restic" "$BACKUP_ROOT/vms" "$BACKUP_ROOT/systemstate" \
    "$BACKUP_ROOT/staging" "$BACKUP_ROOT/reports" "$BACKUP_ROOT/restore-scratch"
  # Reports are world-readable so the monitoring/reporting script can read them without sudo.
  chmod 0755 "$BACKUP_ROOT/reports"
  log "repository storage prepared under $BACKUP_ROOT"
  if ! findmnt -no SOURCE --target "$BACKUP_ROOT" | grep -qE '^(/dev/|/dev/mapper/)'; then
    log "WARNING: $BACKUP_ROOT is on the OS disk. For a real lab, attach a dedicated backup disk."
  fi
  df -h "$BACKUP_ROOT" | tail -1
}

harden_ssh() {
  local want
  want="$(cat <<EOF
# Halden lab (P8): SSH to BKP01 by key only, from the management network only.
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
AllowTcpForwarding no
EOF
)"
  if [[ -f "$SSH_CONF" && "$(cat "$SSH_CONF")" == "$want" ]]; then
    log "SSH already hardened"
  else
    printf '%s\n' "$want" > "$SSH_CONF"
    sshd -t || die "sshd config invalid; not restarting"
    systemctl restart ssh
    log "SSH hardened and reloaded"
  fi
}

configure_firewall() {
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$MGMT_NET" to any port 22 proto tcp comment 'management SSH'
  ufw allow from "$MGMT_NET" to any port "$PBS_PORT" proto tcp comment 'PBS client (Option A)'
  ufw allow from "$MGMT_NET" to any port 8007 proto tcp comment 'restic REST server (optional)'
  ufw --force enable
  log "firewall enabled: SSH and backup ports from $MGMT_NET only"
}

enable_fail2ban() {
  systemctl enable --now fail2ban
  log "fail2ban enabled"
}

totp_note() {
  log "TOTP: libpam-google-authenticator is installed. Enrol interactively for the local admin"
  log "      (google-authenticator) and add 'auth required pam_google_authenticator.so' to the PAM"
  log "      config for console/SSH. The seed is a secret: store it in the password manager, never in Git."
}

summary() {
  cat <<EOF

Next steps (Phase 1):
  1. Attach the dedicated backup disk (or accept the OS-disk warning) and re-run this script.
  2. Copy configs/backup.env.example to /etc/halden-lab/backup.env, fill in real secrets, chmod 600.
  3. Put the repository passphrase in /etc/halden-lab/restic.pass (root-only) and escrow it offline.
  4. Run ./01-Configure-BackupRepository.sh to initialise the repository and schedules.
Do not store any backup until steps 2-3 are done.
EOF
}

main() {
  case "${1:-}" in -h|--help) usage; exit 0 ;; esac
  check_lab
  check_root
  check_not_joined
  install_packages
  create_storage
  harden_ssh
  configure_firewall
  enable_fail2ban
  totp_note
  summary
}

main "$@"

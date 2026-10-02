#!/usr/bin/env bash
# 01-harden-scanner.sh — Phase 3b: harden the scanner host and the least-privilege scan accounts.
#
# Why: a vulnerability scanner is itself a sensitive target. It holds credentials that can log in to
# every host it scans. So: the web UI is bound to loopback and reached through an SSH tunnel, the
# host firewall only allows SSH from the management subnet, and the scan accounts are dedicated,
# non-interactive, and no more privileged than the scan actually needs (AGENTS.md 4.4 least privilege).
#
# What it does: creates the SSH key pair used for Linux authenticated scans, documents the
# requirements for the Windows scan account (created in AD by 02-setup-targets.sh's notes), and
# applies host hardening. No credentials are written into the repository.
#
# Snapshot first: snap-p5-ph3-before (LNX01).   Rollback: revert the snapshot; the host only.
# Usage: sudo ./01-harden-scanner.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/labguard.sh
. "$SCRIPT_DIR/lib/labguard.sh"

KEY_DIR="${KEY_DIR:-/root/.ssh}"
MGMT_NET="${MGMT_NET:-192.168.10.0/24}"

usage() { echo "Usage: sudo $0  (env: KEY_DIR, MGMT_NET). Creates the scanner SSH key and hardens LNX01."; }
[[ "${1:-}" == "-h" ]] && { usage; exit 0; }

require_lab_host
[[ $EUID -eq 0 ]] || halden_die "run with sudo"

ensure_scanner_key() {
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
  if [[ -f "$KEY_DIR/p5-scanner_ed25519" ]]; then
    echo "Scanner SSH key already exists: $KEY_DIR/p5-scanner_ed25519 (leaving it alone)"
  else
    ssh-keygen -t ed25519 -N '' -C 'p5-scanner@lnx01 (Halden lab)' -f "$KEY_DIR/p5-scanner_ed25519"
    chmod 600 "$KEY_DIR/p5-scanner_ed25519"
    echo "Created scanner key pair. Copy ONLY the public key into the 'scanner' user's"
    echo "authorized_keys on each Linux target; never copy the private key off this host."
  fi
}

document_scan_accounts() {
  cat <<'NOTES'
Scan accounts (create these by hand; passwords go in the password manager, never here):
  Linux  : a dedicated 'scanner' user with -- no sudo, a locked password, the public key above,
           and simply no privileges beyond reading package versions. Command-based local
           security checks need no root; anything needing root should be found by patch evidence,
           not by a scanner running as root.
  Windows: a dedicated 'svc-vulnscan' domain account, member of a 'G_VulnScan' group that is a
           member of each target server's local Administrators (or Remote Management Users where
           remote registry/WMI access suffices). Deny interactive logon and deny RDP, and give it
           no rights in AD beyond reading. Its password goes in the password manager only.
NOTES
}

harden_host() {
  echo "Applying minimal host hardening (firewall + SSH tunnel only web UI)..."
  if command -v ufw >/dev/null 2>&1; then
    ufw --force default deny incoming
    ufw allow from "$MGMT_NET" to any port 22 proto tcp
    # 9392 is bound to 127.0.0.1 in the compose file; reach it with:
    #   ssh -L 9392:127.0.0.1:9392 <you>@192.168.10.30
    ufw --force enable
    ufw status verbose || true
  else
    echo "ufw not installed; install it (apt-get install -y ufw) and re-run."
  fi
  cat <<'TUNNEL'
Web UI access (from the management subnet only):
  ssh -L 9392:127.0.0.1:9392 <you>@192.168.10.30
  then browse http://127.0.0.1:9392
TUNNEL
}

ensure_scanner_key
document_scan_accounts
harden_host
echo "Scanner host hardened. Next: 02-setup-targets.sh (creates targets from configs/p05-scan-scope.txt)."

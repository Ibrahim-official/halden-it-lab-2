#!/usr/bin/env bash
# Phase 5: export Linux and OPNsense configuration into the halden-configs Git
# working copy for config-as-code drift detection (companion to the Windows side
# in 06-Export-HaldenConfigs.ps1).
# What: collects sshd/sudoers/ufw facts from lab Ubuntu hosts and a SECRET-FILTERED
#       copy of the OPNsense config.xml, then stages the changes.
# Where: run on OPS01 or a management host with SSH access to the Linux lab hosts.
# Snapshots: nothing on the targets is changed (read-only collection).
# Rollback: delete the files written under $REPO_DIR; nothing on any host changes.
# Idempotent: file contents are rewritten each run; only real changes diff.
set -euo pipefail

DOMAIN="ad.halden.internal"
REPO_DIR="${REPO_DIR:-/opt/halden/halden-configs}"
OPN_HOST="${OPN_HOST:-192.168.10.1}"
SSH_USER="${SSH_USER:-root}"
LINUX_HOSTS="${LINUX_HOSTS:-lnx01.ad.halden.internal ops01.ad.halden.internal}"

usage() {
  cat <<'USAGE'
Usage: sudo 07-export-configs.sh [-h]
  Exports Linux and (filtered) OPNsense config into $REPO_DIR for Git.
  Env: REPO_DIR, OPN_HOST, SSH_USER, LINUX_HOSTS.
  Secrets are filtered out of config.xml before writing; never commit raw exports.
  Prerequisite: /etc/halden-lab must exist on this host.
USAGE
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ "$(hostname -d 2>/dev/null)" == "$DOMAIN" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

export_linux() {
  local host="$1" dir="$REPO_DIR/linux/$1"
  install -d -m 0755 "$dir"
  log "Collecting Linux config from $host"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_USER@$host" '
    set -e
    echo "## sshd_config.d"; for f in /etc/ssh/sshd_config.d/*.conf; do [ -e "$f" ] && { echo "### $f"; cat "$f"; }; done
    echo "## sudoers.d"; for f in /etc/sudoers.d/*; do [ -f "$f" ] && { echo "### $f"; cat "$f"; }; done
    echo "## ufw status"; ufw status verbose 2>/dev/null || true
    echo "## packages"; dpkg-query -W -f="${Package} ${Version}\n" 2>/dev/null | sort | grep -E "^(openssh-server|ufw|docker-ce|chrony|realmd|sssd) " || true
  ' > "$dir/facts.txt"
}

# OPNsense config.xml holds hashes, secrets and keys. REDACT those lines before
# the file can ever reach Git. This is a conservative filter: anything that looks
# like a password/hash/secret/key value is replaced with <redacted>.
export_opnsense() {
  local dir="$REPO_DIR/opnsense"
  install -d -m 0755 "$dir"
  log "Downloading OPNsense config.xml from $OPN_HOST (in memory) and filtering secrets"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_USER@$OPN_HOST" 'cat /conf/config.xml' \
    | python3 - "$dir/config.xml.filtered" <<'PY'
import re, sys
dest = sys.argv[1]
text = sys.stdin.read()
# Redact the text content of any element whose tag looks like a secret material.
pattern = re.compile(
    r'(<(?:password|passwd|pwd|secret|sharedsecret|psk|privatekey|private_key|'
    r'apikey|api_key|token|community|md5|sha256|hash|wpa|psk)>)[^<]*(</)',
    re.IGNORECASE)
redacted = pattern.sub(lambda m: m.group(1) + '<redacted>' + m.group(2), text)
with open(dest, 'w', encoding='utf-8') as fh:
    fh.write(redacted)
print(f"wrote {dest}")
PY
}

stage_git() {
  if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" add -A
    log "Staged changes in $REPO_DIR — review with: git -C $REPO_DIR diff --cached"
    log "Secrets filter applied; still verify before committing (git-crypt/SOPS is the belt-and-braces option)."
  else
    log "$REPO_DIR is not a Git repository yet; files exported for review only."
  fi
}

install -d -m 0755 "$REPO_DIR"
for h in $LINUX_HOSTS; do export_linux "$h"; done
export_opnsense
stage_git
log "Linux/OPNsense config export complete."

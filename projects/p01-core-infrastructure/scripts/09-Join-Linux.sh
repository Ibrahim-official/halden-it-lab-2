#!/usr/bin/env bash
# Phase 7: join LNX01 (Ubuntu 24.04) to ad.halden.internal; AD-group-controlled SSH and sudo.
# Run on LNX01 as root. Snapshot first: snap-p1-ph7-before. Lab marker: /etc/halden-lab
set -euo pipefail
DOMAIN="ad.halden.internal"; ADMIN_USER="${ADMIN_USER:-administrator}"; MGMT_NET="${MGMT_NET:-192.168.10.0/24}"
OU="OU=Linux,OU=Servers,OU=Halden,DC=ad,DC=halden,DC=internal"
usage() { echo "Usage: sudo $0  (env: ADMIN_USER, MGMT_NET). Needs /etc/halden-lab: echo halden-lab | sudo tee /etc/halden-lab"; }
[[ "${1:-}" == "-h" ]] && { usage; exit 0; }
[[ "$(hostname -d 2>/dev/null)" == "$DOMAIN" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { usage; exit 1; }

install_pkgs() { DEBIAN_FRONTEND=noninteractive apt-get install -y realmd sssd sssd-tools adcli krb5-user packagekit samba-common-bin oddjob oddjob-mkhomedir fail2ban ufw chrony; }
join_domain() {
  realm discover "$DOMAIN"
  realm list | grep -q "$DOMAIN" || realm join -U "$ADMIN_USER" "$DOMAIN" --computer-ou="$OU"
  realm deny --all; realm permit -g "G_IT_LinuxAdmins@$DOMAIN"
  pam-auth-update --enable mkhomedir
}
configure_sudo() {
  echo "%G_IT_LinuxAdmins@$DOMAIN ALL=(ALL) ALL" > /etc/sudoers.d/ad-admins; chmod 440 /etc/sudoers.d/ad-admins; visudo -cf /etc/sudoers.d/ad-admins
}
harden_ssh() {
  cat > /etc/ssh/sshd_config.d/10-halden.conf <<CONF
# Halden lab: SSH limited to AD group, key auth only (home dir is created at first console login)
PermitRootLogin no
PasswordAuthentication no
AllowGroups g_it_linuxadmins@$DOMAIN
MaxAuthTries 3
CONF
  sshd -t && systemctl restart ssh
  ufw default deny incoming; ufw allow from "$MGMT_NET" to any port 22 proto tcp; ufw --force enable
  systemctl enable --now fail2ban
}
apt-get update -y; install_pkgs; join_domain; configure_sudo; harden_ssh
echo "Verify: id <user>@$DOMAIN ; non-member login must be denied ; member runs 'sudo -l'"

#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 Phase 1: Wazuh agent on the Linux sources
# Run on EACH of: LNX01, OPS01, BKP01 (and optionally SIEM01 itself) as root.
# Snapshot first: snap-p7-ph1-before.
#
# WHAT THIS DOES
#   Installs the Wazuh agent, points it at SIEM01 and joins it to the correct agent group so it
#   receives the right agent.conf (agent-groups.conf): linux-servers.
#   Idempotent: re-running upgrades/repairs rather than duplicating.
#
# USAGE
#   sudo ./02-Deploy-Agents-Linux.sh -m 192.168.10.41 [-g linux-servers]
#   Lab marker: echo halden-lab | sudo tee /etc/halden-lab
# =============================================================================
set -euo pipefail

MANAGER_IP="192.168.10.41"
AGENT_GROUP="linux-servers"
while getopts ":m:g:h" opt; do
  case "$opt" in
    m) MANAGER_IP="$OPTARG" ;;
    g) AGENT_GROUP="$OPTARG" ;;
    h) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

usage() { echo "Usage: sudo $0 [-m manager_ip] [-g agent_group]"; }

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { usage; echo "Run as root." >&2; exit 1; }

install_agent() {
  if dpkg -s wazuh-agent >/dev/null 2>&1; then
    echo "Wazuh agent already installed — repairing configuration only."
  else
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
      | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
    . /etc/os-release
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
      > /etc/apt/sources.list.d/wazuh.list
    apt-get update -y
    WAZUH_MANAGER="$MANAGER_IP" WAZUH_AGENT_GROUP="$AGENT_GROUP" WAZUH_AGENT_NAME="$(hostname -s)" \
      apt-get install -y wazuh-agent
  fi
}

configure_manager() {
  local conf=/var/ossec/etc/ossec.conf
  [[ -f "$conf" ]] || { echo "Missing $conf" >&2; return 1; }
  if grep -q '<address>'"$MANAGER_IP"'</address>' "$conf"; then
    echo "Manager already configured as $MANAGER_IP."
  else
    sed -i "s#<address>.*</address>#<address>${MANAGER_IP}</address>#" "$conf"
    echo "Set manager address to $MANAGER_IP."
  fi
}

start_agent() {
  systemctl daemon-reload
  systemctl enable wazuh-agent >/dev/null 2>&1 || true
  systemctl restart wazuh-agent
  sleep 3
  systemctl is-active wazuh-agent
}

install_agent
configure_manager
start_agent
echo
echo "Verify on SIEM01: docker exec -it <manager> /var/ossec/bin/agent_control -l  (this host listed, Active)"
echo "Agent group: $AGENT_GROUP ; Manager: $MANAGER_IP"

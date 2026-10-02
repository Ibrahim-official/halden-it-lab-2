#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 Phase 1: prepare SIEM01
# Run on: SIEM01 (Ubuntu Server 24.04, 192.168.10.41) as root.
# Snapshot first: snap-p7-ph1-before.
#
# WHAT THIS DOES
#   Prepares the host for the Wazuh all-in-one stack: kernel settings the indexer needs, Docker,
#   the /opt/wazuh working directory and the syslog listener prerequisites. It changes NOTHING
#   outside the Halden lab (hard guard below).
#
# RAM WARNING (read this)
#   P7 is the heaviest project in the lab. The Wazuh indexer alone wants ~4 GB. The owner's host
#   has 16 GB, so give SIEM01 6 GB and power off FS01/WS02/OPS01 while Wazuh runs. 4 GB is the
#   minimum that will still start (slower dashboard); 8 GB is smooth. This script refuses to
#   continue below 4 GB unless -f is given, and warns below 8 GB.
# =============================================================================
set -euo pipefail

MANAGER_IP="${MANAGER_IP:-192.168.10.41}"
WAZUH_DIR="${WAZUH_DIR:-/opt/wazuh}"
FORCE=0
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,20p' "$0"; exit 0; }
[[ "${1:-}" == "-f" || "${1:-}" == "--force" ]] && FORCE=1

usage() { echo "Usage: sudo $0 [-f|--force]   (env: MANAGER_IP, WAZUH_DIR)"; }

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || { usage; echo "Run as root." >&2; exit 1; }; }

check_ram() {
  local kb gb
  kb="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  gb=$(( kb / 1024 / 1024 ))
  echo "SIEM01 RAM: ${gb} GB"
  if (( gb < 4 )); then
    echo "REFUSING: Wazuh needs at least 4 GB. Resize the VM, then re-run (or -f to override)." >&2
    (( FORCE == 1 )) || exit 1
  elif (( gb < 8 )); then
    echo "WARNING: <8 GB. It will run but the dashboard will be slow, and DC/FS VMs should be off." >&2
  fi
}

kernel_settings() {
  # The indexer (OpenSearch) requires a high mmap count and dislikes swapping.
  local need=262144
  local have; have="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
  if (( have < need )); then
    echo "vm.max_map_count=${need}" > /etc/sysctl.d/99-wazuh.conf
    sysctl --system >/dev/null
    echo "Set vm.max_map_count=${need}."
  else
    echo "vm.max_map_count already ${have} (ok)."
  fi
  if ! grep -q '^vm.swappiness' /etc/sysctl.d/99-wazuh.conf 2>/dev/null; then
    echo "vm.swappiness=10" >> /etc/sysctl.d/99-wazuh.conf
    sysctl -w vm.swappiness=10 >/dev/null
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "Docker already installed ($(docker --version))."
    return
  fi
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

prepare_dir() {
  install -d -m 0750 "$WAZUH_DIR"
  install -d -m 0750 "$WAZUH_DIR/certs"
  echo "Working directory: $WAZUH_DIR"
}

time_sync() {
  timedatectl set-ntp true 2>/dev/null || true
  echo "Time sync: $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
}

require_root
check_ram
kernel_settings
install_docker
prepare_dir
time_sync
echo
echo "Done. Next: copy configs/docker-compose.wazuh.yml to $WAZUH_DIR/ and run scripts/01-Deploy-Wazuh.sh."
echo "Verify: docker --version ; sysctl vm.max_map_count ; free -h"

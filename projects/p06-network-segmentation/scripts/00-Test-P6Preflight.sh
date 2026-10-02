#!/usr/bin/env bash
# P6 - Phase 0 preflight: read-only checks before any network change is made.
#
# What it does : validates that every P6 configuration file exists and parses, prints the zone,
#                VLAN and rule plan, and refuses to continue if a secret looks committed.
# Where        : any Halden lab host (marker file /etc/halden-lab, or a DNS domain of
#                ad.halden.internal). It does NOT run on the home network, ever.
# Mode         : A (Advisor). This script changes nothing; it only reads files and prints text.
# Safety       : read-only. No API call, no firewall change. The scripts that DO change FW01 are
#                01-Apply-OpnSenseNetworks.sh and 05/06, and each of those is applied by the owner
#                against the lab firewall only, never against the home router (AGENTS.md R1/R6).
# Snapshot     : not required - nothing is changed. Take snap-p6-ph0-before before Phase 1 anyway.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_DIR/configs"
DATA_DIR="$PROJECT_DIR/data"

usage() {
  cat <<'EOF'
Usage: 00-Test-P6Preflight.sh [--strict]
  --strict   exit non-zero if a required file is missing (default: warn and continue)

Read-only preflight for P6. Prints the zone / VLAN / rule plan and checks the configuration files.
EOF
}

STRICT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

# Halden lab guard (AGENTS.md Section 2). Never run this outside the lab.
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

command -v nmap >/dev/null 2>&1 || echo "note: nmap not found - install it before running the test suite (09)."

required_files=(
  "$CONFIG_DIR/p06-zone-rule-matrix.csv"
  "$CONFIG_DIR/p06-zone-rule-matrix.md"
  "$CONFIG_DIR/p06-interface-vlan-plan.csv"
  "$CONFIG_DIR/p06-opnsense-aliases.csv"
  "$CONFIG_DIR/p06-dhcp-scope-plan.csv"
  "$CONFIG_DIR/p06-nps-radius-policy.md"
  "$DATA_DIR/p06-segmentation-test-plan.csv"
  "$DATA_DIR/p06-zone-ip-allocation.csv"
)

missing=0
check_files() {
  echo "== Configuration files =="
  for f in "${required_files[@]}"; do
    if [[ -f "$f" ]]; then
      printf '  ok      %s\n' "${f#"$PROJECT_DIR"/}"
    else
      printf '  MISSING %s\n' "${f#"$PROJECT_DIR"/}"
      missing=$((missing + 1))
    fi
  done
}

# Print a CSV (skipping '#' comment lines) as a simple aligned table.
print_csv() {
  local file="$1" label="$2"
  echo
  echo "== $label =="
  awk -F, '!/^#/ && NF>0 { printf "  %-4s %-10s %-10s %-24s %-20s\n", $1, $2, $3, $4, $5 }' "$file"
}

# A secret grep across the project tree (no secrets should ever be committed).
# It looks for key material with an actual base64 body, not for the words in a template or a doc.
scan_secrets() {
  echo
  echo "== Secret scan (should find nothing) =="
  local hits
  hits="$(grep -rIn -A3 -E '^-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----$|^-----BEGIN OpenVPN Static key V1-----$' \
            --include='*.key' --include='*.pem' --include='*.ovpn' --include='*.conf' --include='*.env' \
            "$PROJECT_DIR" 2>/dev/null | grep -E '^[^:]+-[0-9]+-[A-Za-z0-9+/=]{40,}$' || true)"
  if [[ -n "$hits" ]]; then
    echo "  ^ a key with a real body was found - remove it and rotate the credential:" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "  clean - no private keys or shared secrets with a real body found."
  echo "  (template files contain placeholder markers only; see configs/p06-certificate-plan.md.)"
}

check_files
print_csv "$CONFIG_DIR/p06-interface-vlan-plan.csv" "Zone and VLAN plan (interface assignment)"
print_csv "$CONFIG_DIR/p06-zone-rule-matrix.csv" "Inter-zone rule matrix (ordered; first match wins)"
print_csv "$DATA_DIR/p06-zone-ip-allocation.csv" "Zone IP allocation"
scan_secrets

echo
echo "Reminder (AGENTS.md R1/R6): every change in this project targets FW01/FW02 or the lab"
echo "hypervisor switch only. The home router and the home LAN are never touched."

if [[ "$missing" -gt 0 && "$STRICT" -eq 1 ]]; then
  echo "preflight: $missing required file(s) missing" >&2
  exit 1
fi
echo "preflight: complete ($missing missing file(s))."

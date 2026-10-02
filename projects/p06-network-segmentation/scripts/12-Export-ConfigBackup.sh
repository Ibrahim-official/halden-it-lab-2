#!/usr/bin/env bash
# P6 - Phase 6: export the firewall and NPS configuration so it can be versioned in Git.
#
# EXPORT IS NOT THE SAME AS PUBLISH. The raw export contains credentials: user hashes, the RADIUS
# shared secret, OpenVPN and WireGuard private keys, the API key. It is written to evidence/raw/
# (git-ignored) and must NEVER be published as-is. The publishable artefact is the SANITISED SUMMARY
# this script also writes to evidence/public/, which lists configuration areas and counts only.
#
# TARGET: FW01 (default), FW02 with --host fw02. Run BY THE OWNER against the lab firewall (Mode A).
#         The guard refuses any endpoint that is not a 192.168.x lab address.
# MODE A / R1: no change is made to the firewall - this only reads configuration out of it.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_DIR/evidence/raw"
PUB_DIR="$PROJECT_DIR/evidence/public"

usage() {
  cat <<'EOF'
Usage: 12-Export-ConfigBackup.sh [--host fw01|fw02] [--insecure]

  --host fw01|fw02   which firewall to export from (default: fw01)
  --insecure         pass -k to curl (self-signed lab certificate)

Environment:
  FW01_URL / FW01_KEY / FW01_SECRET   (or FW02_* with --host fw02)

Writes: evidence/raw/p06-ph6-opnsense-config-<host>-<date>.xml   (NEVER published)
        evidence/public/p06-ph6-config-summary-<host>.csv         (sanitised, safe to commit)
EOF
}

HOST_ID="fw01"; INSECURE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST_ID="${2:-fw01}"; shift 2 ;;
    --insecure) INSECURE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

if [[ "$HOST_ID" == "fw01" ]]; then URL="${FW01_URL:-}"; KEY="${FW01_KEY:-}"; SECRET="${FW01_SECRET:-}"
else URL="${FW02_URL:-}"; KEY="${FW02_KEY:-}"; SECRET="${FW02_SECRET:-}"; fi

[[ -n "$URL" ]] || { echo "error: $HOST_ID URL is not set." >&2; exit 1; }
endpoint_host="$(printf '%s' "$URL" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:.*$##')"
[[ "$endpoint_host" =~ ^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
  || { echo "error: refusing to talk to '$endpoint_host'; only a 192.168.x lab firewall address is allowed." >&2; exit 1; }
[[ -n "${KEY:-}" && -n "${SECRET:-}" ]] || { echo "error: API key/secret not set for $HOST_ID." >&2; exit 1; }

mkdir -p "$RAW_DIR" "$PUB_DIR"
STAMP="$(date +%Y%m%d)"
RAW_FILE="$RAW_DIR/p06-ph6-opnsense-config-$HOST_ID-$STAMP.xml"
PUB_FILE="$PUB_DIR/p06-ph6-config-summary-$HOST_ID.csv"

CURL_OPTS=(--silent --show-error --fail --max-time 60)
[[ "$INSECURE" -eq 1 ]] && CURL_OPTS+=(--insecure)

echo "Exporting configuration from $URL ($HOST_ID)"
curl "${CURL_OPTS[@]}" -X GET "$URL/api/core/backup/download/this" \
  -u "$KEY:$SECRET" -o "$RAW_FILE"

chmod 600 "$RAW_FILE"
echo "Raw export written to ${RAW_FILE#"$PROJECT_DIR"/} (evidence/raw is git-ignored - do not commit it)."

# Sanitised summary: counts and section names only. No addresses, no keys, no hashes, no secrets.
count() { grep -c "$1" "$RAW_FILE" 2>/dev/null || echo 0; }
{
  echo "# P6 sanitised OPNsense configuration summary - $HOST_ID - $STAMP"
  echo "# This file contains counts only. It is deliberately free of addresses, keys, hashes and secrets."
  echo "section,count,note"
  echo "interfaces,$(count '<if>\|<interface>'),configured interfaces"
  echo "vlans,$(count '<vlan>'),802.1Q VLAN definitions"
  echo "firewall_rules,$(count '<rule>'),filter rules"
  echo "aliases,$(count '<alias>'),firewall aliases"
  echo "nat_rules,$(count '<nat>'),NAT and port-forward entries (target: no inbound forwards)"
  echo "dhcp_relays,$(count '<dhcpd>'),relay instances"
  echo "openvpn_instances,$(count '<openvpn>'),VPN servers"
  echo "wireguard_peers,$(count '<peer>'),site-to-site peers"
  echo "users,$(count '<user>'),local firewall accounts"
} > "$PUB_FILE"

echo "Sanitised summary written to ${PUB_FILE#"$PROJECT_DIR"/}"
echo
echo "Before committing anything, run the sanitisation checklist in AGENTS.md 4.6 and remember:"
echo "  - the raw export is never published, in any form, including 'just the diff';"
echo "  - no WAN address, no API key, no shared secret, no private key leaves this machine."
echo "After the first export, the config-as-code automation in P9 keeps this current automatically."

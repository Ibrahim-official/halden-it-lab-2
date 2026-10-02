#!/usr/bin/env bash
# P6 - Phase 4: site-to-site WireGuard tunnel between HQ (FW01) and the warehouse (FW02).
#
# TARGET: FW01 and FW02 only. Run BY THE OWNER against the lab firewalls (Mode A / R1 / R6).
#         The guard refuses any endpoint that is not a 192.168.x lab address.
#
# KEY HYGIENE: WireGuard private keys are generated ON THE DEVICE (OPNsense generates the pair when
#              the instance is created, or `wg genkey` on the firewall). Only the PUBLIC key is
#              exchanged with the peer. No private key is written by this script or committed.
#
# DEFAULT IS DRY-RUN. Snapshot FW01 and FW02 first (snap-p6-ph4-before).
# ROLLBACK: restore each firewall's config backup (12-Export-ConfigBackup.sh) or revert the snapshot.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: 06-Configure-WireGuardS2S.sh [--apply] [--insecure] [--peer fw01|fw02]

  --apply      perform the API calls (default: dry-run, print the GUI steps)
  --insecure   pass -k to curl (self-signed lab certificate)
  --peer       which firewall this run configures (default: fw01)

Environment:
  FW01_URL / FW01_KEY / FW01_SECRET
  FW02_URL / FW02_KEY / FW02_SECRET
Addresses come from the password manager; only the 192.168.x endpoint is accepted.
EOF
}

APPLY=0; INSECURE=0; PEER="fw01"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --insecure) INSECURE=1; shift ;;
    --peer) PEER="${2:-fw01}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

if [[ "$PEER" == "fw01" ]]; then
  URL="${FW01_URL:-}"; KEY="${FW01_KEY:-}"; SECRET="${FW01_SECRET:-}"
  LOCAL_ADDR="10.99.0.1/30"; REMOTE_ALLOWED="192.168.20.0/24, 10.99.0.2/32"; LABEL="FW01 (HQ)"
else
  URL="${FW02_URL:-}"; KEY="${FW02_KEY:-}"; SECRET="${FW02_SECRET:-}"
  LOCAL_ADDR="10.99.0.2/30"; REMOTE_ALLOWED="192.168.10.0/24, 10.99.0.1/32"; LABEL="FW02 (Warehouse)"
fi

assert_lab_endpoint() {
  [[ -n "$URL" ]] || { echo "error: the firewall URL is not set for peer '$PEER'." >&2; exit 1; }
  local host
  host="$(printf '%s' "$URL" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:.*$##')"
  [[ "$host" =~ ^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
    || { echo "error: refusing to talk to '$host'; only a 192.168.x lab firewall address is allowed." >&2; exit 1; }
}

api() {
  local method="$1" path="$2" body="${3:-}"
  [[ "$INSECURE" -eq 1 ]] && CURL_OPTS+=(--insecure)
  if [[ -n "$body" ]]; then
    curl "${CURL_OPTS[@]}" -X "$method" "$URL$path" -u "${KEY}:${SECRET}" \
      -H 'Content-Type: application/json' -d "$body"
  else
    curl "${CURL_OPTS[@]}" -X "$method" "$URL$path" -u "${KEY}:${SECRET}"
  fi
}
CURL_OPTS=(--silent --show-error --fail --max-time 20)

create_instance() {
  echo "== WireGuard instance on $LABEL =="
  if [[ "$APPLY" -eq 1 ]]; then
    api POST /api/wireguard/server/addItem "$(jq -nc --arg a "$LOCAL_ADDR" \
      '{server:{enabled:"1",name:"S2S-P6",address:$a,port:"51820",public:""}}')" >/dev/null
    echo "  instance created (listen UDP 51820). OPNsense generated the keypair on the device;"
    echo "  copy the PUBLIC key shown in the GUI and give it to the peer. Never copy the private key."
  else
    echo "  [dry-run] VPN > WireGuard > Instances > Add:"
    echo "    Name S2S-P6 · listen port 51820 · tunnel address $LOCAL_ADDR"
    echo "    OPNsense generates the keypair ON THE DEVICE. Copy the PUBLIC key to the peer only."
  fi
}

create_peer() {
  echo "== Peer entry on $LABEL =="
  echo "  [$( [[ "$APPLY" -eq 1 ]] && echo apply || echo dry-run )] VPN > WireGuard > Peers > Add:"
  echo "    Public key  : the peer's public key (from the other firewall, public half only)"
  echo "    Allowed IPs : $REMOTE_ALLOWED"
  echo "    Endpoint    : the peer's lab WAN endpoint (NAT side; no address recorded here)"
}

create_routing() {
  echo "== Static route and firewall rules on the tunnel =="
  echo "  Gateway: the WG interface. Route the remote /24 across it."
  echo "  FW01: allow WAREHOUSE_NET -> DCs / FS01 / OPS01 on AD and file ports only (matrix rules 12,13)."
  echo "  FW02: allow VLAN 20 -> the same HQ destinations. Everything else falls through to deny."
  echo "  Allow UDP 51820 inbound on each firewall's WAN so the peers can establish the tunnel."
}

verify() {
  echo "== Verification (run in the lab; paste results into docs/as-built.md) =="
  echo "  wg show                                  -> recent handshake on both peers"
  echo "  a warehouse client (VLAN 20)             -> DHCP via relay, then nltest /dsgetsite => WAREHOUSE"
  echo "  map a drive to FS01 from the warehouse   -> cross-site AD authentication works"
  echo "  These are checks to perform, not results. Nothing is claimed until captured."
}

assert_lab_endpoint
[[ -n "${KEY:-}" && -n "${SECRET:-}" ]] || { echo "error: API key/secret not set for peer '$PEER'." >&2; exit 1; }
echo "Target: $URL ($LABEL) - $( [[ "$APPLY" -eq 1 ]] && echo APPLY || echo DRY-RUN )"
create_instance
create_peer
create_routing
verify

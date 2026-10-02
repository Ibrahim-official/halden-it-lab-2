#!/usr/bin/env bash
# P6 - Phase 3: remote-access VPN (OpenVPN road-warrior) on FW01 with RADIUS to NPS and a second
# factor. Removes the old port-forwarded RDP in favour of an authenticated, MFA-protected tunnel.
#
# TARGET: FW01 only (192.168.10.1). Run BY THE OWNER against the lab firewall (Mode A / R1 / R6).
#         Never point this at the home router or anything outside the lab - the guard below refuses
#         any endpoint that is not a 192.168.x lab address.
#
# DEFAULT IS DRY-RUN: without --apply the script prints the GUI click-path so the change can be
# reviewed first. --apply performs the API calls. Snapshot FW01 first (snap-p6-ph3-before).
#
# ROLLBACK: restore the FW01 config backup from 12-Export-ConfigBackup.sh, or revert the snapshot.
#           Allowing RDP back through the firewall is NOT the rollback - that was the problem.
#
# SECRETS: the OpenVPN client certificates and keys are generated on FW01. Nothing here writes a
#          key. The RADIUS shared secret lives in NPS and FW01, vaulted, never on the command line.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: 05-Configure-OpenVpnServer.sh [--apply] [--insecure]

  --apply      perform the API calls on FW01 (default: dry-run, print the GUI steps)
  --insecure   pass -k to curl (self-signed lab certificate)

Environment: OPNSENSE_URL, OPNSENSE_KEY, OPNSENSE_SECRET (from the password manager).
EOF
}

APPLY=0; INSECURE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --insecure) INSECURE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

OPNSENSE_URL="${OPNSENSE_URL:-}"
CURL_OPTS=(--silent --show-error --fail --max-time 20)

assert_lab_endpoint() {
  [[ -n "$OPNSENSE_URL" ]] || { echo "error: OPNSENSE_URL is not set." >&2; exit 1; }
  local host
  host="$(printf '%s' "$OPNSENSE_URL" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:.*$##')"
  [[ "$host" =~ ^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
    || { echo "error: refusing to talk to '$host'; only a 192.168.x lab firewall address is allowed." >&2; exit 1; }
}

api() {
  local method="$1" path="$2" body="${3:-}"
  [[ "$INSECURE" -eq 1 ]] && CURL_OPTS+=(--insecure)
  if [[ -n "$body" ]]; then
    curl "${CURL_OPTS[@]}" -X "$method" "$OPNSENSE_URL$path" -u "${OPNSENSE_KEY}:${OPNSENSE_SECRET}" \
      -H 'Content-Type: application/json' -d "$body"
  else
    curl "${CURL_OPTS[@]}" -X "$method" "$OPNSENSE_URL$path" -u "${OPNSENSE_KEY}:${OPNSENSE_SECRET}"
  fi
}

remove_rdp_forward() {
  echo "== 1. Remove the exposed RDP port forward (the whole reason this VPN exists) =="
  if [[ "$APPLY" -eq 1 ]]; then
    echo "  Inspect the NAT table and delete any rule forwarding 3389 to an internal host:"
    api GET /api/firewall/d_nat/searchRule
  else
    echo "  [dry-run] Firewall > NAT > Port Forward: the rule forwarding TCP 3389 to FS01 is deleted."
    echo "  [dry-run] Then confirm no other inbound forward exposes an internal service."
  fi
  echo "  Proof for the evidence folder: a scan of the lab WAN from outside must show the RDP port"
  echo "  as filtered, not open. The lab WAN is only 'Hyper-V Default Switch (NAT)'; no WAN address"
  echo "  is recorded here or published anywhere (AGENTS.md 4.6)."
}

configure_openvpn() {
  echo "== 2. OpenVPN road-warrior server =="
  local body
  body="$(jq -nc '{
    vpnid:{enabled:"1",description:"P6-RoadWarrior",
      dev_mode:"tun",protocol:"UDP4",port:"1194",
      tunnel_network:"192.168.70.0/24",
      server:"192.168.70.1",local_network:"",
      authmode:"radius",
      local_group:"",cert_source:"certs",
      verify_client_cert:"1",data_ciphers:"AES-256-GCM",
      auth_digest:"SHA256",tls_crypt:"1",tunnel:"split"
    }
  }')"
  if [[ "$APPLY" -eq 1 ]]; then
    api POST /api/openvpn/instances/add "$body" >/dev/null
    echo "  OpenVPN instance created (RADIUS auth, AES-256-GCM, split tunnel)."
  else
    echo "  [dry-run] VPN > OpenVPN > Servers > Add:"
    echo "    Backend for authentication: RADIUS (the NPS server created in 04-New-NpsRadiusPolicy.ps1)"
    echo "    Tunnel network 192.168.70.0/24  ·  server address 192.168.70.1"
    echo "    TLS: AES-256-GCM, SHA256, tls-crypt on, verify client certificate on"
    echo "    Split tunnel: push only the internal routes (192.168.10.0/24, 192.168.20.0/24,"
    echo "    192.168.30.0/24, 192.168.40.0/24) and the DC as DNS server"
  fi
}

configure_mfa() {
  echo "== 3. Second factor for VPN logons =="
  echo "  Primary option: NPS Extension for Microsoft Entra MFA (authenticator push) - install only"
  echo "  while a Microsoft 365 trial is active (roadmap rule: the trial starts in the P2 window)."
  echo "  Lab fallback   : OPNsense local users with TOTP, enforced on the same RADIUS path."
  echo "  Either way the evidence must show a second factor being requested, not just a password."
}

configure_access() {
  echo "== 4. Access parity and the default deny =="
  echo "  VPN-USERS inherits the USERS-HQ allow rules (matrix rules 10 and 11) and is explicitly"
  echo "  denied to the management zone (rule 23). A staff tunnel gets the file server, not the PAW."
  echo "  IT may be granted the MGMT path through the separate G_VPN_IT group and the VPN-IT-Mgmt NPS"
  echo "  policy - a deliberate, documented exception, not an 'allow any' rule."
}

configure_client_export() {
  echo "== 5. Client package and staff guide =="
  echo "  VPN > OpenVPN > Client Export: export one profile per user (unique certificate per person)."
  echo "  The exported profile contains a private key: deliver it through the agreed secure channel."
  echo "  Give each user business/p06-remote-access-user-guide.md (the 1-page setup guide)."
}

main() {
  assert_lab_endpoint
  [[ -n "${OPNSENSE_KEY:-}" && -n "${OPNSENSE_SECRET:-}" ]] \
    || { echo "error: OPNSENSE_KEY / OPNSENSE_SECRET are not set." >&2; exit 1; }
  echo "Target: $OPNSENSE_URL  ($( [[ "$APPLY" -eq 1 ]] && echo APPLY || echo DRY-RUN ))"
  remove_rdp_forward
  configure_openvpn
  configure_mfa
  configure_access
  configure_client_export
  echo
  echo "Test: a non-member is rejected (NPS event 6273); a member with MFA reaches FS01 but not MGMT."
}

main "$@"

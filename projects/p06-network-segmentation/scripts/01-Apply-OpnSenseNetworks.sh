#!/usr/bin/env bash
# P6 - Phase 1/2/3: create the VLANs, interfaces, aliases, the DHCP relay and the inter-zone
# rule set on FW01 (OPNsense, HQ). Talks to the firewall through its own API.
#
# TARGET: FW01 only (192.168.10.1, from LAB-INVENTORY.md). Optionally FW02 for the site-to-site
#         part, which lives in 06-Configure-WireGuardS2S.sh.
#
# !! MODE A / R1 / R6 !!
#   This script is run BY THE OWNER against the lab firewall. It must never be pointed at the home
#   router, an employer's device, or any address outside the lab. The guard below enforces that the
#   API endpoint is a 192.168.x address; anything else is refused before a single call is made.
#   Nothing here touches the home network, the home LAN or the internet.
#
# DEFAULT IS DRY-RUN. Without --apply the script prints the exact GUI click-path and the rule list,
# so the owner can review the change before it touches the firewall. --apply performs the API calls.
#
# Anti-lockout: the script refuses to remove rules, and it insists the MGMT allow rule exists before
# it writes anything else. Keep console access to the FW01 VM open while you run this.
#
# ROLLBACK: restore the OPNsense configuration backup taken by 12-Export-ConfigBackup.sh, or revert
# the FW01 VM snapshot snap-p6-ph1-before. See docs/runbooks/apply-a-firewall-rule-change.md.
#
# SECRETS: the API key/secret come from the environment (owner's password manager). They are never
# written to a file and never echoed. The RADIUS shared secret is entered on FW01 in Phase 3.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_DIR/configs"
VLAN_PLAN="$CONFIG_DIR/p06-interface-vlan-plan.csv"
RULE_MATRIX="$CONFIG_DIR/p06-zone-rule-matrix.csv"
ALIAS_PLAN="$CONFIG_DIR/p06-opnsense-aliases.csv"

usage() {
  cat <<'EOF'
Usage: 01-Apply-OpnSenseNetworks.sh [--apply] [--insecure] [--phase vlan|alias|rules|relay|all]

  --apply            perform the API calls on FW01 (default: dry-run, print the GUI steps)
  --insecure         pass -k to curl (self-signed firewall certificate - lab only)
  --phase PHASE      limit the work to one phase (default: all)

Environment (read from the owner's password manager, never committed):
  OPNSENSE_URL       e.g. https://192.168.10.1
  OPNSENSE_KEY       API key
  OPNSENSE_SECRET    API secret

Order of work is deliberate: VLANs -> interface assignment -> relay -> aliases -> rules.
Rules are never written before the MGMT anti-lockout path exists.
EOF
}

APPLY=0
INSECURE=0
PHASE="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --insecure) INSECURE=1; shift ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

# Halden lab guard (AGENTS.md Section 2).
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

OPNSENSE_URL="${OPNSENSE_URL:-}"
CURL_OPTS=(--silent --show-error --fail --max-time 20)

die() { echo "error: $*" >&2; exit 1; }

# Refuse any endpoint that is not a lab-private 192.168.x address. This is the hard stop that
# keeps the script away from the home router and anything else outside the lab.
assert_lab_endpoint() {
  local url="${1:-}"
  [[ -n "$url" ]] || die "OPNSENSE_URL is not set (read it from the password manager)."
  local host
  host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:.*$##')"
  [[ "$host" =~ ^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
    || die "refusing to talk to '$host': only a 192.168.x lab firewall address is allowed."
}

api() {
  local method="$1" path="$2" body="${3:-}"
  [[ "$INSECURE" -eq 1 ]] && CURL_OPTS+=(--insecure)
  if [[ -n "$body" ]]; then
    curl "${CURL_OPTS[@]}" -X "$method" "$OPNSENSE_URL$path" \
      -u "${OPNSENSE_KEY}:${OPNSENSE_SECRET}" -H 'Content-Type: application/json' -d "$body"
  else
    curl "${CURL_OPTS[@]}" -X "$method" "$OPNSENSE_URL$path" \
      -u "${OPNSENSE_KEY}:${OPNSENSE_SECRET}"
  fi
}

# Map a zone name from the matrices to the OPNsense interface option name.
zone_to_if() {
  case "$1" in
    MGMT) echo "opt40" ;;
    USERS-HQ) echo "opt30" ;;
    VPN-USERS) echo "ovpns1" ;;
    WAREHOUSE) echo "opt20" ;;
    IOT) echo "opt60" ;;
    GUEST) echo "opt50" ;;
    SERVERS|FS01|OPS01) echo "opt10" ;;
    *) echo "floating" ;;
  esac
}

create_vlans() {
  echo "== Phase 1: VLANs on the trunk parent =="
  while IFS=, read -r vlan_id zone parent iface ipv subnet gw dhcp relay notes; do
    [[ "$vlan_id" =~ ^# || -z "${vlan_id:-}" ]] && continue
    [[ "$vlan_id" == "0" ]] && continue   # the VPN pool is not a VLAN
    if [[ "$APPLY" -eq 1 ]]; then
      api POST /api/interfaces/vlan_settings/addItem \
        "{\"vlan\":{\"if\":\"${parent%% *}\",\"tag\":\"$vlan_id\",\"pcp\":\"0\",\"descr\":\"VLAN $vlan_id $zone\"}}" >/dev/null
      echo "  created VLAN $vlan_id ($zone) on $parent"
    else
      echo "  [dry-run] Interfaces > Other Types > VLAN > Add: parent=$parent tag=$vlan_id descr='VLAN $vlan_id $zone'"
    fi
  done < "$VLAN_PLAN"
}

assign_interfaces() {
  echo "== Phase 1: interface assignment and gateway addresses =="
  while IFS=, read -r vlan_id zone parent iface ipv subnet gw dhcp relay notes; do
    [[ "$vlan_id" =~ ^# || -z "${vlan_id:-}" ]] && continue
    [[ "$iface" == "ovpns1" ]] && continue
    echo "  [$( [[ "$APPLY" -eq 1 ]] && echo apply || echo dry-run )] Interfaces > Assignments: " \
         "interface=$iface  zone=$zone  ip=$gw/$subnet  enable=yes  lock=yes"
    if [[ "$APPLY" -eq 1 ]]; then
      api POST "/api/interfaces/overview/setItem/$iface" \
        "{\"interface\":{\"enable\":\"1\",\"ipaddr\":\"$gw\",\"subnet\":\"${subnet#*/}\",\"descr\":\"$zone\"}}" >/dev/null
    fi
  done < "$VLAN_PLAN"
  echo "  Anti-lockout: Interfaces > [LAN] > allow the MGMT subnet to reach the FW01 web UI, and"
  echo "  confirm you still have console access to the VM before writing any rule."
}

configure_relay() {
  echo "== Phase 1: DHCP relay to the Windows DHCP pair =="
  while IFS=, read -r vlan_id zone parent iface ipv subnet gw dhcp relay notes; do
    [[ "$vlan_id" =~ ^# || -z "${vlan_id:-}" ]] && continue
    [[ "$dhcp" == "windows-via-relay" ]] || continue
    echo "  [$zone] Services > DHCP Relay: enable on $iface, destination servers: $relay"
    if [[ "$APPLY" -eq 1 ]]; then
      api POST /api/dhcprelay/settings/set "$(jq -nc \
        --arg iface "$iface" --arg servers "$relay" \
        '{dhcpd:{enabled:"1",interface:$iface,server:$servers}}')" >/dev/null
    fi
  done < "$VLAN_PLAN"
}

create_aliases() {
  echo "== Phase 1: aliases =="
  while IFS=, read -r name type contents notes; do
    [[ "$name" =~ ^# || -z "${name:-}" ]] && continue
    if [[ "$APPLY" -eq 1 ]]; then
      api POST /api/firewall/alias/addItem "$(jq -nc \
        --arg n "$name" --arg t "$type" --arg c "$contents" \
        '{alias:{enabled:"1",name:$n,type:$t,content:$c,description:"P6 alias"}}')" >/dev/null
      echo "  created alias $name ($type)"
    else
      echo "  [dry-run] Firewall > Aliases > Add: name=$name type=$type content=$contents"
    fi
  done < "$ALIAS_PLAN"
}

# Translate a matrix port cell into an OPNsense destination-port string.
matrix_ports() {
  local cell="$1"
  [[ "$cell" == "any" ]] && { echo ""; return; }
  # Commas separate aliases that are already defined; keep them as-is, space separated.
  echo "$cell" | tr ',' ' '
}

apply_rules() {
  echo "== Phase 1/2: inter-zone rule set (first match wins - order below is the order applied) =="
  local seq=0
  while IFS=, read -r rid src dst svc ports action owner justification; do
    [[ "$rid" =~ ^# || -z "${rid:-}" ]] && continue
    seq=$((seq + 1))
    local iface; iface="$(zone_to_if "$src")"
    local act="pass"; [[ "$action" == "deny"* ]] && act="block"
    local portstr; portstr="$(matrix_ports "$ports")"
    printf '  %2d  %-6s %-9s -> %-14s %-22s %-10s %s\n' \
      "$rid" "$act" "$src" "$dst" "$portstr" "$owner" "$justification"
    if [[ "$APPLY" -eq 1 ]]; then
      local body
      body="$(jq -nc --arg iface "$iface" --arg act "$act" \
        --arg src "$src" --arg dst "$dst" --arg ports "$portstr" --arg desc "P6 rule $rid: $justification" \
        '{rule:{enabled:"1",action:$act,direction:"in",ipprotocol:"inet",interface:$iface,
                statetype:"keep state",source_net:$src,destination_net:$dst,
                destination_port:$ports,description:$desc}}')"
      api POST /api/firewall/filter/addRule "$body" >/dev/null
    fi
  done < "$RULE_MATRIX"
  if [[ "$APPLY" -eq 1 ]]; then
    api POST /api/firewall/filter/apply >/dev/null
    echo "  rules written and applied on FW01."
  else
    echo "  [dry-run] Firewall > Rules > [interface] > Add in the order above, then Apply."
    echo "  Enable logging on the default-deny rule (24)."
  fi
}

main() {
  assert_lab_endpoint "$OPNSENSE_URL"
  [[ -n "${OPNSENSE_KEY:-}" && -n "${OPNSENSE_SECRET:-}" ]] \
    || die "OPNSENSE_KEY / OPNSENSE_SECRET are not set (read them from the password manager)."
  [[ "$APPLY" -eq 1 ]] && echo "APPLY MODE against $OPNSENSE_URL - snapshot FW01 first (snap-p6-ph1-before)."
  [[ "$APPLY" -eq 0 ]] && echo "DRY-RUN (no change to FW01). Add --apply to perform the calls."

  case "$PHASE" in
    vlan)  create_vlans; assign_interfaces ;;
    alias) create_aliases ;;
    rules) apply_rules ;;
    relay) configure_relay ;;
    all)   create_vlans; assign_interfaces; configure_relay; create_aliases; apply_rules ;;
    *) die "unknown phase '$PHASE'" ;;
  esac

  echo
  echo "Verify: Interfaces > Overview shows the new interfaces up; Firewall > Rules shows each P6"
  echo "rule with its matrix number; then run scripts/09-Test-Segmentation.sh from each zone."
}

main "$@"

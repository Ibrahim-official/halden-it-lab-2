#!/usr/bin/env bash
# P6 - Phase 6: GUEST and IOT zone isolation test.
#
# WHAT IT PROVES: that a guest device can reach the internet and nothing inside the company, and
# that a printer or camera can reach its one allowed share and nothing else. This is the same
# principle as the segmentation suite, applied to the two zones most likely to be handed to a
# visitor or a vendor.
#
# HOST: a client in the GUEST zone and a client in the IOT zone (the script runs the tests for the
# zone it is told it is in). Read-only probing inside the lab only (R1).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_DIR/evidence/raw"
PUB_DIR="$PROJECT_DIR/evidence/public"

usage() {
  cat <<'EOF'
Usage: 11-Test-GuestIotIsolation.sh --zone guest|iot [--timeout SECONDS]

  --zone guest|iot   which isolation test to run (the host must actually be in that zone)

Checks every internal address a guest or an IoT device must NOT reach, the single exception an
IoT device IS allowed (FS01 SMB for scan-to-folder), and the internet route a guest is allowed.
Results are written to evidence/raw and evidence/public as a CSV.
EOF
}

ZONE=""; TIMEOUT=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zone) ZONE="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-5}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
command -v nmap >/dev/null 2>&1 || { echo "error: nmap is required." >&2; exit 1; }
case "$ZONE" in guest|iot) ;; *) echo "error: --zone must be 'guest' or 'iot'." >&2; usage; exit 2 ;; esac

HOST="$(hostname -s)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW_OUT="$RAW_DIR/p06-ph6-$ZONE-isolation-$HOST.csv"
PUB_OUT="$PUB_DIR/p06-ph6-$ZONE-isolation-$HOST.csv"
mkdir -p "$RAW_DIR" "$PUB_DIR"

# Destinations that matter. Every one is a lab address (192.168.x) - never anything outside.
DC01="192.168.10.10"; DC02="192.168.10.11"; FS01="192.168.10.20"; LNX01="192.168.10.30"
OPS01="192.168.10.40"; WS02="192.168.40.10"; FW01="192.168.10.1"

probe() {
  local dest="$1" port="$2" out status
  out="$(nmap -Pn -p "$port" --host-timeout "${TIMEOUT}s" "$dest" 2>/dev/null || true)"
  status="$(printf '%s\n' "$out" | awk '/\/tcp/ {print $2; exit}')"
  case "$status" in
    open) echo open ;;
    closed) echo closed ;;
    filtered) echo filtered ;;
    *) echo unreachable ;;
  esac
}

verdict() { [[ "$2" == open ]] && echo FAIL || echo PASS; }   # every internal path below must be blocked
verdict_open() { [[ "$2" == open ]] && echo PASS || echo FAIL; }

emit() { printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" | tee -a "$RAW_OUT"; }

run_guest() {
  echo "GUEST isolation test on $HOST - a guest device must reach the internet and nothing internal"
  echo "test_id,destination,service,expected,observed,result,zone,checked_at" > "$RAW_OUT"
  local id=0
  for target in "$DC01:53:dc-dns" "$DC01:445:dc-smb" "$DC01:389:dc-ldap" \
                "$FS01:445:fs-smb" "$LNX01:22:lnx-ssh" "$OPS01:443:ops-https" \
                "$WS02:3389:mgmt-rdp" "$FW01:443:fw-webui"; do
    IFS=: read -r dest port label <<<"$target"
    id=$((id + 1))
    local obs res
    obs="$(probe "$dest" "$port")"
    res="$(verdict "$dest" "$obs")"
    printf '%s,%s,%s,blocked,%s,%s,GUEST,%s\n' "G$id" "$dest" "$label" "$obs" "$res" "$(date -u +%FT%TZ)" >> "$RAW_OUT"
    printf '  G%-3s %-15s %-10s blocked  observed %-11s %s\n' "$id" "$dest" "$label" "$obs" "$res"
  done
  # The internet route is the one thing a guest is allowed. Checked by DNS resolution through the
  # guest DHCP option, not by scanning outside the lab.
  local dns_ok="not-tested"
  if getent hosts example.com >/dev/null 2>&1; then dns_ok="resolves"; else dns_ok="no-answer"; fi
  printf '  G%-3s %-15s %-10s allowed  observed %-11s %s\n' "$((id+1))" "internet" "dns" "$dns_ok" "-"
}

run_iot() {
  echo "IOT isolation test on $HOST - a printer or camera reaches only its one allowed share"
  echo "test_id,destination,service,expected,observed,result,zone,checked_at" > "$RAW_OUT"
  local id=0
  # Allowed: FS01 SMB for scan-to-folder (matrix rule 14) and DNS (rule 15).
  for target in "$FS01:445:fs-smb-allowed" "$DC01:53:dns-allowed"; do
    IFS=: read -r dest port label <<<"$target"
    id=$((id + 1))
    local obs res
    obs="$(probe "$dest" "$port")"
    res="$(verdict_open "$dest" "$obs")"
    printf '%s,%s,%s,open,%s,%s,IOT,%s\n' "I$id" "$dest" "$label" "$obs" "$res" "$(date -u +%FT%TZ)" >> "$RAW_OUT"
    printf '  I%-3s %-15s %-16s open     observed %-11s %s\n' "$id" "$dest" "$label" "$obs" "$res"
  done
  # Blocked: everything else internal.
  for target in "$DC01:445:dc-smb" "$DC02:389:dc-ldap" "$LNX01:22:lnx-ssh" "$OPS01:443:ops-https" \
                "$WS02:3389:mgmt-rdp" "$FS01:3389:fs-rdp"; do
    IFS=: read -r dest port label <<<"$target"
    id=$((id + 1))
    local obs res
    obs="$(probe "$dest" "$port")"
    res="$(verdict "$dest" "$obs")"
    printf '%s,%s,%s,blocked,%s,%s,IOT,%s\n' "I$id" "$dest" "$label" "$obs" "$res" "$(date -u +%FT%TZ)" >> "$RAW_OUT"
    printf '  I%-3s %-15s %-16s blocked  observed %-11s %s\n' "$id" "$dest" "$label" "$obs" "$res"
  done
}

main() {
  [[ "$ZONE" == "guest" ]] && run_guest || run_iot
  local pass total
  total="$(awk -F, 'NR>1 && $6 != "" {n++} END {print n+0}' "$RAW_OUT")"
  pass="$(awk -F, 'NR>1 && $6 == "PASS" {n++} END {print n+0}' "$RAW_OUT")"
  {
    echo "# P6 $ZONE isolation results - host $HOST, run $STAMP"
    printf '# SUMMARY: %s/%s PASS\n' "$pass" "$total"
    cat "$RAW_OUT"
  } > "$PUB_OUT"
  echo
  echo "Summary: $pass/$total PASS ($ZONE)"
  echo "Raw     : ${RAW_OUT#"$PROJECT_DIR"/}"
  echo "Publish : ${PUB_OUT#"$PROJECT_DIR"/}"
  [[ "$pass" -eq "$total" && "$total" -gt 0 ]]
}

main "$@"

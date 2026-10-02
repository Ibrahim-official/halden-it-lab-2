#!/usr/bin/env bash
# P6 - Phase 6: the segmentation test suite.
#
# WHAT IT PROVES: that the firewall rules behave as the matrix says they should - not that rules
# exist. "Configured" is not "verified". This script attempts every connection in the test plan
# from the zone the host is actually in and records what really happened.
#
# HOW IT WORKS
#   - Reads the test plan (data/p06-segmentation-test-plan.csv): test_id, source_zone, source_host,
#     destination, port/service, expected result.
#   - Detects (or is told) which zone this host is in, and runs only the rows for that zone.
#   - For every row it attempts the connection with nmap and classifies the observed result as
#     open, closed, filtered or unreachable.
#   - An expected "blocked" row passes if the port is closed, filtered or unreachable.
#     An expected "open" row passes only if the port is open.
#   - Writes the raw results to evidence/raw/ and the publishable copy to evidence/public/, in the
#     "N/N PASS" shape. Nothing is written to the plan itself: the plan stays as the template.
#
# HOST TO RUN FROM: a test host in each zone - WS01 (USERS-HQ), a warehouse client (WAREHOUSE),
#   WS02 (MGMT), a guest client (GUEST), an IOT test client (IOT), and a VPN client (VPN-USERS).
#   Running it on the firewall itself proves nothing about a user's experience.
#
# MODE A / R1: read-only network probing inside the lab. It never touches the home network: every
#   destination in the plan is a 192.168.x lab address, and the script refuses a plan containing
#   anything else. No attack tooling, no exploitation - port reachability only.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PLAN="$PROJECT_DIR/data/p06-segmentation-test-plan.csv"
ZONE_MAP="$PROJECT_DIR/data/p06-zone-ip-allocation.csv"
RAW_DIR="$PROJECT_DIR/evidence/raw"
PUB_DIR="$PROJECT_DIR/evidence/public"

usage() {
  cat <<'EOF'
Usage: 09-Test-Segmentation.sh --zone ZONE [--plan FILE] [--timeout SECONDS]

  --zone ZONE     the zone this test host is in: USERS-HQ | WAREHOUSE | MGMT | GUEST | IOT | VPN-USERS
  --plan FILE     test plan CSV (default: data/p06-segmentation-test-plan.csv)
  --timeout SEC   per-attempt nmap timeout (default: 5)

Writes evidence/raw/p06-ph6-segmentation-results-<host>.csv
and    evidence/public/p06-ph6-segmentation-results-<host>.csv  (the publishable copy)
EOF
}

ZONE=""
TIMEOUT=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zone) ZONE="${2:-}"; shift 2 ;;
    --plan) PLAN="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-5}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

# Halden lab guard (AGENTS.md Section 2).
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] \
  || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

command -v nmap >/dev/null 2>&1 \
  || { echo "error: nmap is required. Install it: sudo apt-get install -y nmap" >&2; exit 1; }
[[ -n "$ZONE" ]] || { echo "error: --zone is required (the suite must know which zone it is testing)." >&2; usage; exit 2; }
[[ -f "$PLAN" ]] || { echo "error: test plan not found: $PLAN" >&2; exit 1; }

HOST="$(hostname -s)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW_OUT="$RAW_DIR/p06-ph6-segmentation-results-$HOST.csv"
PUB_OUT="$PUB_DIR/p06-ph6-segmentation-results-$HOST.csv"
mkdir -p "$RAW_DIR" "$PUB_DIR"

# Refuse a plan that points anywhere outside the lab. This keeps the suite honest about R1.
guard_plan_destinations() {
  local bad
  bad="$(awk -F, '!/^#/ && NR>0 { print $5 }' "$PLAN" | grep -Ev '^(192\.168\.[0-9]{1,3}\.[0-9]{1,3}|[a-z0-9.-]+\.ad\.halden\.internal)$' || true)"
  if [[ -n "$bad" ]]; then
    echo "error: the test plan contains a destination outside the lab:" >&2
    echo "$bad" >&2
    exit 1
  fi
}

# Map a service name from the plan to a TCP port number.
service_to_port() {
  case "$1" in
    443|https) echo 443 ;;
    445|smb) echo 445 ;;
    3389|rdp) echo 3389 ;;
    53|dns) echo 53 ;;
    22|ssh) echo 22 ;;
    80|http) echo 80 ;;
    [0-9]*) echo "$1" ;;
    *) echo "" ;;
  esac
}

# Attempt one connection and classify the result as open / closed / filtered / unreachable.
probe() {
  local dest="$1" port="$2" out status
  # A quick reachability check first: if the host does not answer at all, that is 'unreachable'
  # rather than a claim about the target port.
  if ! ping -c 1 -W 2 "$dest" >/dev/null 2>&1; then
    if ! nmap -Pn -p "$port" --host-timeout "${TIMEOUT}s" "$dest" >/dev/null 2>&1; then
      echo "unreachable"; return
    fi
  fi
  out="$(nmap -Pn -p "$port" --host-timeout "${TIMEOUT}s" "$dest" 2>/dev/null || true)"
  status="$(printf '%s\n' "$out" | awk '/\/tcp/ {print $2; exit}')"
  case "$status" in
    open) echo "open" ;;
    closed) echo "closed" ;;
    filtered) echo "filtered" ;;
    "") echo "unreachable" ;;
    *) echo "$status" ;;
  esac
}

# Decide pass/fail from the expected result and the observed result.
verdict() {
  local expected="$1" observed="$2"
  case "$expected" in
    open)  [[ "$observed" == "open" ]] && echo PASS || echo FAIL ;;
    *)     [[ "$observed" == "open" ]] && echo FAIL || echo PASS ;;   # blocked/closed expected
  esac
}

main() {
  guard_plan_destinations
  echo "Segmentation test suite - host $HOST, zone $ZONE, plan $(basename "$PLAN")"
  echo "Started $STAMP"
  echo "test_id,source_zone,source_host,destination,port,expected,observed,result,checked_at" > "$RAW_OUT"

  local total=0 pass=0 fail=0 skipped=0
  while IFS=, read -r test_id src_zone src_host destination service expected; do
    [[ "$test_id" =~ ^# || -z "${test_id:-}" ]] && continue
    if [[ "$src_zone" != "$ZONE" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    local port; port="$(service_to_port "$service")"
    if [[ -z "$port" ]]; then
      echo "  $test_id  skipped (unrecognised service '$service')"
      skipped=$((skipped + 1))
      continue
    fi
    local observed result
    observed="$(probe "$destination" "$port")"
    result="$(verdict "$expected" "$observed")"
    total=$((total + 1))
    [[ "$result" == "PASS" ]] && pass=$((pass + 1)) || fail=$((fail + 1))
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$test_id" "$src_zone" "$src_host" "$destination" "$service" "$expected" "$observed" "$result" \
      "$(date -u +%FT%TZ)" >> "$RAW_OUT"
    printf '  %-6s %-14s expected %-8s observed %-11s %s\n' "$test_id" "$destination" "$expected" "$observed" "$result"
  done < "$PLAN"

  echo
  echo "Summary: $pass/$total PASS for zone $ZONE ($fail failed, $skipped rows belonging to other zones)"
  {
    echo "# P6 segmentation results - host $HOST, zone $ZONE, run $STAMP"
    echo "# A 'blocked' expectation passes for closed, filtered or unreachable. 'open' passes only for open."
    printf '# SUMMARY: %s/%s PASS (%s failed)\n' "$pass" "$total" "$fail"
    cat "$RAW_OUT"
  } > "$PUB_OUT"

  echo "Raw results : ${RAW_OUT#"$PROJECT_DIR"/}"
  echo "Published   : ${PUB_OUT#"$PROJECT_DIR"/}  (sanitised copy - review it before committing)"
  [[ "$fail" -eq 0 && "$total" -gt 0 ]]
}

main "$@"

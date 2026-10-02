#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 Phase 3: detection validation
# Run on: SIEM01 (Ubuntu Server 24.04) as root, AFTER an approved simulation run (scripts/07)
# and after the analyst has let the alerts settle (allow 2-3 minutes).
#
# WHAT THIS DOES
#   Reads the manager's alerts for the custom rule IDs (100100-100116) within a time window and
#   reports which rules actually fired, how many times and when the first hit was. It makes NO
#   claim about coverage by itself: it prints the observed facts and writes a raw JSON extract to
#   evidence/raw (git-ignored). The sanitized, publishable version is produced by scripts/09.
#
# USAGE
#   sudo ./08-Validate-Detections.sh [-w 30]     # look back 30 minutes (default)
# =============================================================================
set -euo pipefail

WINDOW_MIN=30
while getopts ":w:h" opt; do
  case "$opt" in
    w) WINDOW_MIN="$OPTARG" ;;
    h) sed -n '2,16p' "$0"; exit 0 ;;
    *) : ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="$PROJECT_DIR/evidence/raw"
mkdir -p "$RAW_DIR"

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

find_manager() { docker ps -qf "name=wazuh.manager" | head -n1; }

MANAGER="$(find_manager)"
[[ -n "$MANAGER" ]] || { echo "wazuh.manager container not found." >&2; exit 1; }

RAW_OUT="$RAW_DIR/p07-ph3-detection-raw-extract.json"
echo "Reading alerts from the last ${WINDOW_MIN} minutes..."

# Pull the alert log out of the container to the raw evidence folder (never committed).
docker exec "$MANAGER" cat /var/ossec/logs/alerts/alerts.json > "$RAW_OUT" 2>/dev/null || true

python3 - "$RAW_OUT" "$WINDOW_MIN" <<'PY'
import json, sys, datetime, collections

path, window = sys.argv[1], int(sys.argv[2])
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=window)
custom = {f"1001{n:02d}" for n in range(0, 17)}   # 100100-100116
hits = collections.defaultdict(lambda: {"count": 0, "first": None, "last": None, "desc": ""})

def parse_ts(value):
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.datetime.strptime(value, fmt)
        except (ValueError, TypeError):
            continue
    return None

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            alert = json.loads(line)
        except json.JSONDecodeError:
            continue
        rule = str(alert.get("rule", {}).get("id", ""))
        if rule not in custom:
            continue
        ts = parse_ts(alert.get("timestamp", ""))
        if ts is not None and ts < cutoff:
            continue
        bucket = hits[rule]
        bucket["count"] += 1
        bucket["desc"] = alert.get("rule", {}).get("description", "")
        if bucket["first"] is None or (ts and ts < bucket["first"]):
            bucket["first"] = ts
        if bucket["last"] is None or (ts and ts > bucket["last"]):
            bucket["last"] = ts

print(f"\n{'rule':>8}  {'count':>5}  {'first alert (UTC)':<26}  description")
print("-" * 100)
if not hits:
    print("No custom rules fired in the window. That is a RESULT, not a failure — record it as such:")
    print("a rule that did not fire is a rule that needs tuning or a test that Defender prevented.")
for rule in sorted(hits):
    h = hits[rule]
    first = h["first"].strftime("%Y-%m-%d %H:%M:%S") if h["first"] else "unknown"
    print(f"{rule:>8}  {h['count']:>5}  {first:<26}  {h['desc'][:60]}")
print("\nThis output is the raw observation only. Fill configs/detection-coverage-matrix.csv from it")
print("(validated = YES/NO, time_to_alert_s = observed). Do not invent a value for a rule that did not fire.")
PY
echo
echo "Raw extract: $RAW_OUT (git-ignored). Run scripts/09 for a sanitized, publishable extract."

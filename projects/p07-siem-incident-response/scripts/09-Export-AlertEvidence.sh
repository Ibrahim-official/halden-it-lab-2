#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 triage/export helper: sanitized alert evidence
# Run on: SIEM01 (Ubuntu Server 24.04) as root.
#
# WHAT THIS DOES
#   Takes alerts for one or more custom rule IDs and produces a SMALL, SANITIZED markdown extract
#   suitable for the portfolio (evidence/public). It deliberately does not copy the alert verbatim:
#   it keeps the fields that prove the detection and strips everything else, then runs a redaction
#   pass for anything that looks like a secret.
#
# WHY THE SANITIZATION MATTERS (AGENTS.md 4.6)
#   Raw Wazuh archives and alert dumps are never published. Command lines can contain credentials
#   or tokens even in a lab, so they are redacted by pattern. Private lab IPs are fine to publish;
#   anything resembling a password, key or token is not.
#
# USAGE
#   sudo ./09-Export-AlertEvidence.sh -r 100100,100107 -w 60 -t "D1 privileged group add, D7 shadow deletion"
# =============================================================================
set -euo pipefail

RULES="100100,100107"
WINDOW_MIN=60
TITLE="Halden P7 detection alert extract"
while getopts ":r:w:t:h" opt; do
  case "$opt" in
    r) RULES="$OPTARG" ;;
    w) WINDOW_MIN="$OPTARG" ;;
    t) TITLE="$OPTARG" ;;
    h) sed -n '2,18p' "$0"; exit 0 ;;
    *) : ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="$PROJECT_DIR/evidence/raw"; PUBLIC_DIR="$PROJECT_DIR/evidence/public"
mkdir -p "$RAW_DIR" "$PUBLIC_DIR"

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

find_manager() { docker ps -qf "name=wazuh.manager" | head -n1; }
MANAGER="$(find_manager)"
[[ -n "$MANAGER" ]] || { echo "wazuh.manager container not found." >&2; exit 1; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RAW_OUT="$RAW_DIR/p07-ph3-alertextract-$STAMP.json"
OUT="$PUBLIC_DIR/p07-ph3-alert-extract-$STAMP.md"

docker exec "$MANAGER" cat /var/ossec/logs/alerts/alerts.json > "$RAW_OUT" 2>/dev/null || true

python3 - "$RAW_OUT" "$RULES" "$WINDOW_MIN" "$TITLE" "$OUT" <<'PY'
import json, re, sys, datetime

raw_path, rules_arg, window, title, out_path = sys.argv[1:6]
want = {r.strip() for r in rules_arg.split(",") if r.strip()}
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(window))

# Redaction patterns for anything secret-shaped. Kept conservative; review the output by eye too.
SECRET_PATTERNS = [
    (re.compile(r"(?i)(password|passwd|pwd|secret|token|api[_-]?key|authorization|bearer)\s*[=:]\s*\S+"), r"\1=<redacted>"),
    (re.compile(r"-----BEGIN [A-Z ]+-----.*?-----END [A-Z ]+-----", re.S), "<redacted-key>"),
]
def scrub(value: str) -> str:
    for pattern, repl in SECRET_PATTERNS:
        value = pattern.sub(repl, value)
    return value

def parse_ts(value):
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.datetime.strptime(value, fmt)
        except (ValueError, TypeError):
            continue
    return None

rows = []
with open(raw_path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            alert = json.loads(line)
        except json.JSONDecodeError:
            continue
        rule = alert.get("rule", {})
        if str(rule.get("id", "")) not in want:
            continue
        ts = parse_ts(alert.get("timestamp", ""))
        if ts is not None and ts < cutoff:
            continue
        rows.append({
            "time": alert.get("timestamp", "unknown"),
            "rule": rule.get("id", ""),
            "level": rule.get("level", ""),
            "description": scrub(str(rule.get("description", ""))),
            "agent": alert.get("agent", {}).get("name", "unknown"),
        })

with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(f"# {title}\n\n")
    fh.write("_Sanitized extract produced by scripts/09-Export-AlertEvidence.sh. Raw Wazuh archives "
             "are not published (AGENTS.md 4.6). One row per alert, newest last._\n\n")
    if not rows:
        fh.write("**No alerts matched the requested rules in this window.** Recorded as observed; "
                 "a rule that did not fire is not a pass, it is a fact to tune against.\n")
    else:
        fh.write("| Time (UTC) | Rule | Level | Host | Detection |\n|---|---|---|---|---|\n")
        for r in rows:
            fh.write(f"| {r['time']} | {r['rule']} | {r['level']} | {r['agent']} | {r['description']} |\n")
        fh.write(f"\n**{len(rows)} alert(s) observed for rule(s) {', '.join(sorted(want))} in the last "
                 f"{window} minutes.**\n")

print(f"Wrote {out_path} ({len(rows)} rows).")
print(f"Raw extract kept (git-ignored): {raw_path}")
if not rows:
    print("NOTE: no matching alerts. Do not treat this as a failure or a pass — it is an observation.")
PY

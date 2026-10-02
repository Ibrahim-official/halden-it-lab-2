#!/usr/bin/env bash
# =============================================================================
# Halden Distribution Ltd. — P7 Phase 5: availability monitoring (Uptime Kuma)
# Run on: OPS01 (Ubuntu Server 24.04, 192.168.10.40) as root.
# Snapshot first (OPS01 hosts GLPI/BookStack too — do not disturb them): snap-p7-ph5-before.
#
# WHAT THIS DOES
#   1. Records the monitor set from the P7 plan (DNS, LDAP, SMB, web apps, VPN) as monitors.csv.
#   2. Installs two push-monitor helper scripts:
#        halden-disk-push.sh        — reports disk usage < 85% to Uptime Kuma
#        halden-backup-heartbeat.sh — called by the P8 backup job on success; a MISSING heartbeat
#                                      means a failed backup, which is the point of this monitor
#   3. If UPTIME_KUMA_TOKEN is set, creates the monitors through the Uptime Kuma API; otherwise
#      prints the table so they can be added in the UI (either is fine — record which you did).
#
# NOTE: Uptime Kuma is installed during P9 per the roadmap (docs/plan/01). If it is not up yet,
#       this script still lays down the helper scripts and the monitor definitions ready for P9.
# =============================================================================
set -euo pipefail

UPTIME_KUMA_URL="${UPTIME_KUMA_URL:-http://192.168.10.40:3001}"
DEST="${DEST:-/opt/uptime-kuma-halden}"
DRY_RUN=0
[[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]] && DRY_RUN=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,20p' "$0"; exit 0; }

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
run() { if (( DRY_RUN )); then echo "DRY-RUN: $*"; else "$@"; fi; }

# --- Hard lab guard (AGENTS.md Section 2) ------------------------------------
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || {
  echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

write_monitor_definitions() {
  run install -d -m 0755 "$DEST"
  if (( DRY_RUN )); then echo "DRY-RUN: write $DEST/monitors.csv"; return; fi
  cat > "$DEST/monitors.csv" <<'CSV'
# Halden P7 availability monitors — create these in Uptime Kuma (P9 installs it; P7 uses it).
# type,target,interval_s,why
DNS resolution,dc01/dc02 resolve ad.halden.internal SRV,60,"Tier 0 name resolution"
LDAP (TCP 389/636),DC01 and DC02,60,"Identity services reachable"
SMB (TCP 445),FS01,60,"File services reachable"
HTTPS keyword,GLPI (P9) expected page text,120,"Service desk availability"
HTTPS keyword,BookStack expected page text,120,"Runbooks/knowledge base availability"
HTTPS keyword,Wazuh dashboard expected page text,120,"SIEM availability"
TCP,FW01 VPN endpoint,60,"Remote access reachable (no probe past the endpoint)"
Push heartbeat,backup job -> halden-backup-heartbeat.sh,per run,"A MISSING heartbeat means a failed backup"
Push,disk usage -> halden-disk-push.sh,3600,"Detect a filling disk before users report it"
CSV
  log "Wrote $DEST/monitors.csv"
}

install_disk_push() {
  if (( DRY_RUN )); then echo "DRY-RUN: install $DEST/halden-disk-push.sh"; return; fi
  cat > "$DEST/halden-disk-push.sh" <<SCRIPT
#!/usr/bin/env bash
# Push disk usage to Uptime Kuma. Exit non-zero (and the monitor goes down) if any FS is >= 85%.
set -euo pipefail
[[ "\$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
: "\${UPTIME_KUMA_PUSH_URL:?set UPTIME_KUMA_PUSH_URL to the monitor push token URL}"
worst=\$(df -P -x tmpfs -x devtmpfs | awk 'NR>1 {gsub("%","",\$5); if (\$5+0>m) m=\$5+0} END {print m+0}')
status=up; [[ "\$worst" -ge 85 ]] && status=down
curl -fsS --max-time 10 "\${UPTIME_KUMA_PUSH_URL}?status=\$status&msg=\$(hostname -s)%20disk%20\${worst}%25" >/dev/null
echo "disk worst=\${worst}% status=\${status}"
SCRIPT
  chmod 0755 "$DEST/halden-disk-push.sh"
  log "Installed $DEST/halden-disk-push.sh"
}

install_backup_heartbeat() {
  if (( DRY_RUN )); then echo "DRY-RUN: install $DEST/halden-backup-heartbeat.sh"; return; fi
  cat > "$DEST/halden-backup-heartbeat.sh" <<'SCRIPT'
#!/usr/bin/env bash
# Called by the P8 backup job ON SUCCESS ONLY. The Uptime Kuma push monitor is configured with a
# "heartbeat" interval: if this script does not run, the monitor goes DOWN — a missing heartbeat is
# the signal that the backup did not complete.
set -euo pipefail
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
: "${UPTIME_KUMA_BACKUP_PUSH_URL:?set UPTIME_KUMA_BACKUP_PUSH_URL to the backup monitor push token URL}"
curl -fsS --max-time 10 "${UPTIME_KUMA_BACKUP_PUSH_URL}?status=up&msg=backup%20completed%20$(hostname -s)" >/dev/null
echo "backup heartbeat sent"
SCRIPT
  chmod 0755 "$DEST/halden-backup-heartbeat.sh"
  log "Installed $DEST/halden-backup-heartbeat.sh (wire it into the P8 backup job on success)"
}

create_monitors_via_api() {
  if [[ -z "${UPTIME_KUMA_TOKEN:-}" ]]; then
    echo
    echo "UPTIME_KUMA_TOKEN not set — add the monitors in the Uptime Kuma UI using $DEST/monitors.csv."
    echo "Notifications: set a Telegram/Teams webhook + email, and escalate every 30 min until acknowledged."
    echo "Status page: publish one for staff ('is it down or just me?') — this also cuts helpdesk tickets."
    return
  fi
  log "Creating monitors through the Uptime Kuma API at $UPTIME_KUMA_URL"
  # The REST shape evolves between Uptime Kuma versions; verify against the installed version's API
  # docs before running. The token must come from the owner's password manager, never from Git.
  while IFS=, read -r type target interval why; do
    [[ "$type" == \#* || -z "$type" ]] && continue
    run curl -fsS -X POST "$UPTIME_KUMA_URL/api/monitor" \
      -H "Authorization: Bearer $UPTIME_KUMA_TOKEN" -H "Content-Type: application/json" \
      -d "{\"name\":\"$type - $target\",\"type\":\"$type\",\"target\":\"$target\",\"interval\":$interval}" || true
  done < "$DEST/monitors.csv"
  log "Monitor creation attempted. VERIFY in the UI — do not assume a 200 means a working monitor."
}

write_monitor_definitions
install_disk_push
install_backup_heartbeat
create_monitors_via_api
echo
echo "Done. Definitions: $DEST/monitors.csv ; helpers in $DEST/."
echo "Verify: Uptime Kuma dashboard shows each monitor green, and the backup push monitor shows a heartbeat."

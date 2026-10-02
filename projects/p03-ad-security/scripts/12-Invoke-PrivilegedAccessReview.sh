#!/usr/bin/env bash
#
# 12-Invoke-PrivilegedAccessReview.sh — P3: the recurring privileged-access review.
#
# What:   run the monthly/quarterly privileged-access review end to end. It re-runs the automated
#         checks on a domain controller over PowerShell remoting (WinRM), archives their output
#         under a date-stamped folder, and prints the human follow-up steps. Read-only: it changes
#         nothing in the directory.
# Where:  runs from a management host inside the Halden lab and targets DC01 (192.168.10.10).
#         Lab only — the guard below refuses any host that is not part of ad.halden.internal.
# Why:    privilege creep is normal. A tiering model that is applied once and never reviewed is
#         just a diagram; the review is the control.
# Status: designed. Nothing has been run against the lab yet (AGENTS.md rule R2).
#
# Usage:
#   ./12-Invoke-PrivilegedAccessReview.sh [--target DC01] [--archive-dir DIR] [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TARGET="DC01"
ARCHIVE_DIR="${PROJECT_DIR}/evidence/raw/p03-privileged-access-reviews"
DRY_RUN="no"
STAMP="$(date +%Y%m%d)"

usage() {
  cat <<'EOF'
Usage: 12-Invoke-PrivilegedAccessReview.sh [options]

  --target NAME       domain controller to run the checks on (default DC01)
  --archive-dir DIR   where review output is stored (default evidence/raw/p03-privileged-access-reviews)
  --dry-run           print what would run, without connecting anywhere
  -h | --help         show this help

Read-only: this script never changes the directory. It runs the P3 verification scripts over
PowerShell remoting and archives the output as the review evidence.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)      TARGET="${2:?--target needs a host name}"; shift 2 ;;
    --archive-dir) ARCHIVE_DIR="${2:?--archive-dir needs a path}"; shift 2 ;;
    --dry-run)     DRY_RUN="yes"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- Lab guard (AGENTS.md Section 2 / rule R1) ------------------------------------------------
if [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]]; then
  :
else
  echo "Not a Halden lab host. Aborting." >&2
  exit 1
fi

run_review() {
  local script="$1" out="$2"
  echo "  -> ${script}"
  pwsh -NoProfile -NonInteractive -Command \
    "Invoke-Command -ComputerName ${TARGET} -ScriptBlock { & '${script}' } | Out-String" \
    > "${out}"
}

echo "P3 privileged-access review — $(date -Iseconds)"
echo "Target: ${TARGET}   Archive: ${ARCHIVE_DIR}"

if [[ "${DRY_RUN}" == "yes" ]]; then
  echo "Dry run: would run 10-Test-PrivilegedAccess.ps1 and 11-Verify-Remediation.ps1 on ${TARGET}"
  echo "Dry run: would write to ${ARCHIVE_DIR}/${STAMP}/"
  exit 0
fi

mkdir -p "${ARCHIVE_DIR}/${STAMP}"
run_review "C:\\halden\\projects\\p03-ad-security\\scripts\\10-Test-PrivilegedAccess.ps1" \
  "${ARCHIVE_DIR}/${STAMP}/p03-review-privilege-audit-${STAMP}.txt"
run_review "C:\\halden\\projects\\p03-ad-security\\scripts\\11-Verify-Remediation.ps1" \
  "${ARCHIVE_DIR}/${STAMP}/p03-review-verification-${STAMP}.txt"

cat <<EOF

Review output archived under ${ARCHIVE_DIR}/${STAMP}/.

Now complete the human part of the review (it cannot be automated):
  1. Read every exception in the privilege-audit output and decide: fix, or risk-accept with an
     owner and a review date.
  2. Confirm each privileged account still has a named role holder - a privileged account with
     no owner is a finding in itself.
  3. Confirm the exact list of people who can read a LAPS password is still justified.
  4. Record the outcome in business/p03-privileged-access-policy.md (review section) and, when
     P10 exists, in the change and KPI record.

Nothing in this output is a published result until it has actually been run and reviewed.
EOF

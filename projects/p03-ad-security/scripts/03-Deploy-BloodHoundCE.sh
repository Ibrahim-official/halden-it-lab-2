#!/usr/bin/env bash
#
# 03-Deploy-BloodHoundCE.sh — P3 Phase 1 (LAB ONLY, AUTHORISED EXERCISE)
#
# What:   start (or tear down) BloodHound Community Edition in Docker on LNX01 so the P3
#         assessment can map existing paths to highly privileged accounts, and print the
#         collection step that is run separately from a domain-joined lab host.
# Where:  LNX01 — Ubuntu Server 24.04, AD-joined, 192.168.10.30 (VLAN 10 SERVERS). Lab only.
# Why:    the assessment needs evidence of the BEFORE and AFTER attack-path state. BloodHound
#         Community Edition is free and open source; the stack is defined in
#         configs/p03-bloodhound-ce-compose.yml.
# Status: designed. Nothing is started by default; the assessment has not been run and no
#         attack-path count has been measured (AGENTS.md rule R2).
# Safety: this script refuses to run anywhere that is not the Halden lab, and refuses to start
#         the stack unless --authorise is passed (AGENTS.md rule R6 — the owner must approve
#         running attack-path tooling). Collection archives are written outside the repository
#         and are never committed.
#
# Usage:
#   ./03-Deploy-BloodHoundCE.sh --authorise [--teardown] [--runtime-dir DIR]
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../configs/p03-bloodhound-ce-compose.yml"
RUNTIME_DIR="${HOME}/.local/share/halden-p3-bloodhound"
ACTION="up"
AUTHORISED="no"

usage() {
  cat <<'EOF'
Usage: 03-Deploy-BloodHoundCE.sh --authorise [options]

  --authorise            confirm the owner authorised this lab assessment (required to start)
  --teardown             stop and remove the BloodHound stack instead of starting it
  --runtime-dir DIR      where the generated .env and collected data live (default
                         ~/.local/share/halden-p3-bloodhound)
  -h | --help            show this help

This is an authorised, isolated-lab exercise only. BloodHound maps paths to privileged
accounts; it must never be pointed at any domain the owner does not own.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --authorise)   AUTHORISED="yes"; shift ;;
    --teardown)    ACTION="down"; shift ;;
    --runtime-dir) RUNTIME_DIR="${2:?--runtime-dir needs a path}"; shift 2 ;;
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

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}" >&2
  exit 1
fi

for tool in docker; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "Required tool missing: ${tool}" >&2; exit 1; }
done
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required (docker compose)." >&2; exit 1; }

if [[ "${ACTION}" == "down" ]]; then
  if [[ -f "${RUNTIME_DIR}/.env" ]]; then
    docker compose -f "${COMPOSE_FILE}" --env-file "${RUNTIME_DIR}/.env" down
    echo "BloodHound stack stopped."
  else
    echo "No runtime environment found at ${RUNTIME_DIR}; nothing to stop."
  fi
  exit 0
fi

if [[ "${AUTHORISED}" != "yes" ]]; then
  echo "Refusing to start BloodHound without --authorise (AGENTS.md rule R6)." >&2
  echo "Confirm with the owner that this authorised lab assessment may proceed." >&2
  exit 1
fi

# --- Generate runtime secrets outside the repository (never committed) ------------------------
mkdir -p "${RUNTIME_DIR}"
ENV_FILE="${RUNTIME_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  umask 077
  {
    echo "# Generated $(date -Iseconds) — lab-only runtime secrets for BloodHound CE."
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 24 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    echo "NEO4J_PASSWORD=$(openssl rand -hex 24 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  } > "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  echo "Generated runtime secrets at ${ENV_FILE} (git-ignored, outside the repo)."
fi

echo "Starting BloodHound CE from ${COMPOSE_FILE} ..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d

cat <<EOF

BloodHound CE is starting. Open http://lnx01.ad.halden.internal:8080 (from inside the lab only)
and complete the first-run administrator setup, which is prompted by the application itself.

Next step — collection (run separately, on a domain-joined lab host, as the owner, authorised):
  .\\SharpHound.exe --collectionmethods All --domain ad.halden.internal --outputdirectory <path>
Then upload the resulting zip in the BloodHound CE UI and run the built-in queries such as
"Shortest paths to Domain Admins" and "Kerberoastable users".

Handle the collection zip and the BloodHound database as sensitive: they describe exactly how the
domain can be attacked. Keep them in evidence/raw (git-ignored) and never publish them raw. The
website and register use a sanitized summary instead (AGENTS.md 4.6).

To stop: ./03-Deploy-BloodHoundCE.sh --teardown
EOF

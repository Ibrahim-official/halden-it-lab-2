#!/usr/bin/env bash
# Phase 4: seed the BookStack documentation hub with shelves and books.
# What: creates the shelves/books from configs/bookstack-structure.json through
#       the BookStack REST API, idempotently (existing names are skipped).
# Where: run on OPS01 (or anywhere that can reach BookStack). Needs a BookStack
#        API token in the git-ignored .env.
# Snapshot first: snap-p9-ph4-before (BookStack container data volume).
# Rollback: delete the created shelves/books in the BookStack UI, or restore the
#           bookstack_db volume from the P9 backup.
# Idempotent: a second run reports every shelf/book as already present.
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/halden}"
ENV_FILE="$STACK_DIR/.env"
STRUCTURE="${STRUCTURE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../configs/bookstack-structure.json}"
BOOKSTACK_URL="${BOOKSTACK_URL:-http://127.0.0.1:8080}"

usage() {
  cat <<'USAGE'
Usage: 10-Seed-BookStack.sh [-h]
  Creates the BookStack shelves and books defined in configs/bookstack-structure.json.
  Env: STACK_DIR, STRUCTURE, BOOKSTACK_URL.
  Token: BOOKSTACK_API_TOKEN_ID / BOOKSTACK_API_TOKEN_SECRET in the git-ignored .env.
USAGE
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE." >&2; exit 1; }
[[ -f "$STRUCTURE" ]] || { echo "Missing $STRUCTURE." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (apt-get install -y jq)." >&2; exit 1; }

# Log to stderr so stdout stays clean for captured ids.
log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }
env_get() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- ; }

TOKEN_ID="$(env_get BOOKSTACK_API_TOKEN_ID)"
TOKEN_SECRET="$(env_get BOOKSTACK_API_TOKEN_SECRET)"
[[ -n "$TOKEN_ID" && -n "$TOKEN_SECRET" ]] || { echo "BookStack API token missing from $ENV_FILE." >&2; exit 1; }
AUTH_HEADER="Authorization: Token ${TOKEN_ID}:${TOKEN_SECRET}"

api_get() { curl -fsS -H "$AUTH_HEADER" "$BOOKSTACK_URL/api/$1"; }
api_post() { curl -fsS -H "$AUTH_HEADER" -H 'Content-Type: application/json' -X POST -d "$2" "$BOOKSTACK_URL/api/$1"; }

# Find an object id by exact name, or return empty.
find_id() {
  local endpoint="$1" name="$2"
  api_get "${endpoint}?filter[name]=${name// /%20}" | jq -r --arg n "$name" '.data[] | select(.name==$n) | .id' | head -1
}

create_shelf() {
  local name="$1" id
  id="$(find_id shelves "$name")"
  if [[ -n "$id" ]]; then log "Shelf exists: $name (id $id)"; printf '%s' "$id"; return; fi
  id="$(api_post shelves "$(jq -nc --arg n "$name" '{name:$n, description:"Halden lab documentation shelf (synthetic company)."}')" | jq -r '.id')"
  log "Created shelf: $name (id $id)"; printf '%s' "$id"
}

create_book() {
  local name="$1" shelf_id="$2" id payload
  id="$(find_id books "$name")"
  if [[ -n "$id" ]]; then log "Book exists: $name (id $id)"; return; fi
  payload="$(jq -nc --arg n "$name" --argjson s "$shelf_id" '{name:$n, description:"Owner and review date required on every page."}')"
  id="$(api_post books "$payload" | jq -r '.id')"
  log "Created book: $name (id $id)"
}

main() {
  local count i shelf_name shelf_id
  count="$(jq '.shelves | length' "$STRUCTURE")"
  log "Seeding $count shelves from BookStack structure."
  for i in $(seq 0 $((count - 1))); do
    shelf_name="$(jq -r ".shelves[$i].name" "$STRUCTURE")"
    shelf_id="$(create_shelf "$shelf_name")"
    while read -r book; do
      create_book "$book" "$shelf_id"
    done < <(jq -r ".shelves[$i].books[]" "$STRUCTURE")
  done
  log "BookStack seed complete. Add pages via the page template (Purpose/Scope/Owner/Review)."
}

main

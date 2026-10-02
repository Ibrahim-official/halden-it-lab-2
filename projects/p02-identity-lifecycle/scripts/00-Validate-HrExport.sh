#!/usr/bin/env bash
# Phase 0/1 gate: validate the HR source-of-truth export BEFORE the JML engine is allowed to act.
# Applies to: any Halden lab host (marker /etc/halden-lab) or a host in ad.halden.internal.
# Exit code = number of problems found, so a caller can treat non-zero as "do not run the engine".
set -euo pipefail

DOMAIN="ad.halden.internal"
REQUIRED_COLUMNS=(EmployeeID First Last Department Title Status StartDate EndDate)

usage() {
  cat <<'USAGE'
Usage: 00-Validate-HrExport.sh [--strict] <hr-export.csv ...>
Checks the synthetic HR export before the joiner-mover-leaver engine runs:
  - required columns present
  - EmployeeID present and unique
  - Status is Active or Leaver
  - a Leaver row has an EndDate
  - first.last logon name is unique
  - dates look like YYYY-MM-DD
Lines beginning with '#' are treated as comments and skipped.
Exit code is the number of problems found (0 = clean).
  --strict  also fail when the file has fewer than 2 data rows
USAGE
}

fail() { echo "FAIL: $*" >&2; }

# --- lab guard (AGENTS.md Section 2): refuse to run outside the Halden lab --------------------
[[ "$(hostname -d 2>/dev/null)" == "$DOMAIN" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }

strip_comments() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

check_columns() {
  local header="$1" file="$2" missing=0 column
  for column in "${REQUIRED_COLUMNS[@]}"; do
    if ! printf '%s\n' "$header" | tr ',' '\n' | grep -qx "$column"; then
      fail "$file: missing required column '$column'"
      missing=$((missing + 1))
    fi
  done
  echo "$missing"
}

check_rows() {
  local file="$1"
  local header
  header="$(strip_comments "$file" | head -n 1)"
  local rows errors=0
  rows="$(strip_comments "$file" | tail -n +2)"

  local missing
  missing="$(check_columns "$header" "$file")"
  errors=$((errors + missing))

  local id_col status_col end_col first_col last_col start_col
  id_col="$(col_index "$header" EmployeeID)"
  first_col="$(col_index "$header" First)"
  last_col="$(col_index "$header" Last)"
  status_col="$(col_index "$header" Status)"
  start_col="$(col_index "$header" StartDate)"
  end_col="$(col_index "$header" EndDate)"

  local count=0
  declare -A seen_ids=() seen_names=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    count=$((count + 1))
    local eid first last status start end name
    eid="$(field "$line" "$id_col")"
    first="$(field "$line" "$first_col")"
    last="$(field "$line" "$last_col")"
    status="$(field "$line" "$status_col")"
    start="$(field "$line" "$start_col")"
    end="$(field "$line" "$end_col")"
    name="$(printf '%s.%s' "$first" "$last" | tr '[:upper:]' '[:lower:]')"

    [[ -n "$eid" ]] || { fail "$file line $((count + 1)): empty EmployeeID"; errors=$((errors + 1)); }
    if [[ -n "${seen_ids[$eid]:-}" ]]; then
      fail "$file: duplicate EmployeeID '$eid'"
      errors=$((errors + 1))
    fi
    seen_ids[$eid]=1

    if [[ -n "${seen_names[$name]:-}" ]]; then
      fail "$file: duplicate first.last logon name '$name' (accounts would collide)"
      errors=$((errors + 1))
    fi
    seen_names[$name]=1

    case "$status" in
      Active|Leaver) ;;
      *) fail "$file line $((count + 1)): Status must be Active or Leaver, got '$status'"; errors=$((errors + 1)) ;;
    esac

    if [[ "$status" == "Leaver" && -z "$end" ]]; then
      fail "$file line $((count + 1)): a Leaver row must have an EndDate"
      errors=$((errors + 1))
    fi

    for value in "$start" "$end"; do
      if [[ -n "$value" && ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        fail "$file line $((count + 1)): date '$value' is not YYYY-MM-DD"
        errors=$((errors + 1))
      fi
    done
  done <<< "$rows"

  if [[ "$STRICT" -eq 1 && "$count" -lt 2 ]]; then
    fail "$file: fewer than 2 data rows (a truncated export is the classic bad-file incident)"
    errors=$((errors + 1))
  fi

  echo "$file: ${count} data row(s), ${errors} problem(s)" >&2
  echo "$errors"
}

col_index() {
  local header="$1" wanted="$2" i=1 column
  local -a columns=()
  IFS=',' read -r -a columns <<< "$header"
  for column in "${columns[@]}"; do
    if [[ "$column" == "$wanted" ]]; then echo "$i"; return 0; fi
    i=$((i + 1))
  done
  echo "0"
}

field() {
  local line="$1" index="$2"
  # Fields in this file contain no embedded commas, so a simple split is correct and predictable.
  local i=1 value
  local -a values=()
  IFS=',' read -r -a values <<< "$line"
  for value in "${values[@]}"; do
    if [[ "$i" -eq "$index" ]]; then echo "$value"; return 0; fi
    i=$((i + 1))
  done
  echo ""
}

main() {
  local strict=0 files=()
  while (($# > 0)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --strict) strict=1; shift ;;
      --) shift; break ;;
      -*) fail "unknown option '$1'"; usage; exit 2 ;;
      *) files+=("$1"); shift ;;
    esac
  done
  if ((${#files[@]} == 0)); then usage; exit 2; fi

  local total=0 file
  for file in "${files[@]}"; do
    if [[ ! -r "$file" ]]; then fail "$file: not readable"; total=$((total + 1)); continue; fi
    local errors
    errors="$(STRICT="$strict" check_rows "$file" | tail -n 1)"
    total=$((total + errors))
  done

  if [[ "$total" -eq 0 ]]; then
    echo "HR export validated: clean. The JML engine may run."
  else
    echo "HR export validation found ${total} problem(s). DO NOT run the JML engine." >&2
  fi
  exit "$total"
}

main "$@"

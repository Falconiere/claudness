#!/usr/bin/env bash
# Pre-tool check: Protect quality infrastructure files from edits.
# Data-driven: globs come from $SETTINGS_DIR/protected-files.txt.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

[[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SETTINGS_DIR=$(detect_settings_dir)
LIST_FILE="$SETTINGS_DIR/protected-files.txt"

[ -f "$LIST_FILE" ] || exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
[ -z "$file_path" ] && exit 0

read_list() {
  [ -f "$1" ] || return 0
  grep -vE '^\s*(#|$)' "$1"
}

# glob_match <pattern> <path>
glob_match() {
  local pattern="$1"
  local path="$2"
  # Enable extended globs for ** to match path segments.
  shopt -s extglob globstar 2>/dev/null || true
  # shellcheck disable=SC2053  # intentional glob match on RHS
  [[ "$path" == $pattern ]]
}

matched=""
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  if glob_match "$pattern" "$file_path"; then
    matched="$pattern"
    break
  fi
  # Also check basename for patterns without a path separator.
  if [[ "$pattern" != */* ]]; then
    base=$(basename "$file_path")
    if glob_match "$pattern" "$base"; then
      matched="$pattern"
      break
    fi
  fi
done <<< "$(read_list "$LIST_FILE")"

if [ -n "$matched" ]; then
  jq -n --arg p "$matched" --arg f "$file_path" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("File " + $f + " is protected (matches \"" + $p + "\"). Editing is not allowed unless explicitly requested by the user.")
    }
  }'
  exit 0
fi

exit 0

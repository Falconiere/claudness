#!/usr/bin/env bash
# Post-tool check: Rust quality rules.
# Project-agnostic: no-op outside Rust projects or when cargo is missing.
# Unsafe-block exemptions for FFI crates come from
# $SETTINGS_DIR/rust-unsafe-exemptions.txt.
#
# Inputs (from parent dispatcher post-tools/mod.sh, via `export`):
#   $tool_name     - name of the tool being invoked
#   $input         - raw JSON payload on stdin
#   $PROJECT_ROOT  - repository root

: "${tool_name:=}"
: "${input:=}"
: "${PROJECT_ROOT:=$(pwd)}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

[ "$(detect_rust)" = "rust" ] || exit 0
command -v cargo >/dev/null 2>&1 || exit 0
command -v jq    >/dev/null 2>&1 || exit 0

SETTINGS_DIR=$(detect_settings_dir)
EXEMPTIONS_FILE="$SETTINGS_DIR/rust-unsafe-exemptions.txt"

read_list() {
  [ -f "$1" ] || return 0
  grep -vE '^\s*(#|$)' "$1"
}

fp_from_input=""
if [[ "$tool_name" == "Write" ]]; then
  fp_from_input=$(echo "$input" | jq -r '.tool_input.path // .tool_input.file_path // .tool_input.target_file // empty' 2>/dev/null || echo "")
fi
FILE_PATH="${CLAUDE_FILE_PATHS:-$fp_from_input}"

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ ! "$FILE_PATH" =~ \.rs$ ]] && exit 0

MESSAGES=""
add_error() {
  MESSAGES="${MESSAGES}${1}\n"
}

LINE_COUNT=$(wc -l < "$FILE_PATH" | tr -d ' ')
if [[ "$LINE_COUNT" -gt 500 ]]; then
  add_error "File exceeds 500-line limit: $FILE_PATH ($LINE_COUNT lines) — split into submodules"
fi

if [[ "$FILE_PATH" == */src/* ]] && grep -qE '#\[cfg\(test\)\]' "$FILE_PATH" 2>/dev/null; then
  add_error "Inline #[cfg(test)] in $FILE_PATH — tests must live in tests/ directory"
fi

# Forbidden #[allow(...)] / #![allow(...)] / #[expect(...)] / #![expect(...)]
if grep -qE '#!?\[(allow|expect)\(' "$FILE_PATH" 2>/dev/null; then
  add_error "Forbidden #[allow(...)] / #[expect(...)] in $FILE_PATH — remove it and fix the underlying warning. For unsafe_code, override in Cargo.toml [lints.rust]."
fi

# Forbidden unsafe blocks/functions — except for crates listed in the
# exemptions file (FFI crates, sandboxes, etc).
exempt=0
if [ -f "$EXEMPTIONS_FILE" ]; then
  while IFS= read -r crate; do
    [ -z "$crate" ] && continue
    if [[ "$FILE_PATH" == *"$crate"* ]]; then
      exempt=1
      break
    fi
  done <<< "$(read_list "$EXEMPTIONS_FILE")"
fi
if [ "$exempt" -eq 0 ]; then
  if grep -qE '\bunsafe\b\s*(\{|fn )' "$FILE_PATH" 2>/dev/null; then
    add_error "Forbidden unsafe code in $FILE_PATH — refactor to safe alternative. Add crate to settings/rust-unsafe-exemptions.txt if it legitimately needs unsafe (FFI, sandboxing)."
  fi
fi

LONG_RS_FUNCS=$(awk '
  /^[[:space:]]*(pub )?(async )?fn / { start=NR; name=$0 }
  start && /^[[:space:]]*\}/ {
    len=NR-start
    if (len > 50) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_RS_FUNCS" ]]; then
  add_error "Function too long in $FILE_PATH (>50 lines) — extract helpers."
fi

LONG_IMPL=$(awk '
  /^impl / { start=NR; name=$0 }
  start && /^\}/ {
    len=NR-start
    if (len > 200) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_IMPL" ]]; then
  add_error "Impl block too large in $FILE_PATH (>200 lines) — split into trait impls or modules."
fi

if [[ -n "$MESSAGES" ]]; then
  jq -n --arg ctx "$MESSAGES" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("Quality issue detected:\n" + $ctx)
    }
  }'
fi

exit 0

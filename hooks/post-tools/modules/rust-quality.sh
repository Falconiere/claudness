#!/bin/bash
# Post-tool check: Rust quality rules
# Lightweight file-level checks (fast, no external tool invocations).
# Heavy checks (cargo clippy, nextest) run via explicit quality gate commands.
#
# Inputs (from parent dispatcher post-tools/mod.sh, via `export`):
#   $tool_name     - name of the tool being invoked
#   $input         - raw JSON payload on stdin
#   $PROJECT_ROOT  - repository root

: "${tool_name:=}"
: "${input:=}"
: "${PROJECT_ROOT:=$(pwd)}"

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
  add_error "Forbidden #[allow(...)] / #[expect(...)] in $FILE_PATH — remove it and fix the underlying warning. For unsafe_code, override in Cargo.toml [lints.rust]. See docs/rules/forbidden-syntax-rust.md"
fi

# Forbidden unsafe blocks/functions (FFI crates excluded at workspace lint level)
if [[ "$FILE_PATH" != *yamless-secrets-runtime* && "$FILE_PATH" != *yamless-sandbox* ]]; then
  if grep -qE '\bunsafe\b\s*(\{|fn )' "$FILE_PATH" 2>/dev/null; then
    add_error "Forbidden unsafe code in $FILE_PATH — refactor to safe alternative. See docs/rules/forbidden-syntax-rust.md"
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
  add_error "Function too long in $FILE_PATH (>50 lines) — extract helpers. See docs/rules/simplicity.md"
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
  add_error "Impl block too large in $FILE_PATH (>200 lines) — split into trait impls or modules. See docs/rules/simplicity.md"
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

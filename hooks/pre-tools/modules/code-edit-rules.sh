#!/bin/bash
# Pre-tool check: Remind to read rules before editing code files
# Surfaces relevant rule docs based on file type
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

[[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]] && exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

# Only apply to source code files
case "$file_path" in
  *.rs)
    rules="docs/rules/rust-quality.md + docs/rules/forbidden-syntax-rust.md + docs/rules/simplicity.md"
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.py)
    rules="docs/rules/quality-gates.md + docs/rules/forbidden-syntax-typescript.md + docs/rules/simplicity.md"
    if [[ "$file_path" == */features/* || "$file_path" == */components/* || "$file_path" == */routes/* ]]; then
      rules="${rules} + docs/rules/frontend-organization.md"
    fi
    ;;
  *)
    exit 0
    ;;
esac

jq -n --arg msg "Read relevant rules before editing: ${rules}" --arg file "$file_path" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("File: " + $file + "\n" + $msg)
  }
}'
exit 0

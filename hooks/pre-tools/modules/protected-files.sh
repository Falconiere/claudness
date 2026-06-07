#!/bin/bash
# Pre-tool check: Protect quality infrastructure files from edits
# Blocks editing lint/format configs and quality check code
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

[[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]] && exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

# Lint/format config files
if [[ "$file_path" == *".oxfmtrc.json" || "$file_path" == *".oxlintrc.json" ]]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Editing .oxfmtrc.json and .oxlintrc.json is not allowed unless explicitly requested by the user."
    }
  }'
  exit 0
fi

# Quality check infrastructure (bash CLI)
if [[ "$file_path" == */tools/yamless/cmd/check.sh || "$file_path" == */tools/yamless/lib/checker.sh ]]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Quality check code (tools/yamless/cmd/check.sh, tools/yamless/lib/checker.sh) is protected. Do not weaken quality gates to pass checks — fix the code instead."
    }
  }'
  exit 0
fi

exit 0

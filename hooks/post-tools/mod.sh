#!/bin/bash
# Post-tool-use hook dispatcher
# Runs all scripts in .claude/hooks/post-tools/modules/*.sh sequentially.
# Each script receives $input, $tool_name, and $PROJECT_ROOT as env vars.
#
# Output discipline:
#   - A module that emits `hookSpecificOutput.permissionDecision == "deny"` is
#     authoritative: emit that output immediately and stop dispatch.
#   - Otherwise, every module's advisory `additionalContext` is collected and
#     merged into ONE final JSON object emitted at the end.

input=$(cat 2>/dev/null || echo "{}")
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export PATH="$PROJECT_ROOT/node_modules/.bin:$PATH"

export input tool_name PROJECT_ROOT

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)/modules"

collected_contexts=()

for script in "$HOOK_DIR"/*.sh; do
  [[ ! -f "$script" ]] && continue
  result=$(echo "$input" | bash "$script" 2>/dev/null)
  [[ -z "$result" ]] && continue

  decision=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [[ "$decision" == "deny" ]]; then
    echo "$result"
    exit 0
  fi

  ctx=$(echo "$result" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  [[ -n "$ctx" ]] && collected_contexts+=("$ctx")
done

if [[ ${#collected_contexts[@]} -gt 0 ]]; then
  merged=""
  for c in "${collected_contexts[@]}"; do
    if [[ -z "$merged" ]]; then
      merged="$c"
    else
      merged="${merged}"$'\n\n'"${c}"
    fi
  done
  jq -n --arg ctx "$merged" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $ctx
    }
  }'
fi

exit 0

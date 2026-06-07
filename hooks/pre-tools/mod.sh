#!/bin/bash
# Pre-tool-use hook dispatcher
# Runs all scripts in .claude/hooks/pre-tools/modules/*.sh sequentially.
# Each script receives $input and $tool_name as env vars.
#
# Output discipline:
#   - A module that emits `hookSpecificOutput.permissionDecision == "deny"` is
#     authoritative: emit that output immediately and stop dispatch (security
#     wins; a deny must not be silently suppressed by an advisory).
#   - Otherwise, every module's advisory `additionalContext` is collected and
#     merged into ONE final JSON object emitted at the end.

HOOK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)"
# shellcheck source=../lib/config.sh
. "$HOOK_LIB/config.sh"

if ! claudness_enabled hooks pre-tools; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

export input tool_name

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)/modules"

collected_contexts=()

for script in "$HOOK_DIR"/*.sh; do
  [[ ! -f "$script" ]] && continue
  result=$(echo "$input" | bash "$script" 2>/dev/null)
  [[ -z "$result" ]] && continue

  # Deny short-circuits.
  decision=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [[ "$decision" == "deny" ]]; then
    echo "$result"
    exit 0
  fi

  # Otherwise collect advisory additionalContext.
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
      "hookEventName": "PreToolUse",
      "additionalContext": $ctx
    }
  }'
fi

exit 0

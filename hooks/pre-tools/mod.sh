#!/bin/bash
# Pre-tool-use hook dispatcher
# Runs all scripts in .claude/hooks/pre-tools/modules/*.sh sequentially.
# Each script receives $input and $tool_name as env vars.
# First script that produces output wins (non-empty stdout stops execution).

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

export input tool_name

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)/modules"

for script in "$HOOK_DIR"/*.sh; do
  [[ ! -f "$script" ]] && continue
  result=$(echo "$input" | bash "$script" 2>/dev/null)
  if [[ -n "$result" ]]; then
    echo "$result"
    exit 0
  fi
done

exit 0

#!/bin/bash
# Post-tool-use hook dispatcher
# Runs all scripts in .claude/hooks/post-tools/modules/*.sh sequentially.
# Each script receives $input, $tool_name, and $PROJECT_ROOT as env vars.
# First script that produces output wins (non-empty stdout stops execution).

input=$(cat 2>/dev/null || echo "{}")
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export PATH="$PROJECT_ROOT/node_modules/.bin:$PATH"

export input tool_name PROJECT_ROOT

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

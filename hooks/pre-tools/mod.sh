#!/bin/bash
# Pre-tool-use hook dispatcher (entrypoint).
# Runs all scripts in .claude/hooks/pre-tools/modules/*.sh sequentially.
# Each script receives $input and $tool_name as env vars plus $input on stdin.
#
# Dispatch, decision short-circuit (permissionDecision:"deny"), advisory
# merging, and module exit-code semantics live in lib/dispatch.sh.

HOOK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)"
export CLAUDNESS_LIB_DIR="$HOOK_LIB"
# shellcheck source=../lib/config.sh
. "$HOOK_LIB/config.sh"
# shellcheck source=../lib/dispatch.sh
. "$HOOK_LIB/dispatch.sh"

if ! claudness_enabled hooks pre-tools; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

input=$(cat)
tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || echo "")

export input tool_name

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)/modules"

# Exits 2 if a module hard-blocks via exit code 2 (stderr forwarded).
claudness_dispatch_modules "$HOOK_DIR" "PreToolUse"

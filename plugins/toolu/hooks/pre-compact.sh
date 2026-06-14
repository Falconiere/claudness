#!/bin/bash
# PreCompact hook

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/detect.sh
. "$HOOK_DIR/lib/detect.sh"
# shellcheck source=lib/config.sh
. "$HOOK_DIR/lib/config.sh"

if ! toolu_enabled hooks pre-compact; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

# Consume stdin (Claude Code sends hook input via stdin)
cat > /dev/null 2>&1 || true

case "$(toolu_comemory_state)" in
  available)
    # The wrapper ships in the comemory plugin; its install path differs per
    # machine, so reference the wrapper name, not a path.
    mod_sh="the comemory plugin's comemory.sh"
    reminder=$(cat "$HOOK_DIR/docs/post-compaction.md" 2>/dev/null || echo "Context compacted. Run $mod_sh summary then $mod_sh search \"<topic>\".")
    ;;
  missing)
    reminder="Context compacted. WARN: comemory CLI not installed — memory summary/recall disabled. Continue from in-window context only."
    ;;
  disabled|*)
    reminder="Context compacted. Continue from in-window context only."
    ;;
esac

jq -n --arg reminder "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": $reminder
  }
}'

exit 0

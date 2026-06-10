#!/bin/bash
# PreCompact hook

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/detect.sh
. "$HOOK_DIR/lib/detect.sh"
# shellcheck source=lib/config.sh
. "$HOOK_DIR/lib/config.sh"

if ! claudness_enabled hooks pre-compact; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

# Consume stdin (Claude Code sends hook input via stdin)
cat > /dev/null 2>&1 || true

case "$(claudness_engram_state)" in
  available)
    # Resolve the code-intel wrapper relative to this hook — works from the
    # repo checkout and through the installed plugin's scripts→hooks symlink.
    mod_sh="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)/skills/code-intel/scripts/mod.sh"
    [ -x "$mod_sh" ] || mod_sh="skills/code-intel/scripts/mod.sh"
    reminder=$(cat "$HOOK_DIR/docs/post-compaction.md" 2>/dev/null || echo "Context compacted. Run $mod_sh engram summary then $mod_sh engram context.")
    ;;
  missing)
    reminder="Context compacted. WARN: engram CLI not installed — memory summary/recall disabled. Continue from in-window context only."
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

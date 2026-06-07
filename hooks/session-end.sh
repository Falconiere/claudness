#!/bin/bash
# Stop hook — prompt to save session learnings before exiting.

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/detect.sh
. "$HOOK_DIR/lib/detect.sh"
# shellcheck source=lib/config.sh
. "$HOOK_DIR/lib/config.sh"

if ! claudness_enabled hooks session-end; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

# Consume stdin (Claude Code sends hook input via stdin)
cat > /dev/null 2>&1 || true

case "$(claudness_engram_state)" in
  available)
    save_doc="$HOOK_DIR/docs/vector-helper-save.md"
    save_hint=$(cat "$save_doc" 2>/dev/null || echo "Save reusable learnings via .claude/skills/code-intel/scripts/mod.sh engram save.")
    ctx="Session ending. $save_hint"
    ;;
  missing)
    ctx="Session ending. WARN: engram CLI not installed — session save skipped. Install engram to persist learnings across sessions."
    ;;
  disabled|*)
    ctx="Session ending."
    ;;
esac

jq -n --arg ctx "$ctx" '{
  "stopReason": $ctx
}'

exit 0

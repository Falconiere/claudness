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
    # Resolve the code-intel wrapper relative to this hook — works from the
    # repo checkout and through the installed plugin's scripts→hooks symlink.
    mod_sh="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)/skills/code-intel/scripts/mod.sh"
    [ -x "$mod_sh" ] || mod_sh="skills/code-intel/scripts/mod.sh"
    save_hint=$(cat "$save_doc" 2>/dev/null || echo "Save reusable learnings via $mod_sh engram save.")
    ctx="Session ending. $save_hint"
    ;;
  missing)
    ctx="Session ending. WARN: engram CLI not installed — session save skipped. Install engram to persist learnings across sessions."
    ;;
  disabled|*)
    ctx="Session ending."
    ;;
esac

# Stop hooks have no recognized `stopReason` output field; use
# `systemMessage` (valid for every hook event, shown to the user).
# Do NOT use decision:"block" — that would force an extra model turn
# on every Stop.
jq -n --arg ctx "$ctx" '{
  "systemMessage": $ctx
}'

exit 0

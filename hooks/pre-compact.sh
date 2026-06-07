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

if [ "$(detect_engram)" = "engram" ]; then
  reminder=$(cat "$HOOK_DIR/docs/post-compaction.md" 2>/dev/null || echo "Context compacted. Run .claude/skills/code-intel/scripts/mod.sh engram summary then mod.sh engram context.")
else
  reminder="Context compacted. WARN: engram CLI not installed — memory summary/recall disabled. Continue from in-window context only."
fi

jq -n --arg reminder "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": $reminder
  }
}'

exit 0

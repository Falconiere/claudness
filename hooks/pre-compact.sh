#!/bin/bash
# PreCompact hook

HOOK_DIR="$(dirname "$0")"

# Consume stdin (Claude Code sends hook input via stdin)
cat > /dev/null 2>&1 || true

reminder=$(cat "$HOOK_DIR/docs/post-compaction.md" 2>/dev/null || echo "Context compacted. Run .claude/skills/code-intel/scripts/mod.sh engram summary then mod.sh engram context.")

jq -n --arg reminder "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": $reminder
  }
}'

exit 0

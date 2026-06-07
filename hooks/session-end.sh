#!/bin/bash
# Stop hook — prompt to save session learnings before exiting.

# Consume stdin (Claude Code sends hook input via stdin)
cat > /dev/null 2>&1 || true

save_doc="$(dirname "$0")/docs/vector-helper-save.md"
save_hint=$(cat "$save_doc" 2>/dev/null || echo "Save reusable learnings via .claude/skills/code-intel/scripts/mod.sh engram save.")

jq -n --arg ctx "Session ending. $save_hint" '{
  "stopReason": $ctx
}'

exit 0

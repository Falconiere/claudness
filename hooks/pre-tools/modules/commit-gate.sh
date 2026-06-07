#!/bin/bash
# Pre-commit gate — remind to run detect-changes + save memory
# Triggers on Bash tool when command starts with "git commit"

: "${tool_name:=}"
: "${input:=}"

[[ "$tool_name" != "Bash" ]] && exit 0

command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Only match git commit commands
case "$command" in
  "git commit"*) ;;
  *) exit 0 ;;
esac

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "BEFORE COMMITTING:\n1. Verify diff covers only expected scope (git diff --stat)\n2. Run: .claude/skills/code-intel/scripts/mod.sh engram save \"...\" --type <type>\nSkip only if already done this task."
  }
}'
exit 0

#!/usr/bin/env bash
# Pre-commit gate — validates Conventional Commits prefix and reminds about
# scope verification + memory save before commits.
# Project-agnostic: prefixes come from settings/commit-prefixes.txt; base
# branch is detected via detect_base_branch.

: "${tool_name:=}"
: "${input:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

[[ "$tool_name" != "Bash" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Only match git commit commands
case "$command" in
  "git commit"*) ;;
  *) exit 0 ;;
esac

SETTINGS_DIR=$(detect_settings_dir)
PREFIX_FILE="$SETTINGS_DIR/commit-prefixes.txt"
BASE_BRANCH=$(detect_base_branch)

# read_list is sourced from lib/detect.sh.

# Extract the message from -m "..." if present; else allow (it's editor-driven).
msg=""
if [[ "$command" == *" -m "* ]]; then
  msg=$(printf '%s' "$command" | sed -nE 's/.* -m[[:space:]]+"([^"]*)".*/\1/p')
  if [ -z "$msg" ]; then
    msg=$(printf '%s' "$command" | sed -nE "s/.* -m[[:space:]]+'([^']*)'.*/\\1/p")
  fi
fi

prefixes=$(read_list "$PREFIX_FILE")
if [ -n "$msg" ] && [ -n "$prefixes" ]; then
  # Subject = first line up to first colon/space
  subject_prefix=$(printf '%s' "$msg" | head -1 | sed -nE 's/^([a-z]+)(\(.*\))?:.*/\1/p')
  if [ -n "$subject_prefix" ]; then
    if ! echo "$prefixes" | grep -qFx "$subject_prefix"; then
      jq -n --arg p "$subject_prefix" --arg base "$BASE_BRANCH" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": ("Unknown Conventional Commits prefix: \"" + $p + "\". Allowed prefixes are in settings/commit-prefixes.txt. Base branch: " + $base)
        }
      }'
      exit 0
    fi
  fi
fi

jq -n --arg base "$BASE_BRANCH" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("BEFORE COMMITTING:\n1. Verify diff covers only expected scope (git diff --stat against " + $base + ")\n2. Save memory of significant decisions before committing.\nSkip only if already done this task.")
  }
}'
exit 0

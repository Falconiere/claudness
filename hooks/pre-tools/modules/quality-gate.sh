#!/bin/bash
# Pre-tool check: Quality gate enforcement
# DENIES all non-fix actions when quality gate is failing.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Skip enforcement in git linked worktrees (e.g. .worktrees/<branch>) — quality state is for the main checkout.
git_dir="$(git -C "$project_root" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
common_dir="$(git -C "$project_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
git_dir="${git_dir%/}"
common_dir="${common_dir%/}"
if [[ -n "$git_dir" && -n "$common_dir" && "$git_dir" != "$common_dir" ]]; then
  exit 0
fi

gate_file="$project_root/.claude/tmp/quality-gate-status.json"

[[ ! -f "$gate_file" ]] && exit 0
[[ "$(jq -r '.status // ""' "$gate_file" 2>/dev/null)" != "failing" ]] && exit 0

# Gate is failing — determine if this action is allowed

# Allow quality-fix commands (Bash/Shell)
if [[ "$tool_name" == "Bash" || "$tool_name" == "Shell" ]]; then
  command=$(echo "$input" | jq -r '.tool_input.command // ""')
  cmd_only=$(echo "$command" | sed '/<<['"'"'"]*EOF['"'"'"]*$/,/^EOF$/d')

  # Allow quality check/fix commands (scripts + bun run variants)
  if echo "$cmd_only" | grep -qE '(bun run (check|check:fix|check:duplication|lint:fix|format|build|test)|bun test|vitest|tsc|oxlint|oxfmt|\.\/scripts\/ts-check\.sh)'; then
    exit 0
  fi

  # Allow git commands
  if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)git\s+(status|diff|log|add|commit|branch|stash)'; then
    exit 0
  fi
fi

# Allow Edit/Write on code/config files (to fix violations)
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" || "$tool_name" == "MultiEdit" ]]; then
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')
  if [[ "$file_path" =~ \.(ts|tsx|js|mjs|sh|json)$ ]]; then
    exit 0
  fi
fi

# Allow Read, Grep, Glob (non-destructive)
if [[ "$tool_name" == "Read" || "$tool_name" == "Grep" || "$tool_name" == "Glob" ]]; then
  exit 0
fi

# Deny everything else
reason=$(jq -r '.reason // "Quality gate failing"' "$gate_file" 2>/dev/null || echo "Quality gate failing")
violations=$(jq -r '.violations // ""' "$gate_file" 2>/dev/null || echo "")

jq -n --arg reason "$reason" --arg violations "$violations" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ("BLOCKED: Quality gate failing. Fix violations first.\n" + $reason + "\n" + $violations)
  }
}'
exit 0

#!/bin/bash
# Pre-tool check: Bash/Shell command validation
# Rules:
#   0. Block git push to main/master
#   0b. Block cargo test (use nextest)
#   1. Use bun, not npm/yarn/pnpm/npx
#   2. Never use biome (project uses oxlint + oxfmt)
#   3. Use yamless wrapper scripts for code checks
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

[[ "$tool_name" != "Bash" && "$tool_name" != "Shell" ]] && exit 0

command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Strip heredoc bodies so we only check actual commands, not prose in commit messages etc.
cmd_only=$(echo "$command" | sed '/<<['"'"'"]*EOF['"'"'"]*$/,/^EOF$/d')

# Rule 0: Block git push to main/master
if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)git\s+push(\s|$)'; then
  if echo "$cmd_only" | grep -qE 'git\s+push\s+.*\b(main|master)\b'; then
    jq -n '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "git push to main/master is blocked. Push to development instead."
      }
    }'
    exit 0
  fi
fi

# Rule 0b: Block cargo test — use cargo nextest run instead
if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)cargo\s+test(\s|$)'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Use `cargo nextest run` instead of `cargo test`. nextest provides better output, parallel execution, and is the project standard."
    }
  }'
  exit 0
fi

# Rule 1: Block npm/npx/yarn/pnpm — use bun instead
if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)(npm|npx|yarn|pnpm)\s'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "This project uses bun, not npm/npx/yarn/pnpm. Use `bun` or `bun run <script>` instead."
    }
  }'
  exit 0
fi

# Rule 2: Block biome — this project uses oxlint + oxfmt, NOT biome
if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)(bunx\s+)?biome\s'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "This project does NOT use biome. Use package.json scripts: `bun run lint`, `bun run lint:fix`, `bun run format`, `bun run format:fix`."
    }
  }'
  exit 0
fi

# Rule 3: Enforce yamless wrapper scripts for code checks
if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)(bunx\s+)?(oxlint|oxfmt)\s'; then
  if ! echo "$cmd_only" | grep -qE '(tools/yamless/(check|test|format)\.sh|bun run (ts:check|rust:check|rust:test|lint|format|check-types|build)|yamless\s+check)'; then
    jq -n '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Use yamless wrapper scripts instead of running tools directly. Available: `./tools/yamless/check.sh ts`, `./tools/yamless/check.sh rust`, `./tools/yamless/check.sh all` (static gates), `./tools/yamless/test.sh rust`, `./tools/yamless/test.sh` (tests)."
      }
    }'
    exit 0
  fi
fi

exit 0

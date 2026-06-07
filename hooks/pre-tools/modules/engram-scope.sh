#!/usr/bin/env bash
# Pre-tool check: enforce --project scope on raw `engram` CLI invocations.
#
# Without --project, `engram search` / `save` / `context` mix results across
# every project in the local engram DB — wasted tokens at best, wrong-project
# answers at worst. The `.claude/skills/code-intel/scripts/mod.sh engram
# <subcmd>` wrapper auto-scopes; this module pushes the agent toward that path
# by denying unscoped raw calls.
#
# Subcommands that require scoping: search, save, context, summary, and
# `conflicts list` / `conflicts stats`. Anything else (stats, tui, serve, mcp,
# timeline, get, delete, --help, --version) is intentionally global.
#
# Always allowed: wrapper calls (`mod.sh engram …` adds --project itself),
# and raw calls that already include --project, -p, or ENGRAM_PROJECT=.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload (stdin also delivers it)

: "${tool_name:=}"
: "${input:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

[[ "$tool_name" != "Bash" && "$tool_name" != "Shell" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // ""')
[[ -z "$command" ]] && exit 0

cmd_only=$(printf '%s\n' "$command" | strip_heredocs)

# Skip wrapper calls — the wrapper always scopes.
if echo "$cmd_only" | grep -qE '(^|[[:space:]/])mod\.sh[[:space:]]+engram\b'; then
  exit 0
fi

# Split on shell statement separators so each segment is independent.
# Then inspect each segment for a raw `engram <subcmd>` invocation.
violation=""
while IFS= read -r segment; do
  # Trim leading whitespace + strip leading env-var assignments.
  segment="${segment#"${segment%%[![:space:]]*}"}"
  while [[ "$segment" =~ ^[A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+(.*)$ ]]; do
    env_prefix="${segment%%=*}"
    # ENGRAM_PROJECT=... acts as scope.
    if [[ "$env_prefix" == "ENGRAM_PROJECT" ]]; then
      segment=""
      break
    fi
    segment="${BASH_REMATCH[1]}"
  done
  [[ -z "$segment" ]] && continue

  # Only raw `engram <subcmd>` (not a path containing the literal `engram`).
  if [[ ! "$segment" =~ ^engram[[:space:]]+([a-z][a-zA-Z0-9_-]*) ]]; then
    continue
  fi
  subcmd="${BASH_REMATCH[1]}"

  case "$subcmd" in
    search|save|context|summary)
      requires_scope=1
      ;;
    conflicts)
      if [[ "$segment" =~ ^engram[[:space:]]+conflicts[[:space:]]+(list|stats)([[:space:]]|$) ]]; then
        requires_scope=1
      else
        requires_scope=0
      fi
      ;;
    *)
      requires_scope=0
      ;;
  esac

  [[ "$requires_scope" -eq 0 ]] && continue

  # Already scoped via --project / -p?
  if [[ "$segment" =~ (^|[[:space:]])(--project|-p)([[:space:]]|=) ]]; then
    continue
  fi

  violation="$segment"
  break
done < <(printf '%s\n' "$cmd_only" | tr ';&|' '\n' | sed '/^$/d')

if [[ -n "$violation" ]]; then
  jq -n --arg cmd "$violation" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "engram call missing --project scope:\n  " + $cmd + "\n\n" +
        "Engram stores memories across multiple projects. Without --project, search/save/context leak across projects.\n\n" +
        "Fix one of:\n" +
        "  1. Prefer the wrapper (auto-scopes):\n" +
        "       .claude/skills/code-intel/scripts/mod.sh engram <subcmd> …\n" +
        "  2. Add --project <name> to the raw call:\n" +
        "       engram <subcmd> … --project <project-name>\n" +
        "  3. Set ENGRAM_PROJECT=<name> in the env."
      )
    }
  }'
  exit 0
fi

exit 0

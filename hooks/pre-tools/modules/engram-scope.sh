#!/usr/bin/env bash
# Pre-tool check: enforce --project scope on raw `engram` CLI invocations.
#
# Without --project, `engram search` / `save` / `context` mix results across
# every project in the local engram DB — wasted tokens at best, wrong-project
# answers at worst. The `skills/code-intel/scripts/mod.sh engram <subcmd>`
# wrapper (resolved relative to this module, so it works both in-repo and
# through the installed plugin's scripts→hooks symlink) auto-scopes; this
# module pushes the agent toward that path by denying unscoped raw calls.
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

# Split on shell statement separators (;, &&, ||) — but ONLY when they are
# unquoted. A naive `tr ';&|' '\n'` would split `engram save "title; body"`
# inside the quoted argument, falsely denying a legitimate call. Use python3
# to walk the command character-by-character respecting single/double quotes
# and backslash escapes; fall back to the naive split if python3 is missing.
split_statements() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY' 2>/dev/null
import sys
s = sys.argv[1]
segments, buf = [], []
i, n = 0, len(s)
quote = None  # current quote char or None
while i < n:
    c = s[i]
    if quote:
        buf.append(c)
        if c == '\\' and i + 1 < n:
            buf.append(s[i + 1]); i += 2; continue
        if c == quote: quote = None
        i += 1; continue
    if c in ("'", '"'):
        quote = c; buf.append(c); i += 1; continue
    if c == '\\' and i + 1 < n:
        buf.append(c); buf.append(s[i + 1]); i += 2; continue
    # Unquoted separator?
    if c == ';':
        segments.append(''.join(buf)); buf = []; i += 1; continue
    if c in ('&', '|') and i + 1 < n and s[i + 1] == c:
        segments.append(''.join(buf)); buf = []; i += 2; continue
    buf.append(c); i += 1
if buf: segments.append(''.join(buf))
for seg in segments:
    seg = seg.strip()
    if seg: print(seg)
PY
    return
  fi
  # Fallback: naive split. Accepts the quoted-string false-positive risk only
  # when python3 is unavailable.
  printf '%s\n' "$1" | tr ';&|' '\n' | sed '/^$/d'
}

# Then inspect each segment for a raw `engram <subcmd>` invocation.
violation=""
while IFS= read -r segment; do
  # Trim leading whitespace + strip leading env-var assignments.
  segment="${segment#"${segment%%[![:space:]]*}"}"
  # The value may be a single/double-quoted string (which can contain
  # whitespace) OR a run of non-space chars. Matching only the latter would
  # stop at the first space inside a quoted value (MY_VAR="foo bar"), leaving
  # the tail (bar" engram save) as the segment and letting an unscoped raw
  # engram call slip past the ^engram check below. The value alternation is
  # capture group 1, so the trailing REST is group 2.
  #
  # The regex is built in a variable (with \047 = single quote) so the literal
  # single-quote of the quoted-value alternation never sits inside [[ ]] — an
  # embedded ' there desyncs shellcheck's parser.
  _env_re=$'^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|\047[^\047]*\047|[^[:space:]]+)[[:space:]]+(.*)$'
  while [[ "$segment" =~ $_env_re ]]; do
    env_prefix="${segment%%=*}"
    # ENGRAM_PROJECT=... acts as scope.
    if [[ "$env_prefix" == "ENGRAM_PROJECT" ]]; then
      segment=""
      break
    fi
    # :- guard: defensive — if the capture group is somehow unset (regex
    # engine quirk), drop the segment instead of erroring under `set -u`.
    segment="${BASH_REMATCH[2]:-}"
  done
  [[ -z "$segment" ]] && continue

  # Only raw `engram <subcmd>` (not a path containing the literal `engram`).
  if [[ ! "$segment" =~ ^engram[[:space:]]+([a-z][a-zA-Z0-9_-]*) ]]; then
    continue
  fi
  subcmd="${BASH_REMATCH[1]:-}"
  [[ -z "$subcmd" ]] && continue

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
done < <(split_statements "$cmd_only")

if [[ -n "$violation" ]]; then
  # Resolve the auto-scoping wrapper relative to this module's location —
  # works from the repo checkout and through the plugin's scripts→hooks
  # symlink. Fall back to the repo-relative path if resolution fails.
  wrapper_root=$(cd "${BASH_SOURCE%/*}/../../.." 2>/dev/null && pwd)
  wrapper="${wrapper_root:+$wrapper_root/}skills/code-intel/scripts/mod.sh"
  [[ -x "$wrapper" ]] || wrapper="skills/code-intel/scripts/mod.sh"
  jq -n --arg cmd "$violation" --arg wrapper "$wrapper" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "engram call missing --project scope:\n  " + $cmd + "\n\n" +
        "Engram stores memories across multiple projects. Without --project, search/save/context leak across projects.\n\n" +
        "Fix one of:\n" +
        "  1. Prefer the wrapper (auto-scopes):\n" +
        "       " + $wrapper + " engram <subcmd> …\n" +
        "  2. Add --project <name> to the raw call:\n" +
        "       engram <subcmd> … --project <project-name>\n" +
        "  3. Set ENGRAM_PROJECT=<name> in the env."
      )
    }
  }'
  exit 0
fi

exit 0

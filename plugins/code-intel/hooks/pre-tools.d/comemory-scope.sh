#!/usr/bin/env bash
# Pre-tool check: enforce --repo scope on raw `comemory` CLI invocations.
#
# Without --repo, `comemory search` / `save` / `context` mix results across
# every repo in the local comemory store — wasted tokens at best, wrong-repo
# answers at worst. The `skills/code-intel/scripts/mod.sh comemory <subcmd>`
# wrapper (resolved relative to this module — skills/ is a sibling of hooks/
# inside the plugin root, in-repo and installed alike) auto-scopes; this
# module pushes the agent toward that path by denying unscoped raw calls.
#
# Subcommands that require scoping: search, save, context. Anything else
# (list, doctor, stats, tui, serve, --help, --version) is intentionally global.
#
# Always allowed: wrapper calls (`mod.sh comemory …` adds --repo itself), and
# raw calls that already include --repo. comemory has no `-p` short flag and no
# repo env var, so --repo is the only scope signal.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload (stdin also delivers it)

: "${tool_name:=}"
: "${input:=}"

# Core lib comes from the claudness dispatcher via CLAUDNESS_LIB_DIR (set by
# plugins/claudness/hooks/pre-tools/mod.sh before registry dispatch). Outside
# that pipeline there is no relative path to it — fail SOFT: this module is
# an enforcement extra and must never break tool calls by erroring.
[ -n "${CLAUDNESS_LIB_DIR:-}" ] && [ -f "$CLAUDNESS_LIB_DIR/detect.sh" ] || exit 0
# shellcheck source=../../../claudness/hooks/lib/detect.sh
. "$CLAUDNESS_LIB_DIR/detect.sh"

[[ "$tool_name" != "Bash" && "$tool_name" != "Shell" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // ""')
[[ -z "$command" ]] && exit 0

cmd_only=$(printf '%s\n' "$command" | strip_heredocs)

# Skip wrapper calls — the wrapper always scopes.
if echo "$cmd_only" | grep -qE '(^|[[:space:]/])mod\.sh[[:space:]]+comemory\b'; then
  exit 0
fi

# Split on shell statement separators (;, &&, ||) — but ONLY when they are
# unquoted. A naive `tr ';&|' '\n'` would split `comemory save "title; body"`
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

# Then inspect each segment for a raw `comemory <subcmd>` invocation.
violation=""
while IFS= read -r segment; do
  # Trim leading whitespace + strip leading env-var assignments.
  segment="${segment#"${segment%%[![:space:]]*}"}"
  # The value may be a single/double-quoted string (which can contain
  # whitespace) OR a run of non-space chars. Matching only the latter would
  # stop at the first space inside a quoted value (MY_VAR="foo bar"), leaving
  # the tail (bar" comemory save) as the segment and letting an unscoped raw
  # comemory call slip past the ^comemory check below. The value alternation
  # is wrapped in a group, so the trailing REST is BASH_REMATCH[2].
  #
  # comemory has no repo env var, so an env prefix is never scope — it is just
  # stripped so the bare `comemory <subcmd>` underneath is inspected.
  #
  # The regex is built in a variable (with \047 = single quote) so the literal
  # single-quote of the quoted-value alternation never sits inside [[ ]] — an
  # embedded ' there desyncs shellcheck's parser.
  _env_re=$'^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|\047[^\047]*\047|[^[:space:]]+)[[:space:]]+(.*)$'
  while [[ "$segment" =~ $_env_re ]]; do
    # :- guard: defensive — if the capture group is somehow unset (regex
    # engine quirk), drop the segment instead of erroring under `set -u`.
    segment="${BASH_REMATCH[2]:-}"
  done
  [[ -z "$segment" ]] && continue

  # Only raw `comemory <subcmd>` (not a path containing the literal `comemory`).
  if [[ ! "$segment" =~ ^comemory[[:space:]]+([a-z][a-zA-Z0-9_-]*) ]]; then
    continue
  fi
  subcmd="${BASH_REMATCH[1]:-}"
  [[ -z "$subcmd" ]] && continue

  # Only search/save/context require scoping; everything else is global.
  case "$subcmd" in
    search|save|context) ;;
    *) continue ;;
  esac

  # Already scoped via --repo? (comemory has no -p short flag and no repo env.)
  if [[ "$segment" =~ (^|[[:space:]])--repo([[:space:]]|=) ]]; then
    continue
  fi

  violation="$segment"
  break
done < <(split_statements "$cmd_only")

if [[ -n "$violation" ]]; then
  # Resolve the auto-scoping wrapper. Two levels up from this module is the
  # code-intel plugin root — valid in the repo checkout and installed plugin.
  # When run from the runtime-registry COPY (~/.claude/claudness/pre-tools.d/)
  # that path does not exist, so fall back to generic wording: the deny text
  # only needs to point the agent at the wrapper, not at an exact path.
  wrapper_root=$(cd "${BASH_SOURCE%/*}/../.." 2>/dev/null && pwd)
  wrapper="${wrapper_root:+$wrapper_root/}skills/code-intel/scripts/mod.sh"
  [[ -x "$wrapper" ]] || wrapper="the code-intel plugin's skills/code-intel/scripts/mod.sh"
  jq -n --arg cmd "$violation" --arg wrapper "$wrapper" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "comemory call missing --repo scope:\n  " + $cmd + "\n\n" +
        "comemory stores memories across multiple repos. Without --repo, search/save/context leak across repos.\n\n" +
        "Fix one of:\n" +
        "  1. Prefer the wrapper (auto-scopes):\n" +
        "       " + $wrapper + " comemory <subcmd> …\n" +
        "  2. Add --repo <name> to the raw call:\n" +
        "       comemory <subcmd> … --repo <name>"
      )
    }
  }'
  exit 0
fi

exit 0

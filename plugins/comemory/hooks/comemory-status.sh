#!/usr/bin/env bash
# SessionStart hook — publish this project's comemory memory count for the statusline.
#
# Counts memories for the MAIN-repo key on each session start (startup/resume/
# clear/compact) and writes a small marker
# the statusline reads to render a [COMEMORY:N] badge. The key is derived from
# git-common-dir so worktrees share the main repo's memory scope (a bare worktree
# toplevel basename would mis-scope to the worktree name and read 0).
#
# Bounded and non-fatal: a missing, slow, or failing comemory never stalls session
# start and simply leaves no marker (the badge is then omitted).
set -u

input="$(cat 2>/dev/null)"   # consume stdin so the hook IPC never stalls
command -v jq       >/dev/null 2>&1 || exit 0
command -v comemory >/dev/null 2>&1 || exit 0

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"

# Main-repo key: basename of the parent of git-common-dir. A relative ".git"
# (ordinary checkout) is absolutized via the cwd first; a linked worktree yields
# an absolute path straight to the main repo's .git.
repo_key() {  # $1 = dir
  local c
  c=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || { printf 'unknown'; return; }
  case "$c" in
    /*) ;;
    *) c=$(cd "$1" 2>/dev/null && cd "$c" 2>/dev/null && pwd) || { printf 'unknown'; return; } ;;
  esac
  basename "$(dirname "$c")"
}

KEY=$(repo_key "$cwd")
[ -n "$KEY" ] && [ "$KEY" != unknown ] || exit 0

# Bound the call if a timeout tool is present; otherwise run unbounded but still
# non-fatal (stock macOS has no `timeout`).
TO=""
command -v timeout  >/dev/null 2>&1 && TO="timeout 5"
command -v gtimeout >/dev/null 2>&1 && TO="gtimeout 5"
count=$($TO comemory list --repo "$KEY" --json 2>/dev/null | jq 'length' 2>/dev/null)
[ -n "$count" ] || exit 0   # comemory absent/slow/failed → no marker

dir="$CFG/comemory-status"
mkdir -p "$dir" 2>/dev/null || exit 0
tmp="$dir/.$KEY.$$.tmp"
printf '{"repo":"%s","count":%s,"updated":"%s"}\n' \
  "$KEY" "$count" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$tmp" 2>/dev/null \
  && mv -f "$tmp" "$dir/$KEY.json" 2>/dev/null
exit 0

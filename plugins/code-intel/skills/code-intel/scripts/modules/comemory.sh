#!/usr/bin/env bash
# comemory CLI wrapper — persistent memory for AI agents
# Defaults to the current project (auto-detected via detect_project_name) and
# scopes every operation to it via comemory's server-side --repo filter.
# Override the repo with MY_CLAUDE_COMEMORY_REPO=<name>.
# Honors COMEMORY_DATA_DIR (passed through to the comemory CLI, which already
# reads it from the environment) for the data root.
set -euo pipefail

# Self-contained project detection — inlined from the claudness core's
# hooks/lib/detect.sh so this plugin has no cross-plugin source path (it may
# be installed without a claudness checkout next to it). detect_project_name
# uses an if-block (not a bare `[ -n ] && basename`) so it exits 0 outside a
# git repo and `set -e` reaches the REPO="unknown" fallback below; the
# core helper matches this contract.
detect_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || true
}
detect_project_name() {
  local root
  root=$(detect_project_root)
  if [ -n "$root" ]; then basename "$root"; fi
}

# No comemory CLI? Graceful no-op so dependent skills don't break.
command -v comemory >/dev/null 2>&1 || exit 0

REPO="${MY_CLAUDE_COMEMORY_REPO:-$(detect_project_name)}"
[ -z "$REPO" ] && REPO="unknown"

subcmd="${1:-}"
shift 2>/dev/null || true

usage() {
  cat <<'USAGE'
Usage: comemory.sh <subcommand> [args...]

Subcommands:
  search <query> [flags]              Search memories (--repo <detected>; --k N to widen)
  save <title> <content> [flags]      Save a memory (--repo <detected>; --kind defaults to note)
  list [flags]                        List memories (--repo <detected>)
  summary <content>                   Save session summary (--kind note --tags session-summary)
  stats                               Data-directory + index health report (comemory doctor)

Pass-through flags: --kind <kind>, --tags <csv>, --quality N, --k N, --json
USAGE
  exit 1
}

case "$subcmd" in
  search)
    query="${1:?search requires a query}"
    shift
    exec comemory search "$query" --repo "$REPO" "$@"
    ;;
  save)
    title="${1:?save requires a title}"
    content="${2:?save requires content}"
    shift 2
    exec comemory save "$(printf '%s\n\n%s' "$title" "$content")" --repo "$REPO" "$@"
    ;;
  list)
    exec comemory list --repo "$REPO" "$@"
    ;;
  summary)
    content="${1:?summary requires content}"
    shift
    exec comemory save "$(printf '%s\n\n%s' "Session summary" "$content")" --kind note --tags session-summary --repo "$REPO" "$@"
    ;;
  stats)
    exec comemory doctor "$@"
    ;;
  *)
    usage
    ;;
esac

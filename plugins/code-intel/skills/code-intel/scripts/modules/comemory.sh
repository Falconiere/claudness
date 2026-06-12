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

Memory (repo-scoped — --repo auto-injected):
  search <query> [flags]              Search memories (--k N to widen; --kind to filter)
  save <title> <content> [flags]      Save a memory (--kind defaults to note)
  list [flags]                        List memories
  summary <content>                   Save a session summary (tags: session-summary; yields to caller --tags)

Code intelligence (repo-scoped — --repo auto-injected):
  search-code <query> [flags]         Lexical code search (--lang, --k). NOTE: semantic ranking
                                      needs an embedder comemory does not ship; without one this
                                      is FTS/BM25 only — prefer ast-grep for structural queries.
  index-code --path <dir> [flags]     Index a repo's code symbols (lexical). --path required.
  graph [flags]                       Code relationship graph (--rel imports|co-changed|all,
                                      --format json|dot|html, --min-weight N)

Retrieval-quality loop (GLOBAL — no --repo; local, no LLM/API):
  feedback <query_id> [flags]         Record recall relevance (--used/--irrelevant <csv ids>)
  mine [--apply]                      Mine query-expansion pairs from the retrieval log
  tune [--apply]                      Grid-search ranking blend weights against a golden set
  eval [flags]                        Score recall@k + MRR (--golden <file>, --k N)
  prune [--apply]                     Soft-delete low-value memories + orphan edges
  gc                                  Hard-delete trashed entries + stale telemetry
  rebuild                             Rebuild the SQLite mirror from markdown source of truth
  maintain                            Autonomous upkeep: mine --apply + prune --apply + gc
  stats                               Data-directory + index health report (comemory doctor)

Pass-through flags: --kind <kind>, --tags <csv>, --quality N, --k N, --lang <lang>, --json
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
    body="$(printf '%s\n\n%s' "Session summary" "$content")"
    # Default the session-summary tag, but yield to a caller-supplied --tags:
    # comemory/clap rejects a duplicate single-value flag. --kind is left to
    # comemory's own default (note) so a caller may override it via "$@".
    case " $* " in
      *" --tags "*|*" --tags="*)
        exec comemory save "$body" --repo "$REPO" "$@" ;;
      *)
        exec comemory save "$body" --tags session-summary --repo "$REPO" "$@" ;;
    esac
    ;;
  stats)
    exec comemory doctor "$@"
    ;;

  # ── Code intelligence (repo-scoped) ──────────────────────────────────
  # Lexical only without an embedder; comemory ships none. ast-grep remains
  # first choice for structural queries — see SKILL.md.
  search-code)
    query="${1:?search-code requires a query}"
    shift
    exec comemory search-code "$query" --repo "$REPO" "$@"
    ;;
  index-code)
    # --path is required by comemory; caller supplies it. --repo auto-injected.
    exec comemory index-code --repo "$REPO" "$@"
    ;;
  graph)
    exec comemory graph --repo "$REPO" "$@"
    ;;

  # ── Retrieval-quality loop (GLOBAL — comemory has no --repo on these) ──
  # All local, no LLM/API. Safe to run autonomously (see `maintain`).
  feedback)
    query_id="${1:?feedback requires a query_id (from a prior search --json)}"
    shift
    exec comemory feedback "$query_id" "$@"
    ;;
  mine|tune|eval|prune|gc|rebuild)
    exec comemory "$subcmd" "$@"
    ;;
  maintain)
    # Autonomous upkeep bundle. Each step is best-effort and non-fatal so a
    # failure in one never blocks the others (or a Stop hook calling this).
    comemory mine --apply >/dev/null 2>&1 || true
    comemory prune --apply >/dev/null 2>&1 || true
    comemory gc >/dev/null 2>&1 || true
    ;;

  *)
    usage
    ;;
esac

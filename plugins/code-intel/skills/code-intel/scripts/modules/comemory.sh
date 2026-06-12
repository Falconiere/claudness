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

# No comemory CLI? Graceful no-op so dependent skills don't break — but warn on
# stderr first so the agent SEES that this operation (e.g. a save) was dropped,
# not silently swallowed mid-session.
if ! command -v comemory >/dev/null 2>&1; then
  printf 'comemory.sh: comemory CLI not installed — "%s" skipped (no-op). Install comemory to persist/recall.\n' "${1:-<subcommand>}" >&2
  exit 0
fi

REPO="${MY_CLAUDE_COMEMORY_REPO:-$(detect_project_name)}"
if [ -z "$REPO" ]; then
  REPO="unknown"
  # Visibility: outside a git repo with MY_CLAUDE_COMEMORY_REPO unset, every
  # memory lands in the shared "unknown" pool, silently co-mingling across
  # repo-less runs. Warn once so the contamination is not invisible.
  printf 'comemory.sh: no git repo and MY_CLAUDE_COMEMORY_REPO unset — scoping to "unknown" (set MY_CLAUDE_COMEMORY_REPO to isolate)\n' >&2
fi
# A flag-like repo value (leading '-') would be parsed by comemory/clap as a
# flag rather than the --repo argument. Refuse it — fall back to "unknown".
case "$REPO" in
  -*)
    printf 'comemory.sh: ignoring flag-like repo name "%s" — scoping to "unknown"\n' "$REPO" >&2
    REPO="unknown" ;;
esac

# Inject `--repo "$REPO"` UNLESS the caller already passed --repo: a second
# --repo would clap-collide on a duplicate single-value flag (the same hazard
# the `summary` verb guards for --tags). Sets the REPO_ARGS array; expand it
# set-u-safe with ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} (empty-array-safe on bash 3.2).
repo_flag() {
  case " $* " in
    *" --repo "*|*" --repo="*) REPO_ARGS=() ;;
    *)                          REPO_ARGS=(--repo "$REPO") ;;
  esac
}

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
  maintain                            Autonomous upkeep: mine --apply + prune --apply + gc.
                                      Each step is bounded by timeout/gtimeout when present; on a
                                      host with neither (stock macOS) a hung comemory can block a
                                      manual call — the session-end hook runs it detached instead.
  stats                               Data-directory + index health report (comemory doctor)

Pass-through flags: --kind <kind>, --tags <csv>, --quality N, --k N, --lang <lang>, --json
USAGE
  exit 1
}

# Positional values (query, save body) are passed AFTER a `--` end-of-options
# marker so a value with a leading `--` (e.g. a title/query that starts with
# "--foo") is parsed as the positional, not mistaken for a flag. comemory/clap
# requires every flag BEFORE the `--`, so the order is: <verb> <flags> -- <value>.
case "$subcmd" in
  search)
    query="${1:?search requires a query}"
    shift
    repo_flag "$@"
    exec comemory search ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@" -- "$query"
    ;;
  save)
    title="${1:?save requires a title}"
    content="${2:?save requires content}"
    shift 2
    repo_flag "$@"
    exec comemory save ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@" -- "$(printf '%s\n\n%s' "$title" "$content")"
    ;;
  list)
    repo_flag "$@"
    exec comemory list ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@"
    ;;
  summary)
    content="${1:?summary requires content}"
    shift
    # Stamp the title with a UTC timestamp so repeated summaries are not
    # title-identical (a fixed "Session summary" title makes comemory's
    # near-duplicate auto-warn fire on every save).
    body="$(printf 'Session summary %s\n\n%s' "$(date -u +%Y-%m-%dT%H:%MZ 2>/dev/null)" "$content")"
    repo_flag "$@"
    # Default the session-summary tag, but yield to a caller-supplied --tags:
    # comemory/clap rejects a duplicate single-value flag. --kind is left to
    # comemory's own default (note) so a caller may override it via "$@".
    case " $* " in
      *" --tags "*|*" --tags="*)
        exec comemory save ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@" -- "$body" ;;
      *)
        exec comemory save --tags session-summary ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@" -- "$body" ;;
    esac
    ;;
  stats)
    # No REPO_ARGS: `doctor` is a global command (data-dir/index health), not
    # repo-scoped — matching the retrieval-loop verbs below. Do not add --repo.
    exec comemory doctor "$@"
    ;;

  # ── Code intelligence (repo-scoped) ──────────────────────────────────
  # Lexical only without an embedder; comemory ships none. ast-grep remains
  # first choice for structural queries — see SKILL.md.
  search-code)
    query="${1:?search-code requires a query}"
    shift
    repo_flag "$@"
    exec comemory search-code ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@" -- "$query"
    ;;
  index-code)
    # --path is required by comemory; caller supplies it. --repo auto-injected
    # unless the caller passed their own.
    repo_flag "$@"
    exec comemory index-code ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@"
    ;;
  graph)
    repo_flag "$@"
    exec comemory graph ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$@"
    ;;

  # ── Retrieval-quality loop (GLOBAL — comemory has no --repo on these) ──
  # All local, no LLM/API. Safe to run autonomously (see `maintain`).
  feedback)
    query_id="${1:?feedback requires a query_id (from a prior search --json)}"
    shift
    exec comemory feedback "$@" -- "$query_id"
    ;;
  mine|tune|eval|prune|gc|rebuild)
    exec comemory "$subcmd" "$@"
    ;;
  maintain)
    # Autonomous upkeep bundle. Each step is best-effort and non-fatal so a
    # failure in one never blocks the others. Each is bounded by timeout/gtimeout
    # when available (matching session-end.sh) so a hung step can't block a
    # manual `mod.sh comemory maintain`; bare on hosts with neither.
    _cm_to=""
    if command -v timeout >/dev/null 2>&1; then _cm_to="timeout 30"
    elif command -v gtimeout >/dev/null 2>&1; then _cm_to="gtimeout 30"; fi
    $_cm_to comemory mine --apply >/dev/null 2>&1 || true
    $_cm_to comemory prune --apply >/dev/null 2>&1 || true
    $_cm_to comemory gc >/dev/null 2>&1 || true
    ;;

  *)
    usage
    ;;
esac

#!/usr/bin/env bash
# stats.sh — entry point for the /stats report. Parses options, scans the
# transcripts (memoized), aggregates, and renders. Read-only except for the
# per-session rollup cache it maintains under $CLAUDE_CONFIG_DIR/stats/.
#
#   stats.sh [--today|--week|--all] [--project P] [--model M] [--session ID]
#            [--this-session] [--since YYYY-MM-DD] [--limit N] [--json] [--rescan]
#
# Cost figures are sticker-price estimates, not a bill.
set -u

# jq is the one hard dependency. Check before touching anything external so the
# missing-jq path stays self-contained (echo is a builtin; no PATH needed).
command -v jq >/dev/null 2>&1 || {
  echo "stats: jq not found — install jq to see usage stats."
  exit 0
}

LIB="$(cd "${0%/*}/lib" && pwd)" || { echo "stats: cannot locate lib dir." >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB/scan.sh"
# shellcheck source=/dev/null
source "$LIB/aggregate.sh"
# shellcheck source=/dev/null
source "$LIB/render.sh"

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

WINDOW=all; SINCE=""; THIS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --today) WINDOW=today ;;
    --week)  WINDOW=week ;;
    --all)   WINDOW=all ;;
    --json)        export STATS_OUTPUT=json ;;
    --rescan)      export STATS_FORCE_RESCAN=1 ;;
    --this-session) THIS=1 ;;
    --project) shift; export STATS_PROJECT="${1:-}" ;;
    --model)   shift; export STATS_MODEL="${1:-}" ;;
    --session) shift; export STATS_SESSION="${1:-}" ;;
    --limit)   shift; export STATS_LIMIT="${1:-10}" ;;
    --since)   shift; SINCE="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "stats: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
export STATS_WINDOW="$WINDOW"

if [ "$THIS" -eq 1 ]; then
  # Current session = newest transcript under this dir's project; always fresh.
  t="$(stats_current_transcript "$PWD")" || {
    echo "stats: no session transcript found for this directory."
    exit 0
  }
  printf '[%s]\n' "$(stats_rollup_session "$t")" | stats_aggregate | stats_render
  exit 0
fi

rolls="$(stats_scan_all)"
if [ -n "$SINCE" ]; then
  # Keep sessions whose most recent active day is on/after --since.
  rolls="$(printf '%s' "$rolls" | jq --arg s "$SINCE" \
    'map(select((([.by_day|keys[]] | max) // "0") >= $s))')"
fi
printf '%s' "$rolls" | stats_aggregate | stats_render

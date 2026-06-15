#!/usr/bin/env bash
# scan.sh — enumerate session transcripts, memoize per-session rollups, resolve
# project identity, and keep the cache honest.
#
# Source of truth is the transcript; usage.sh does the math. This layer adds:
#   - enumeration of <projects>/<slug>/<session>.jsonl (+ its subagents);
#   - a per-session cache at $CFG/stats/sessions/<id>.json, reused only when
#     src_mtime AND schema_version AND pricing_id all match (a pricing change
#     busts stale cost; STATS_FORCE_RESCAN=1 bypasses the cache entirely);
#   - project label/path from the transcript's .cwd, slug fallback when absent;
#   - orphan GC: cache files whose transcript is gone are deleted and never
#     counted (aggregation iterates live transcripts, not cache files).
set -u

STATS_SCHEMA_VERSION=1

# Resolve roots from CLAUDE_CONFIG_DIR so tests (and alternate homes) isolate.
stats_projects_root() { printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"; }
stats_cache_dir()     { printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/stats/sessions"; }

# Portable mtime (epoch seconds). GNU stat FIRST: on Linux `stat -f` means
# filesystem-status and succeeds with non-numeric output, so the BSD form must be
# the fallback (macOS stat rejects -c and falls through to -f). Then 0.
stats_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# cwd → Claude Code project-dir slug (every non-alphanumeric char becomes '-').
stats_cwd_to_slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# Populate the caller's STATS_FILES (transcript + its subagents) and STATS_MTIME
# (max mtime over them). Must be called DIRECTLY, not in $(...) — a command
# substitution subshell would discard the array assignment.
_stats_session_files() {  # $1=transcript ; sets STATS_FILES[] and STATS_MTIME
  local t="$1" base f m
  base="${t%.jsonl}"
  STATS_FILES=("$t"); STATS_MTIME=0
  for f in "$base"/subagents/agent-*.jsonl; do
    [ -f "$f" ] && STATS_FILES+=("$f")
  done
  for f in "${STATS_FILES[@]}"; do m=$(stats_mtime "$f"); [ "$m" -gt "$STATS_MTIME" ] && STATS_MTIME=$m; done
}

# Compute a fresh, enriched rollup for one session (no cache read/write).
stats_rollup_session() {  # $1=transcript -> enriched rollup JSON (compact, one line)
  local t="$1" lib slug session cwd label ppath mt
  local -a STATS_FILES; local STATS_MTIME
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "$lib/usage.sh"
  # shellcheck source=/dev/null
  source "$lib/pricing.sh"
  _stats_session_files "$t"; mt="$STATS_MTIME"
  slug="$(basename "$(dirname "$t")")"
  session="$(basename "$t" .jsonl)"
  local roll; roll="$(stats_usage_rollup "${STATS_FILES[@]}")"
  cwd="$(printf '%s' "$roll" | jq -r '.cwd // empty')"
  if [ -n "$cwd" ]; then label="$(basename "$cwd")"; ppath="$cwd"; else label="${slug#-}"; ppath="$slug"; fi
  printf '%s' "$roll" | jq -c \
    --arg sid "$session" --arg slug "$slug" --arg label "$label" --arg ppath "$ppath" \
    --argjson mt "$mt" --argjson sv "$STATS_SCHEMA_VERSION" --arg pid "$STATS_PRICING_ID" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    { schema_version: $sv, pricing_id: $pid, session_id: $sid,
      project: $label, project_path: $ppath, project_slug: $slug,
      src_mtime: $mt, scanned_at: $now } + .'
}

# Reuse the cache when fresh, else recompute and write it atomically.
stats_session_rollup() {  # $1=transcript -> enriched rollup JSON
  local t="$1" session cdir cache mt cmt csv cpid roll tmp
  local -a STATS_FILES; local STATS_MTIME
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pricing.sh"
  session="$(basename "$t" .jsonl)"
  cdir="$(stats_cache_dir)"; cache="$cdir/$session.json"
  _stats_session_files "$t"; mt="$STATS_MTIME"
  if [ "${STATS_FORCE_RESCAN:-0}" != "1" ] && [ -f "$cache" ]; then
    IFS=' ' read -r cmt csv cpid < <(jq -r '"\(.src_mtime) \(.schema_version) \(.pricing_id)"' "$cache" 2>/dev/null)
    if [ "$cmt" = "$mt" ] && [ "$csv" = "$STATS_SCHEMA_VERSION" ] && [ "$cpid" = "$STATS_PRICING_ID" ]; then
      cat "$cache"; return 0
    fi
  fi
  roll="$(stats_rollup_session "$t")"
  [ -n "$roll" ] || return 0
  mkdir -p "$cdir" 2>/dev/null || true
  tmp="$cdir/.$session.$$.tmp"
  printf '%s\n' "$roll" >"$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null
  printf '%s\n' "$roll"
}

# Delete cache files whose session is not in the live-id list ($@).
stats_gc_orphans() {  # $@=live session ids
  local cdir cf id live=" $* "
  cdir="$(stats_cache_dir)"; [ -d "$cdir" ] || return 0
  for cf in "$cdir"/*.json; do
    [ -f "$cf" ] || continue
    id="$(basename "$cf" .json)"
    case "$live" in *" $id "*) : ;; *) rm -f "$cf" 2>/dev/null ;; esac
  done
}

# Enumerate every session, emit a JSON array of enriched rollups, GC orphans.
stats_scan_all() {
  local root t; root="$(stats_projects_root)"
  local -a transcripts=() ids=()
  for t in "$root"/*/*.jsonl; do [ -f "$t" ] && transcripts+=("$t"); done
  for t in "${transcripts[@]+"${transcripts[@]}"}"; do ids+=("$(basename "$t" .jsonl)"); done
  { for t in "${transcripts[@]+"${transcripts[@]}"}"; do stats_session_rollup "$t"; done; } | jq -s '.'
  stats_gc_orphans "${ids[@]+"${ids[@]}"}"
}

# Newest transcript directly under the project dir for a cwd (the "current"
# session). Always rolled up fresh by the caller — never the cache.
stats_current_transcript() {  # $1=cwd -> transcript path (or non-zero)
  local cwd="$1" root slug dir f m best=0 newest=""
  root="$(stats_projects_root)"; slug="$(stats_cwd_to_slug "$cwd")"; dir="$root/$slug"
  [ -d "$dir" ] || return 1
  for f in "$dir"/*.jsonl; do
    [ -f "$f" ] || continue
    m=$(stats_mtime "$f"); [ "$m" -ge "$best" ] && { best=$m; newest="$f"; }
  done
  [ -n "$newest" ] && printf '%s\n' "$newest"
}

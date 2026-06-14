#!/usr/bin/env bash
# Stop hook — accumulate weekly token consumption into a per-(week,session) ledger.
#
# Reads the finished session's transcript plus its subagent transcripts, sums
# input + output + cache_creation tokens (cache_read excluded — it is ~98% of
# usage, billed ~0.1x, and does not pace the rate-limit window) deduped by
# message.id, and buckets each message into the LOCAL-TZ ISO week of its own
# timestamp. Writes one small JSON file per week the session touched. The
# statusline reads these cheaply; nothing here runs on the render hot path.
#
# Idempotent: a re-run recomputes from the full transcript and REPLACES this
# session's per-week files, so the weekly total never double-counts.
set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
# Strip session_id to a safe charset before using it as a path component — it is
# a UUID in practice, but never let an unexpected value traverse out of the dir.
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')

# No transcript or no session id → nothing to record. Non-fatal (Stop must not block).
[ -n "$transcript_path" ] && [ -f "$transcript_path" ] || exit 0
[ -n "$session_id" ] || exit 0

# File list: main transcript + this session's subagent (sidechain) transcripts.
# The [ -f ] guard makes an unexpanded glob harmless on bash 3.2 (no nullglob).
files=("$transcript_path")
for f in "${transcript_path%.jsonl}"/subagents/agent-*.jsonl; do
  [ -f "$f" ] && files+=("$f")
done

# Replace this session's contribution to one week (idempotent; never appends).
write_week_file() {            # $1=week  $2=session_id  $3=tokens
  local dir="$CFG/statusline/usage/$1" tmp
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$2.$$.tmp"
  printf '{"session_id":"%s","week":"%s","tokens":%s,"updated":"%s"}\n' \
    "$2" "$1" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$tmp" 2>/dev/null \
    && mv -f "$tmp" "$dir/$2.json" 2>/dev/null
}

# Dedup by message.id, exclude cache_read, bucket by each message's local ISO week.
# `try ... catch null` + the null filter drop any line with a malformed timestamp
# rather than aborting the whole pass. Assumes Claude Code's `...Z` (UTC) timestamp
# form; a numeric-offset timestamp would not parse and that line would be dropped.
jq -rs '
  [ .[]
    | select(.type == "assistant")
    | select(.message.id != null and .timestamp != null)
    | { id: .message.id,
        week: (try (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strflocaltime("%G-W%V")) catch null),
        t: ( (.message.usage.input_tokens // 0)
           + (.message.usage.output_tokens // 0)
           + (.message.usage.cache_creation_input_tokens // 0) ) } ]
  | map(select(.week != null))
  | group_by(.id) | map(.[0])
  | group_by(.week) | map({ week: .[0].week, tokens: (map(.t) | add) })
  | .[] | "\(.week)\t\(.tokens)"
' "${files[@]}" 2>/dev/null \
| while IFS=$'\t' read -r week toks; do
    [ -n "$week" ] && write_week_file "$week" "$session_id" "$toks"
  done

exit 0

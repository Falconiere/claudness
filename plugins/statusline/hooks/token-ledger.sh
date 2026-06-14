#!/usr/bin/env bash
# Stop hook — accumulate weekly token consumption into a per-(week,session) ledger.
#
# Reads the finished session's transcript plus its subagent transcripts, sums
# input + output + cache_creation tokens (the rate-limit-pacing `tokens` total —
# cache_read excluded, as it is ~98% of usage and billed ~0.1x) deduped by
# message.id, and buckets each message into the LOCAL-TZ ISO week of its own
# timestamp. Writes one small JSON file per week the session touched. The
# statusline reads these cheaply; nothing here runs on the render hot path.
#
# It ALSO records the per-bucket token sums (input / output / cache_read /
# cache_write) and a $-weighted `cost`, so the statusline can surface the true
# cost picture — cache_read dominates volume but is cheap, so a tokens-only view
# is misleading. Cost is priced per message at that message's model rate
# (Opus $5/$25, Sonnet $3/$15, Haiku $1/$5 per Mtok; cache_read 0.1x input;
# cache writes 1.25x for 5-min / 2x for 1-hour TTL, split via the usage block's
# cache_creation.ephemeral_{5m,1h}_input_tokens). Unknown models price at the
# Sonnet tier. Rates are 2026 sticker prices and may drift; treat cost as an
# estimate, not a billing figure.
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
write_week_file() {  # $1=week $2=session $3=tokens $4=input $5=output $6=cache_read $7=cache_write $8=cost
  local dir="$CFG/statusline/usage/$1" tmp
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$2.$$.tmp"
  printf '{"session_id":"%s","week":"%s","tokens":%s,"input":%s,"output":%s,"cache_read":%s,"cache_write":%s,"cost":%s,"updated":"%s"}\n' \
    "$2" "$1" "$3" "$4" "$5" "$6" "$7" "$8" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$tmp" 2>/dev/null \
    && mv -f "$tmp" "$dir/$2.json" 2>/dev/null
}

# Dedup by message.id, price each message at its model rate, bucket by each
# message's local ISO week. `try ... catch null` + the null filter drop any line
# with a malformed timestamp rather than aborting the whole pass. Assumes Claude
# Code's `...Z` (UTC) timestamp form; a numeric-offset timestamp would not parse
# and that line would be dropped.
jq -rs '
  def rates(m):
    if   (m | test("opus"))  then {i: 5, o: 25}
    elif (m | test("haiku")) then {i: 1, o: 5}
    else {i: 3, o: 15} end;          # default: Sonnet tier (also covers unknown models)
  [ .[]
    | select(.type == "assistant")
    | select(.message.id != null and .timestamp != null)
    | rates(.message.model // "") as $r
    | (.message.usage // {}) as $u
    | ($u.input_tokens // 0)               as $inp
    | ($u.output_tokens // 0)              as $outp
    | ($u.cache_read_input_tokens // 0)    as $crd
    | ($u.cache_creation_input_tokens // 0) as $cwr
    | ($u.cache_creation.ephemeral_5m_input_tokens // 0) as $w5
    | ($u.cache_creation.ephemeral_1h_input_tokens // 0) as $w1
    | { id: .message.id,
        week: (try (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strflocaltime("%G-W%V")) catch null),
        t:   ($inp + $outp + $cwr),
        in:  $inp, out: $outp, cr: $crd, cw: $cwr,
        cost: ( ( $inp * $r.i + $outp * $r.o + $crd * $r.i * 0.1
                + (if ($w5 + $w1) > 0 then $w5 * 1.25 * $r.i + $w1 * 2 * $r.i
                                      else $cwr * 1.25 * $r.i end)
                ) / 1000000 ) } ]
  | map(select(.week != null))
  | group_by(.id) | map(.[0])
  | group_by(.week)
  | map({ week:   .[0].week,
          tokens: (map(.t)    | add),
          in:     (map(.in)   | add),
          out:    (map(.out)  | add),
          cr:     (map(.cr)   | add),
          cw:     (map(.cw)   | add),
          cost:   (map(.cost) | add) })
  | .[] | "\(.week)\t\(.tokens)\t\(.in)\t\(.out)\t\(.cr)\t\(.cw)\t\(.cost)"
' "${files[@]}" 2>/dev/null \
| while IFS=$'\t' read -r week toks tin tout tcr tcw tcost; do
    [ -n "$week" ] && write_week_file "$week" "$session_id" "$toks" "$tin" "$tout" "$tcr" "$tcw" "$tcost"
  done

exit 0

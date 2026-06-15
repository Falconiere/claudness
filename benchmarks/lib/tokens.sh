#!/usr/bin/env bash
# tokens.sh — token counting for the deterministic tier, and run-variance stats.
#
# bench_count_tokens implements the spec's "labeled-both" rule: exact counts via
# the Anthropic count_tokens API when ANTHROPIC_API_KEY is set, else a bytes/4
# heuristic. CRITICAL invariant: if the key IS set but the API call fails, we
# ABORT (non-zero) rather than silently downgrading to the heuristic — mixing
# exact and heuristic counts inside one delta would corrupt the comparison.
# Only the deterministic retrieval tier uses this; live tiers read real usage.
set -u

# bench_count_tokens [--model <id>] <text-on-stdin>
#   -> {"tokens":N,"mode":"exact|heuristic","source":"count_tokens|bytes-div-4"}
# Heuristic when no key; exact via API when key set; non-zero abort on API error.
bench_count_tokens() {
  local model="claude-sonnet-4-6"
  while [ $# -gt 0 ]; do
    case "$1" in
      --model) model="${2:-}"; shift 2 ;;
      *) echo "bench_count_tokens: unknown arg: $1" >&2; return 2 ;;
    esac
  done

  local text; text="$(cat)"

  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    local bytes; bytes="$(printf '%s' "$text" | wc -c | tr -d ' ')"
    printf '{"tokens":%d,"mode":"heuristic","source":"bytes-div-4"}\n' "$((bytes / 4))"
    return 0
  fi

  local base body resp tokens
  base="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
  body="$(jq -nc --arg m "$model" --arg c "$text" \
    '{model:$m, messages:[{role:"user", content:$c}]}')" \
    || { echo "bench_count_tokens: failed to build request body" >&2; return 1; }

  resp="$(curl -sS --max-time 30 -X POST "$base/v1/messages/count_tokens" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$body" 2>/dev/null)" \
    || { echo "bench_count_tokens: count_tokens request failed (key set; refusing to downgrade to heuristic)" >&2; return 1; }

  tokens="$(printf '%s' "$resp" | jq -e '.input_tokens' 2>/dev/null)" \
    || { echo "bench_count_tokens: no input_tokens in API response: $resp" >&2; return 1; }

  printf '{"tokens":%d,"mode":"exact","source":"count_tokens"}\n' "$tokens"
}

# bench_stats <newline-separated numbers on stdin> -> {"mean":m,"stddev":s,"n":k}
# Sample standard deviation (n-1); n<=1 reports stddev 0; n==0 reports zeros.
bench_stats() {
  jq -Rs '
    [ split("\n")[] | select(length > 0) | tonumber ] as $xs
    | ($xs | length) as $n
    | if   $n == 0 then {mean: 0, stddev: 0, n: 0}
      elif $n == 1 then {mean: $xs[0], stddev: 0, n: 1}
      else ($xs | add / $n) as $m
        | {mean: $m,
           stddev: ( ($xs | map(. - $m | . * .) | add) / ($n - 1) | sqrt ),
           n: $n}
      end'
}

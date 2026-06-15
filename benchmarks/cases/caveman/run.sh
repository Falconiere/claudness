#!/usr/bin/env bash
# caveman/run.sh — live tier. Direct Anthropic API A/B: for each real prompt, run
# n generations with the FAIR "answer-concisely" system (baseline) vs the pinned
# caveman full-mode system (treatment), and measure the response's real
# usage.output_tokens. Delta is on OUTPUT tokens. Live: needs ANTHROPIC_API_KEY.
# A failed curl or a missing output_tokens DROPS that run (note appended) rather
# than writing a partial; zero survivors on either side aborts nonzero.
set -u

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_dir/../../lib/common.sh"
# shellcheck source=/dev/null
source "$_dir/../../lib/tokens.sh"
# shellcheck source=/dev/null
source "$_dir/../../lib/result.sh"

# bench_caveman_one <system-text> <prompt-text> -> usage.output_tokens on stdout,
# or non-zero on curl failure / missing output_tokens (caller drops the run).
bench_caveman_one() {
  local system="$1" prompt="$2" base body resp tok
  base="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
  body="$(jq -nc \
      --arg m "$BENCH_CAVEMAN_MODEL" --argjson mt "$BENCH_CAVEMAN_MAXTOK" \
      --arg s "$system" --arg p "$prompt" \
      '{model:$m, max_tokens:$mt, system:$s, messages:[{role:"user", content:$p}]}')" \
    || return 1
  resp="$(curl -sS --max-time 60 -X POST "$base/v1/messages" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$body" 2>/dev/null)" \
    || return 1
  tok="$(printf '%s' "$resp" | jq -e '.usage.output_tokens' 2>/dev/null)" || return 1
  printf '%s\n' "$tok"
}

bench_caveman_run() {
  local n=5 prompts="$_dir/prompts"
  BENCH_CAVEMAN_MODEL="claude-sonnet-4-6"
  BENCH_CAVEMAN_MAXTOK=1024
  while [ $# -gt 0 ]; do
    case "$1" in
      --n)          n="${2:-}";                     shift 2 ;;
      --model)      BENCH_CAVEMAN_MODEL="${2:-}";    shift 2 ;;
      --prompts)    prompts="${2:-}";               shift 2 ;;
      --max-tokens) BENCH_CAVEMAN_MAXTOK="${2:-}";   shift 2 ;;
      *) echo "caveman: unknown arg: $1" >&2; return 2 ;;
    esac
  done

  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "caveman: live tier needs ANTHROPIC_API_KEY" >&2
    return 1
  fi
  [ -d "$prompts" ] || { echo "caveman: prompts dir not found: $prompts" >&2; return 1; }

  local base_sys treat_sys
  base_sys="$(cat "$_dir/baseline-system.txt")" \
    || { echo "caveman: cannot read baseline-system.txt" >&2; return 1; }
  treat_sys="$(cat "$_dir/treatment-system.txt")" \
    || { echo "caveman: cannot read treatment-system.txt" >&2; return 1; }

  local base_samples="" treat_samples="" cases='[]' notes=""
  local pfile pid prompt run tok
  local found=0
  for pfile in "$prompts"/*.txt; do
    [ -f "$pfile" ] || continue
    found=1
    pid="$(basename "$pfile" .txt)"
    prompt="$(cat "$pfile")" || { notes="${notes}${pid}:read-failed; "; continue; }

    local p_base_sum=0 p_base_n=0 p_treat_sum=0 p_treat_n=0
    for run in $(seq 1 "$n"); do
      if tok="$(bench_caveman_one "$base_sys" "$prompt")"; then
        base_samples="${base_samples}${tok}"$'\n'
        p_base_sum=$((p_base_sum + tok)); p_base_n=$((p_base_n + 1))
      else
        notes="${notes}${pid}:baseline-run${run}-dropped; "
      fi
      if tok="$(bench_caveman_one "$treat_sys" "$prompt")"; then
        treat_samples="${treat_samples}${tok}"$'\n'
        p_treat_sum=$((p_treat_sum + tok)); p_treat_n=$((p_treat_n + 1))
      else
        notes="${notes}${pid}:treatment-run${run}-dropped; "
      fi
    done

    local p_base_mean=0 p_treat_mean=0
    [ "$p_base_n" -gt 0 ]  && p_base_mean=$((p_base_sum / p_base_n))
    [ "$p_treat_n" -gt 0 ] && p_treat_mean=$((p_treat_sum / p_treat_n))
    cases="$(jq -c --arg id "$pid" --argjson b "$p_base_mean" --argjson t "$p_treat_mean" \
      '. + [{id:$id, baseline_tokens:$b, treatment_tokens:$t}]' <<<"$cases")"
  done

  [ "$found" -eq 1 ] || { echo "caveman: no prompt .txt files in $prompts" >&2; return 1; }

  local base_stats treat_stats n_base n_treat
  base_stats="$(printf '%s' "$base_samples"  | bench_stats)"
  treat_stats="$(printf '%s' "$treat_samples" | bench_stats)"
  n_base="$(jq -r '.n' <<<"$base_stats")"
  n_treat="$(jq -r '.n' <<<"$treat_stats")"
  if [ "$n_base" -eq 0 ] || [ "$n_treat" -eq 0 ]; then
    echo "caveman: zero surviving samples on a side (base=$n_base treat=$n_treat); refusing partial" >&2
    return 1
  fi

  local commit date
  commit="$(git -C "$BENCH_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  date="$(date +%Y-%m-%d)"

  jq -nc \
    --argjson cases "$cases" \
    --argjson bs "$base_stats" --argjson ts "$treat_stats" \
    --arg model "$BENCH_CAVEMAN_MODEL" --arg commit "$commit" --arg date "$date" \
    --arg pid "$STATS_PRICING_ID" --arg notes "$notes" \
    '
    ($bs.mean) as $mb | ($ts.mean) as $mt
    | (($mb | round)) as $rb | (($mt | round)) as $rt
    | (if $mb > 0 then (($mb - $mt) / $mb * 100) | round else 0 end) as $pct
    | (($mb - $mt) | round) as $absT
    | (($ts.stddev) | round) as $sd
    | {mechanism:"caveman", tier:"live", method:"api-ab",
       tokenizer:{mode:"usage", source:"usage"},
       provenance:{model:$model, date:$date, commit:$commit,
                   n_runs:($ts.n), pricing_id:$pid},
       baseline:{label:"answer-concisely",
                 tokens:{input:0, output:$rb, cache_read:0, cache_write:0, total:$rb},
                 cost:null},
       treatment:{label:"caveman",
                  tokens:{input:0, output:$rt, cache_read:0, cache_write:0, total:$rt},
                  cost:null},
       delta:{tokens_pct:$pct, cost_pct:null, abs_tokens:$absT, mean:$rt, stddev:$sd},
       cases:$cases, notes:$notes,
       _modes:["usage","usage"]}' \
    | bench_result_write
}

bench_caveman_run "$@"

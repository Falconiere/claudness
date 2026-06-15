#!/usr/bin/env bash
# retrieval/run.sh — deterministic tier. For each query, measure the full-file
# read (baseline) vs the ast-grep targeted match (treatment) as tokens, and emit
# one retrieval result. No model in the loop: hermetic, CI-safe. A missing/empty
# target is guarded (saved 0 + note) so an absent file never divides by zero.
set -u

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_dir/../../lib/common.sh"
# shellcheck source=/dev/null
source "$_dir/../../lib/tokens.sh"
# shellcheck source=/dev/null
source "$_dir/../../lib/result.sh"

bench_retrieval_run() {
  local queries="$_dir/queries.tsv" corpus="$BENCH_ROOT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --queries) queries="${2:-}"; shift 2 ;;
      --corpus)  corpus="${2:-}";  shift 2 ;;
      *) echo "retrieval: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  [ -f "$queries" ] || { echo "retrieval: queries file not found: $queries" >&2; return 1; }

  local cases='[]' modes='[]' sum_base=0 sum_treat=0 notes=""
  local qid target pattern lang
  while IFS=$'\t' read -r qid target pattern lang; do
    case "$qid" in ''|'#'*) continue ;; esac
    local tfile="$corpus/$target"
    if [ ! -f "$tfile" ] || [ ! -s "$tfile" ]; then
      cases="$(jq -c --arg id "$qid" \
        '. + [{id:$id, baseline_tokens:0, treatment_tokens:0, saved:0, note:"missing-or-empty-target"}]' <<<"$cases")"
      notes="${notes}${qid}:missing-target; "
      continue
    fi

    local base_json treat_json treat_text base_tok treat_tok base_mode treat_mode saved
    base_json="$(bench_count_tokens < "$tfile")" \
      || { echo "retrieval: token count failed (baseline $qid)" >&2; return 1; }
    treat_text="$(ast-grep run --lang "$lang" --pattern "$pattern" "$tfile" 2>/dev/null)"
    treat_json="$(printf '%s' "$treat_text" | bench_count_tokens)" \
      || { echo "retrieval: token count failed (treatment $qid)" >&2; return 1; }

    base_tok="$(jq -r '.tokens' <<<"$base_json")"
    treat_tok="$(jq -r '.tokens' <<<"$treat_json")"
    base_mode="$(jq -r '.mode' <<<"$base_json")"
    treat_mode="$(jq -r '.mode' <<<"$treat_json")"
    sum_base=$((sum_base + base_tok))
    sum_treat=$((sum_treat + treat_tok))
    saved=0
    [ "$base_tok" -gt 0 ] && saved=$(( (base_tok - treat_tok) * 100 / base_tok ))
    cases="$(jq -c --arg id "$qid" --argjson b "$base_tok" --argjson t "$treat_tok" --argjson s "$saved" \
      '. + [{id:$id, baseline_tokens:$b, treatment_tokens:$t, saved:$s}]' <<<"$cases")"
    modes="$(jq -c --arg a "$base_mode" --arg c "$treat_mode" '. + [$a, $c]' <<<"$modes")"
  done < "$queries"

  local mode src pct abs commit date
  mode="$(jq -r 'unique | .[0] // "heuristic"' <<<"$modes")"
  src="bytes-div-4"; [ "$mode" = "exact" ] && src="count_tokens"
  pct=0; [ "$sum_base" -gt 0 ] && pct=$(( (sum_base - sum_treat) * 100 / sum_base ))
  abs=$((sum_base - sum_treat))
  commit="$(git -C "$BENCH_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  date="$(date +%Y-%m-%d)"

  jq -nc \
    --argjson cases "$cases" --argjson modes "$modes" \
    --arg mode "$mode" --arg src "$src" \
    --arg commit "$commit" --arg date "$date" --arg pid "$STATS_PRICING_ID" \
    --argjson sb "$sum_base" --argjson st "$sum_treat" --argjson pct "$pct" --argjson abs "$abs" \
    --arg notes "$notes" \
    '{mechanism:"retrieval", tier:"deterministic", method:"tool-bytes",
      tokenizer:{mode:$mode, source:$src},
      provenance:{model:null, date:$date, commit:$commit, n_runs:1, pricing_id:$pid},
      baseline:{label:"full-read",  tokens:{input:$sb,output:0,cache_read:0,cache_write:0,total:$sb}, cost:null},
      treatment:{label:"ast-grep",  tokens:{input:$st,output:0,cache_read:0,cache_write:0,total:$st}, cost:null},
      delta:{tokens_pct:$pct, cost_pct:null, abs_tokens:$abs, mean:null, stddev:null},
      cases:$cases, notes:$notes, _modes:($modes | unique)}' \
    | bench_result_write
}

bench_retrieval_run "$@"

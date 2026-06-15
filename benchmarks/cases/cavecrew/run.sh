#!/usr/bin/env bash
# cavecrew/run.sh — live headless A/B for the cavecrew mechanism. For each task,
# TREATMENT runs `claude` with the cavecrew/toolu plugins active (it may delegate
# exploration to subagents); BASELINE runs `claude --bare` (no plugins) and
# explores inline. We compare MAIN-THREAD total tokens via stats_usage_rollup over
# the pinned-session transcript (+ its subagent transcripts) — the point of
# subagent isolation is keeping the main thread's context small. A run whose
# `claude` invocation fails, or whose transcript is missing/empty, is DROPPED with
# a note (never written as a bogus sample); if no samples survive we abort nonzero.
set -u

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_dir/../../lib/common.sh"
# shellcheck source=/dev/null
source "$_dir/../../lib/result.sh"
# shellcheck source=/dev/null
source "$_dir/../../lib/tokens.sh"

# Resolve the transcript path Claude Code writes for a pinned (cwd, session-id):
#   <projects-root>/<slug>/<session>.jsonl  with subagents under
#   <projects-root>/<slug>/<session>/subagents/agent-*.jsonl
# slug = cwd with every non-alphanumeric char turned into '-' (mirrors stats).
cavecrew_transcript_path() {  # $1=cwd $2=session-id -> transcript path on stdout
  local cwd="$1" sid="$2" root slug
  root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  slug="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
  printf '%s/%s/%s.jsonl\n' "$root" "$slug" "$sid"
}

# Echo the transcript file followed by any subagent transcripts (one per line).
cavecrew_session_files() {  # $1=transcript -> file list on stdout
  local t="$1" base f
  printf '%s\n' "$t"
  base="${t%.jsonl}"
  for f in "$base"/subagents/agent-*.jsonl; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# Run one `claude` headless invocation, then roll up its main-thread total tokens.
# Prints the total tokens on stdout (and 0 status) on success; non-zero on any
# failure (claude error, or missing/empty transcript) so the caller can drop it.
#   $1=cwd  $2=model  $3=task-text  $4=extra-flag ("" or "--bare")
cavecrew_run_one() {
  local cwd="$1" model="$2" task="$3" extra="$4"
  local sid transcript files total
  sid="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  # Run from $cwd so the transcript slug (derived from cwd) matches where Claude
  # Code actually writes — otherwise the transcript lands under a different slug
  # and every run is silently dropped.
  if [ -n "$extra" ]; then
    ( cd "$cwd" && claude -p "$extra" --output-format json --model "$model" --session-id "$sid" "$task" >/dev/null 2>&1 ) \
      || return 1
  else
    ( cd "$cwd" && claude -p --output-format json --model "$model" --session-id "$sid" "$task" >/dev/null 2>&1 ) \
      || return 1
  fi

  transcript="$(cavecrew_transcript_path "$cwd" "$sid")"
  [ -s "$transcript" ] || return 1

  mapfile -t files < <(cavecrew_session_files "$transcript")
  local roll
  roll="$(stats_usage_rollup "${files[@]}")" || return 1
  [ "$(printf '%s' "$roll" | jq -r '.messages')" -gt 0 ] 2>/dev/null || return 1
  total="$(printf '%s' "$roll" | jq -r '.totals.tokens')"
  [ -n "$total" ] && [ "$total" != "null" ] || return 1
  printf '%s\n' "$total"
}

bench_cavecrew_run() {
  # Parse args BEFORE the CLI gate so an unknown arg is a hard 2 regardless of
  # whether the claude CLI is installed (keeps the contract env-independent).
  local n=5 model="claude-sonnet-4-6" tasks="$_dir/tasks" cwd="$BENCH_ROOT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --n)     n="${2:-}";     shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --tasks) tasks="${2:-}"; shift 2 ;;
      *) echo "cavecrew: unknown arg: $1" >&2; return 2 ;;
    esac
  done

  command -v claude >/dev/null 2>&1 \
    || { echo "cavecrew: live tier needs the claude CLI" >&2; return 1; }
  [ -d "$tasks" ] || { echo "cavecrew: tasks dir not found: $tasks" >&2; return 1; }

  local cases='[]' base_samples="" treat_samples="" notes=""
  local sum_base=0 sum_treat=0 n_pairs=0
  local taskfile

  for taskfile in "$tasks"/*.txt; do
    [ -f "$taskfile" ] || continue
    local id task
    id="$(basename "$taskfile" .txt)"
    task="$(cat "$taskfile")"
    local b_sum=0 t_sum=0 b_n=0 t_n=0 run=1
    while [ "$run" -le "$n" ]; do
      local b t
      if b="$(cavecrew_run_one "$cwd" "$model" "$task" "--bare")"; then
        base_samples="${base_samples}${b}"$'\n'; b_sum=$((b_sum + b)); b_n=$((b_n + 1))
      else
        notes="${notes}${id}#${run}:baseline-dropped; "
      fi
      if t="$(cavecrew_run_one "$cwd" "$model" "$task" "")"; then
        treat_samples="${treat_samples}${t}"$'\n'; t_sum=$((t_sum + t)); t_n=$((t_n + 1))
      else
        notes="${notes}${id}#${run}:treatment-dropped; "
      fi
      if [ -n "${b:-}" ] && [ -n "${t:-}" ]; then
        sum_base=$((sum_base + b)); sum_treat=$((sum_treat + t)); n_pairs=$((n_pairs + 1))
      fi
      run=$((run + 1)); b=""; t=""
    done
    cases="$(jq -c --arg id "$id" --argjson b "$b_sum" --argjson t "$t_sum" \
      --argjson bn "$b_n" --argjson tn "$t_n" \
      '. + [{id:$id, baseline_tokens:$b, treatment_tokens:$t, baseline_runs:$bn, treatment_runs:$tn}]' <<<"$cases")"
  done

  [ "$n_pairs" -gt 0 ] \
    || { echo "cavecrew: no surviving paired samples (all runs dropped); refusing to write" >&2; return 1; }

  local base_stats treat_stats pct abs commit date
  base_stats="$(printf '%s' "$base_samples" | bench_stats)"
  treat_stats="$(printf '%s' "$treat_samples" | bench_stats)"
  pct=0; [ "$sum_base" -gt 0 ] && pct=$(( (sum_base - sum_treat) * 100 / sum_base ))
  abs=$((sum_base - sum_treat))
  commit="$(git -C "$BENCH_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  date="$(date +%Y-%m-%d)"

  jq -nc \
    --argjson cases "$cases" \
    --arg model "$model" --arg commit "$commit" --arg date "$date" --arg pid "$STATS_PRICING_ID" \
    --argjson nr "$n_pairs" \
    --argjson sb "$sum_base" --argjson st "$sum_treat" --argjson pct "$pct" --argjson abs "$abs" \
    --argjson bstats "$base_stats" --argjson tstats "$treat_stats" \
    --arg notes "$notes" \
    '{mechanism:"cavecrew", tier:"live", method:"headless-ab",
      tokenizer:{mode:"usage", source:"usage"},
      provenance:{model:$model, date:$date, commit:$commit, n_runs:$nr, pricing_id:$pid},
      baseline: {label:"inline",   tokens:{input:null,output:null,cache_read:null,cache_write:null,total:$sb}, cost:null},
      treatment:{label:"cavecrew", tokens:{input:null,output:null,cache_read:null,cache_write:null,total:$st}, cost:null},
      delta:{tokens_pct:$pct, cost_pct:null, abs_tokens:$abs, mean:$tstats.mean, stddev:$tstats.stddev},
      baseline_stats:$bstats, treatment_stats:$tstats,
      cases:$cases, notes:$notes, _modes:["usage","usage"]}' \
    | bench_result_write
}

bench_cavecrew_run "$@"

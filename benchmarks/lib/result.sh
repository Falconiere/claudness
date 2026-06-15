#!/usr/bin/env bash
# result.sh — write and validate benchmark result JSON (the one committed shape).
#
# bench_result_write reads a result object on stdin and writes the canonical file
# results/<mechanism>-<tier>-<date>.json. It enforces the never-mix-modes rule:
# the caller passes a transient "_modes" array (one entry per delta side); if any
# differ from each other or from tokenizer.mode, the write is refused. "_modes" is
# stripped before the file is written, so the committed schema stays clean.
# bench_result_validate asserts the required keys are present and non-empty.
set -u

_brlib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_brlib/common.sh"

# bench_result_validate <file> -> 0 if every required key is present and non-empty.
bench_result_validate() {
  local f="${1:-}"
  [ -f "$f" ] || { echo "bench_result: file not found: $f" >&2; return 1; }
  local missing
  missing="$(jq -r '
    . as $doc
    | [ "mechanism","tier","method",
        "tokenizer.mode","tokenizer.source",
        "provenance.date","provenance.commit","provenance.pricing_id","provenance.n_runs",
        "baseline.label","baseline.tokens","treatment.label","treatment.tokens",
        "delta.tokens_pct","delta.abs_tokens" ]
    | [ .[] as $p
        | ($doc | getpath($p | split("."))) as $v
        | select( ($v == null) or (($v | type) == "string" and ($v | length) == 0) )
        | $p ]
    | join(",")' "$f" 2>/dev/null)" \
    || { echo "bench_result: invalid JSON in $f" >&2; return 1; }
  [ -z "$missing" ] || { echo "bench_result: $f missing/empty required keys: $missing" >&2; return 1; }
  jq -e '(.provenance // {}) | has("model")' "$f" >/dev/null 2>&1 \
    || { echo "bench_result: $f missing provenance.model key" >&2; return 1; }
  return 0
}

# bench_result_write <result-json-on-stdin> -> path of the written file on stdout.
bench_result_write() {
  local input; input="$(cat)"
  printf '%s' "$input" | jq -e . >/dev/null 2>&1 \
    || { echo "bench_result: invalid JSON on stdin" >&2; return 1; }

  local modeok
  modeok="$(printf '%s' "$input" | jq -r '
    (._modes // []) as $m
    | if   ($m | length) == 0 then "ok"
      elif ([ $m[], .tokenizer.mode ] | unique | length) == 1 then "ok"
      else "mixed" end')"
  [ "$modeok" = "ok" ] \
    || { echo "bench_result: mixed tokenizer modes in one delta; refusing to write" >&2; return 1; }

  local clean mech tier date out
  clean="$(printf '%s' "$input" | jq 'del(._modes)')"
  mech="$(printf '%s' "$clean" | jq -r '.mechanism // ""')"
  tier="$(printf '%s' "$clean" | jq -r '.tier // ""')"
  date="$(printf '%s' "$clean" | jq -r '.provenance.date // ""')"
  [ -n "$mech" ] && [ -n "$tier" ] && [ -n "$date" ] \
    || { echo "bench_result: result needs mechanism, tier, and provenance.date" >&2; return 1; }

  mkdir -p "$BENCH_RESULTS_DIR"
  out="$BENCH_RESULTS_DIR/${mech}-${tier}-${date}.json"
  printf '%s\n' "$clean" | jq . > "$out" || { echo "bench_result: failed to write $out" >&2; return 1; }
  bench_result_validate "$out" || return 1
  printf '%s\n' "$out"
}

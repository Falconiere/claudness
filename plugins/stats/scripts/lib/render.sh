#!/usr/bin/env bash
# render.sh — present the aggregate object. STATS_OUTPUT=json emits the raw
# aggregate (pretty); otherwise a scannable text digest. Token counts are
# humanized (13.7M / 45k); costs are 2-decimal dollar estimates.
set -u

# 13779513 -> 13.7M, 45000 -> 45k, else the raw integer. Integer-only math so it
# is safe on any input (a non-numeric value renders as 0).
stats_format_tokens() {
  local n="$1"
  [[ "$n" =~ ^[0-9]+$ ]] || { printf '0'; return; }
  if   [ "$n" -ge 1000000 ]; then printf '%d.%dM' "$(( n / 1000000 ))" "$(( (n % 1000000) / 100000 ))"
  elif [ "$n" -ge 1000 ];    then printf '%dk' "$(( n / 1000 ))"
  else printf '%d' "$n"; fi
}

# Read the aggregate JSON (stdin) and print it.
stats_render() {
  local agg; agg="$(cat)"
  if [ "${STATS_OUTPUT:-text}" = "json" ]; then printf '%s\n' "$agg" | jq .; return 0; fi
  # jq emits dot-decimal numbers, but a comma-decimal locale makes `printf '%.2f'`
  # reject "4.2" outright ("invalid number" → $0.00). Pin LC_ALL=C — it overrides
  # an inherited LC_ALL/LC_NUMERIC, which a bare LC_NUMERIC=C would not.
  export LC_ALL=C

  local tok cost hit sess
  IFS=' ' read -r tok cost hit sess < <(printf '%s' "$agg" | jq -r '.totals | "\(.tokens) \(.cost) \(.cache_hit_pct) \(.sessions)"')
  if [ "${sess:-0}" -eq 0 ] 2>/dev/null; then
    echo "stats: no usage recorded yet."
    return 0
  fi

  printf 'Usage — %s tokens · $%.2f · cache %s%% · %s sessions  (cost is an estimate)\n' \
    "$(stats_format_tokens "$tok")" "$cost" "$hit" "$sess"

  # Time windows (absent under a --model filter).
  if [ "$(printf '%s' "$agg" | jq -r '.windows == null')" = "true" ]; then
    printf '\nWindows: n/a under --model filter\n'
  else
    local tt tc wt wc at ac
    IFS=' ' read -r tt tc wt wc at ac < <(printf '%s' "$agg" | jq -r \
      '.windows | "\(.today.tokens) \(.today.cost) \(.week.tokens) \(.week.cost) \(.all.tokens) \(.all.cost)"')
    printf '\n  today     %8s  $%.2f\n'    "$(stats_format_tokens "$tt")" "$tc"
    printf '  this week %8s  $%.2f\n'      "$(stats_format_tokens "$wt")" "$wc"
    printf '  all-time  %8s  $%.2f\n'      "$(stats_format_tokens "$at")" "$ac"
  fi

  _stats_render_table "$agg" 'Projects' '.by_project[] | "\(.tokens)\t\(.cost)\t\(.sessions)\t\(.project)"'
  _stats_render_table "$agg" 'Models'   '.by_model[]   | "\(.tokens)\t\(.cost)\t-\t\(.model)"'
  _stats_render_table "$agg" 'Top sessions' '.top_sessions[] | "\(.tokens)\t\(.cost)\t-\t\(.project) \(.session_id[0:8])"'

  local tools phases gate comem
  tools="$(printf '%s' "$agg"  | jq -r '.activity.tools  | to_entries | map("\(.key):\(.value)") | join(" ") | if .=="" then "-" else . end')"
  phases="$(printf '%s' "$agg" | jq -r '.activity.phases | to_entries | map("\(.key):\(.value)") | join(" ") | if .=="" then "-" else . end')"
  gate="$(printf '%s' "$agg"   | jq -r '.activity.gate')"
  comem="$(printf '%s' "$agg"  | jq -r '.activity.comemory')"
  printf '\nActivity\n  tools:  %s\n  phases: %s\n  gate:   %s   comemory: %s\n' \
    "$tools" "$phases" "$gate" "$comem"
}

# Render one labelled table from a jq row expression of "tokens\tcost\tcount\tname".
_stats_render_table() {  # $1=agg $2=title $3=jq-rows
  local agg="$1" title="$2" expr="$3" tk co cn nm any=0
  while IFS=$'\t' read -r tk co cn nm; do
    [ -n "$tk" ] || continue
    [ "$any" -eq 0 ] && { printf '\n%s\n' "$title"; any=1; }
    if [ "$cn" = "-" ]; then
      printf '  %8s  $%8.2f  %s\n' "$(stats_format_tokens "$tk")" "$co" "$nm"
    else
      printf '  %8s  $%8.2f  %3s sess  %s\n' "$(stats_format_tokens "$tk")" "$co" "$cn" "$nm"
    fi
  done < <(printf '%s' "$agg" | jq -r "$expr")
}

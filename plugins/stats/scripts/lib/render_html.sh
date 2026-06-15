#!/usr/bin/env bash
# render_html.sh — render the aggregate object as a self-contained HTML report by
# filling templates/report.html. Values are substituted with bash literal
# replacement (${tmpl//"{{K}}"/$v}) so paths/specials in the data never get
# reinterpreted (unlike sed); data is HTML-escaped via jq @html. Requires the
# token/cost humanizers from render.sh (stats_format_tokens, stats_money) to be
# sourced — stats.sh sources both. The browser-open side effect is guarded by
# STATS_NO_OPEN=1 (set in tests).
set -u

# Disable bash 5.2+ patsub_replacement so `&` (and `\`) in ${var//pat/repl} values
# are literal, not the matched text. No-op (option unknown) on older bash —
# including bash 5.0/5.1 and macOS /bin/bash 3.2 — where they are already literal.
shopt -u patsub_replacement 2>/dev/null || true

# Absolute path of the report file (under the stats config dir).
stats_html_path() { printf '%s/stats/report.html' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# Substitute {{KEY}} with VALUE in the caller's $tmpl (dynamic scope). With
# patsub_replacement disabled (top of file), & and \ are literal in the
# replacement on every bash version, so arbitrary HTML/data substitutes cleanly.
_stats_apply() {  # $1=KEY $2=VALUE
  tmpl="${tmpl//"{{$1}}"/$2}"
}

# Build one HTML block of <div class="row"> from a jq expression that emits
# "tokens\tcost\tname" lines (name already @html-escaped, rows sorted desc). The
# bar width % is scaled to the section's largest row, computed in bash.
_stats_html_rows() {  # $1=agg $2=jq-rows
  local agg="$1" expr="$2" tk co nm out="" pct
  local -a rows=(); local line max=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    rows+=("$line")
    tk="${line%%$'\t'*}"
    [[ "$tk" =~ ^[0-9]+$ ]] && [ "$tk" -gt "$max" ] && max="$tk"
  done < <(printf '%s' "$agg" | jq -r "$expr")
  [ "${#rows[@]}" -eq 0 ] && return 0
  for line in "${rows[@]}"; do
    IFS=$'\t' read -r tk co nm <<<"$line"
    if [ "$max" -gt 0 ]; then pct=$(( tk * 100 / max )); else pct=0; fi
    out+="    <div class=\"row\"><span class=\"name\">${nm}</span>"
    out+="<span class=\"track\"><span class=\"fill\" style=\"width:${pct}%\"></span></span>"
    out+="<span class=\"tok\">$(stats_format_tokens "$tk")</span>"
    out+="<span class=\"cost\">\$$(stats_money "$co")</span></div>"$'\n'
  done
  printf '%s' "$out"
}

# Build an inline SVG bar chart from the 14-day daily series (a muted note when
# daily is null, i.e. under a --model filter).
_stats_html_spark() {  # $1=agg
  local agg="$1"
  if [ "$(printf '%s' "$agg" | jq -r '.daily == null')" = "true" ]; then
    printf '<p class="muted">Per-day trend is unavailable under a model filter.</p>'
    return 0
  fi
  local -a vals=(); local v max=0 i h x y rects=""
  while IFS= read -r v; do
    vals+=("$v"); [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -gt "$max" ] && max="$v"
  done < <(printf '%s' "$agg" | jq -r '.daily[].tokens')
  for i in "${!vals[@]}"; do
    v="${vals[$i]}"; [[ "$v" =~ ^[0-9]+$ ]] || v=0
    if [ "$max" -gt 0 ]; then h=$(( v * 46 / max )); else h=0; fi
    [ "$h" -lt 1 ] && h=1
    x=$(( i * 20 )); y=$(( 48 - h ))
    rects+="<rect x=\"$x\" y=\"$y\" width=\"16\" height=\"$h\" rx=\"2\"></rect>"
  done
  printf '<svg class="spark" viewBox="0 0 280 48" preserveAspectRatio="none" role="img" aria-label="14-day token trend">%s</svg>' "$rects"
}

# Open the report in the default browser unless suppressed. Never fatal.
_stats_open_html() {  # $1=path
  [ "${STATS_NO_OPEN:-0}" = "1" ] && return 0
  if   command -v open     >/dev/null 2>&1; then open "$1"     >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 || true
  fi
}

# stats_render_html < aggregate.json -> writes the report, prints its path.
stats_render_html() {
  local agg; agg="$(cat)"
  local sess; sess="$(printf '%s' "$agg" | jq -r '.totals.sessions')"
  if [ "${sess:-0}" -eq 0 ] 2>/dev/null; then
    echo "stats: no usage recorded yet."
    return 0
  fi

  local tmpl_path; tmpl_path="${STATS_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/../../templates/report.html}"
  if [ ! -r "$tmpl_path" ]; then
    echo "stats: HTML template not found at $tmpl_path" >&2
    return 1
  fi
  local tmpl; tmpl="$(cat "$tmpl_path")"

  local gen tok cost hit today week all
  IFS=$'\t' read -r gen tok cost hit today week all < <(printf '%s' "$agg" | jq -r \
    '[ .generated_at, (.totals.tokens|tostring), (.totals.cost|tostring), (.totals.cache_hit_pct|tostring),
       ((.windows.today.tokens // 0)|tostring), ((.windows.week.tokens // 0)|tostring), ((.windows.all.tokens // 0)|tostring) ] | @tsv')

  local tools phases gate comem
  tools="$(printf '%s' "$agg"  | jq -r '.activity.tools  | to_entries | map("\(.key):\(.value)") | join(" ") | if .=="" then "—" else . end | @html')"
  phases="$(printf '%s' "$agg" | jq -r '.activity.phases | to_entries | map("\(.key):\(.value)") | join(" ") | if .=="" then "—" else . end | @html')"
  gate="$(printf '%s' "$agg"   | jq -r '.activity.gate | @html')"
  comem="$(printf '%s' "$agg"  | jq -r '.activity.comemory | tostring')"

  local prows mrows srows spark
  prows="$(_stats_html_rows "$agg" '.by_project[]   | "\(.tokens)\t\(.cost)\t\(.project|@html)"')"
  mrows="$(_stats_html_rows "$agg" '.by_model[]     | "\(.tokens)\t\(.cost)\t\(.model|@html)"')"
  srows="$(_stats_html_rows "$agg" '.top_sessions[] | "\(.tokens)\t\(.cost)\t\((.project + " " + .session_id[0:8])|@html)"')"
  spark="$(_stats_html_spark "$agg")"

  _stats_apply GENERATED_AT "$gen"
  _stats_apply TOTAL_TOKENS "$(stats_format_tokens "$tok")"
  _stats_apply TOTAL_COST   "$(stats_money "$cost")"
  _stats_apply CACHE_PCT    "$hit"
  _stats_apply SESSIONS     "$sess"
  _stats_apply TODAY_TOKENS "$(stats_format_tokens "$today")"
  _stats_apply WEEK_TOKENS  "$(stats_format_tokens "$week")"
  _stats_apply ALL_TOKENS   "$(stats_format_tokens "$all")"
  _stats_apply SPARKLINE_SVG "$spark"
  _stats_apply PROJECT_ROWS "$prows"
  _stats_apply MODEL_ROWS   "$mrows"
  _stats_apply SESSION_ROWS "$srows"
  _stats_apply TOOLS    " $tools"
  _stats_apply PHASES   " $phases"
  _stats_apply GATE     " $gate"
  _stats_apply COMEMORY " $comem"

  local out; out="$(stats_html_path)"
  mkdir -p "$(dirname "$out")" || { echo "stats: cannot create $(dirname "$out")" >&2; return 1; }
  printf '%s\n' "$tmpl" > "$out" || { echo "stats: cannot write $out" >&2; return 1; }
  printf 'Wrote HTML report: %s\n' "$out"
  _stats_open_html "$out"
}

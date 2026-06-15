#!/usr/bin/env bash
# widgets.sh — terminal UI primitives for the stats dashboard: proportional bar,
# percent gauge, sparkline, and light box-drawing. Glyph-only (no ANSI), so the
# output renders identically wherever the digest is shown. Display-width math is
# locale-independent (counts UTF-8 characters, not bytes) so box/bar alignment
# survives an inherited LC_ALL=C.
set -u

# _stats_repeat CHAR N -> CHAR repeated N times (N<=0 -> empty).
_stats_repeat() {
  local c="$1" n="$2" i out=""
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for ((i = 0; i < n; i++)); do out+="$c"; done
  printf '%s' "$out"
}

# _stats_dwidth STR -> printable character count, independent of the current
# locale. Bytes minus UTF-8 continuation bytes (0x80-0xBF) = character count.
_stats_dwidth() {
  local s="$1" bytes cont
  bytes=$(LC_ALL=C printf '%s' "$s" | LC_ALL=C wc -c)
  cont=$(LC_ALL=C printf '%s' "$s" | LC_ALL=C tr -cd '\200-\277' | LC_ALL=C wc -c)
  printf '%d' $(( bytes - cont ))
}

# _stats_pad STR W -> STR right-padded with spaces to display width W (never
# truncates; returns STR unchanged when already >= W).
_stats_pad() {
  local s="$1" w="$2" dw pad
  dw=$(_stats_dwidth "$s")
  pad=$(( w - dw )); [ "$pad" -lt 0 ] && pad=0
  printf '%s%*s' "$s" "$pad" ""
}

# stats_bar VALUE MAX WIDTH -> WIDTH cells: round(VALUE*WIDTH/MAX) filled (█),
# the rest empty (░). MAX<=0 or non-numeric inputs render an empty bar.
stats_bar() {
  local v="$1" max="$2" w="$3" filled i out=""
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  [[ "$max" =~ ^[0-9]+$ ]] || max=0
  [[ "$w" =~ ^[0-9]+$ ]] || w=0
  if [ "$max" -le 0 ]; then filled=0; else filled=$(( (v * w + max / 2) / max )); fi
  [ "$filled" -gt "$w" ] && filled="$w"
  [ "$filled" -lt 0 ] && filled=0
  for ((i = 0; i < filled; i++)); do out+="█"; done
  for ((i = filled; i < w; i++)); do out+="░"; done
  printf '%s' "$out"
}

# stats_gauge PCT WIDTH -> a bar of WIDTH cells filled to PCT percent.
stats_gauge() { stats_bar "$1" 100 "$2"; }

# stats_sparkline V1 V2 ... -> one of ▁▂▃▄▅▆▇█ per value, scaled to the max in
# the set: idx = round(v*7/max). All-zero (or empty) input -> baseline glyphs.
stats_sparkline() {
  [ "$#" -eq 0 ] && return 0
  local -a vals=("$@")
  local -a g=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  local v max=0 idx out=""
  for v in "${vals[@]}"; do
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    [ "$v" -gt "$max" ] && max="$v"
  done
  for v in "${vals[@]}"; do
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    if [ "$max" -le 0 ]; then idx=0; else idx=$(( (v * 7 + max / 2) / max )); fi
    [ "$idx" -gt 7 ] && idx=7
    out+="${g[idx]}"
  done
  printf '%s' "$out"
}

# stats_box_top INNER TITLE  -> ┌─ TITLE ──…──┐  (INNER chars between corners).
stats_box_top() {
  local inner="$1" head="─ $2 " n
  n=$(( inner - $(_stats_dwidth "$head") )); [ "$n" -lt 0 ] && n=0
  printf '┌%s%s┐' "$head" "$(_stats_repeat ─ "$n")"
}

# stats_box_line INNER CONTENT -> │ CONTENT…padded to INNER… │
stats_box_line() { printf '│%s│' "$(_stats_pad " $2" "$1")"; }

# stats_box_bottom INNER -> └──…──┘
stats_box_bottom() { printf '└%s┘' "$(_stats_repeat ─ "$1")"; }

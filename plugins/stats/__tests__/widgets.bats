#!/usr/bin/env bats
# widgets.sh — pure UI primitives. Deterministic glyph output; display-width math
# must be locale-independent (assert on multibyte glyphs directly).

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib/widgets.sh"
}

@test "stats_bar fills proportionally and rounds" {
  [ "$(stats_bar 5 10 10)" = "█████░░░░░" ]
  [ "$(stats_bar 10 10 10)" = "██████████" ]
  [ "$(stats_bar 0 10 10)" = "░░░░░░░░░░" ]
}

@test "stats_bar guards zero/non-numeric max and clamps overflow" {
  [ "$(stats_bar 5 0 6)" = "░░░░░░" ]
  [ "$(stats_bar 5 x 6)" = "░░░░░░" ]
  [ "$(stats_bar 99 10 6)" = "██████" ]
}

@test "stats_gauge maps a percentage" {
  [ "$(stats_gauge 50 10)" = "█████░░░░░" ]
  [ "$(stats_gauge 100 10)" = "██████████" ]
  [ "$(stats_gauge 0 10)" = "░░░░░░░░░░" ]
}

@test "stats_sparkline maps values to 8 levels by set max" {
  [ "$(stats_sparkline 0 50 100)" = "▁▅█" ]
  [ "$(stats_sparkline 0 0 0)" = "▁▁▁" ]
  [ "$(stats_sparkline 100)" = "█" ]
}

@test "_stats_dwidth counts characters, not bytes" {
  [ "$(_stats_dwidth "abc")" = "3" ]
  [ "$(_stats_dwidth "███")" = "3" ]
  [ "$(_stats_dwidth "─ Usage ")" = "8" ]
  [ "$(_stats_dwidth "")" = "0" ]
}

@test "_stats_pad pads to display width over multibyte content" {
  [ "$(_stats_pad "ab" 5)" = "ab   " ]
  [ "$(_stats_pad "██" 5)" = "██   " ]
  [ "$(_stats_pad "toolong" 3)" = "toolong" ]
}

@test "box helpers draw rules of the right display width" {
  run stats_box_top 20 "Usage"
  [ "${output:0:1}" = "┌" ]
  echo "$output" | grep -q "Usage"
  [ "$(_stats_dwidth "$output")" = "22" ]
  run stats_box_bottom 20
  [ "$(_stats_dwidth "$output")" = "22" ]
  run stats_box_line 20 "hi"
  [ "$(_stats_dwidth "$output")" = "22" ]
}

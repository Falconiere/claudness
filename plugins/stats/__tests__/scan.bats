#!/usr/bin/env bats
# scan.sh — enumeration, cache gating, project identity, orphan GC. Fully
# isolated: CLAUDE_CONFIG_DIR points at a temp tree, so no live data is read
# and the real cache is never touched.

setup() {
  export TZ=UTC
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  source "${BATS_TEST_DIRNAME}/../scripts/lib/scan.sh"
  FX="${BATS_TEST_DIRNAME}/fixtures"
  ROOT="$CLAUDE_CONFIG_DIR/projects"
  SLUG="-Volumes-Projects-toolu-sh"
  mkdir -p "$ROOT/$SLUG"
  cp "$FX/multimodel.jsonl" "$ROOT/$SLUG/sess-mm.jsonl"
  cp "$FX/nocwd.jsonl"      "$ROOT/$SLUG/sess-nc.jsonl"
  T="$ROOT/$SLUG/sess-mm.jsonl"
  CACHE="$CLAUDE_CONFIG_DIR/stats/sessions/sess-mm.json"
}

j() { echo "$output" | jq -r "$1"; }

@test "resolves project label and path from .cwd" {
  run stats_session_rollup "$T"
  [ "$status" -eq 0 ]
  [ "$(j '.project')" = "toolu.sh" ]
  [ "$(j '.project_path')" = "/Volumes/Projects/toolu.sh" ]
  [ "$(j '.schema_version')" = "1" ]
  [ -n "$(j '.pricing_id')" ]
}

@test "falls back to the slug when the transcript has no .cwd" {
  run stats_session_rollup "$ROOT/$SLUG/sess-nc.jsonl"
  [ "$status" -eq 0 ]
  [ "$(j '.project')" = "Volumes-Projects-toolu-sh" ]
  [ "$(j '.project_path')" = "$SLUG" ]
}

@test "writes a cache file and reuses it when src_mtime/schema/pricing match" {
  stats_session_rollup "$T" >/dev/null
  [ -f "$CACHE" ]
  # backdate the cache; a cache HIT must not rewrite it
  touch -t 200001010000 "$CACHE"
  before=$(stats_mtime "$CACHE")
  stats_session_rollup "$T" >/dev/null
  after=$(stats_mtime "$CACHE")
  [ "$before" = "$after" ]              # untouched → served from cache
}

@test "rescan flag bypasses the cache and recomputes" {
  stats_session_rollup "$T" >/dev/null
  touch -t 200001010000 "$CACHE"
  before=$(stats_mtime "$CACHE")
  STATS_FORCE_RESCAN=1 stats_session_rollup "$T" >/dev/null
  after=$(stats_mtime "$CACHE")
  [ "$before" != "$after" ]             # rewritten → recomputed
}

@test "a pricing_id change busts the cache" {
  stats_session_rollup "$T" >/dev/null
  # tamper the cached pricing_id, then backdate so only a content rewrite moves mtime
  tmp="$BATS_TEST_TMPDIR/t.json"
  jq '.pricing_id = "1999-01"' "$CACHE" > "$tmp" && mv "$tmp" "$CACHE"
  touch -t 200001010000 "$CACHE"
  before=$(stats_mtime "$CACHE")
  stats_session_rollup "$T" >/dev/null
  after=$(stats_mtime "$CACHE")
  [ "$before" != "$after" ]             # stale pricing → recomputed
  [ "$(jq -r '.pricing_id' "$CACHE")" != "1999-01" ]
}

@test "scan_all returns one enriched rollup per live session" {
  run stats_scan_all
  [ "$status" -eq 0 ]
  [ "$(j 'length')" = "2" ]
  [ "$(j 'map(.session_id)|sort|join(",")')" = "sess-mm,sess-nc" ]
}

@test "orphan cache (no transcript) is excluded and GC'd" {
  mkdir -p "$CLAUDE_CONFIG_DIR/stats/sessions"
  echo '{"schema_version":1,"pricing_id":"x","session_id":"ghost","src_mtime":1,"project":"gone","totals":{"tokens":999}}' \
    > "$CLAUDE_CONFIG_DIR/stats/sessions/ghost.json"
  run stats_scan_all
  [ "$status" -eq 0 ]
  [ "$(j 'map(.session_id)|index("ghost")')" = "null" ]   # not in the report
  [ ! -f "$CLAUDE_CONFIG_DIR/stats/sessions/ghost.json" ]  # GC'd
}

@test "current_transcript resolves the newest session under a cwd" {
  # sess-nc newer than sess-mm
  touch -t 203001010000 "$ROOT/$SLUG/sess-nc.jsonl"
  run stats_current_transcript "/Volumes/Projects/toolu.sh"
  [ "$status" -eq 0 ]
  [ "$(basename "$output")" = "sess-nc.jsonl" ]
}

@test "empty projects root yields an empty array, not an error" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects"
  run stats_scan_all
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = "[]" ]
}

#!/usr/bin/env bash
# Multi-slot writer for .claude/tmp/quality-gate-status.json.
#
# The gate file used to be single-slot (last writer wins): a TS failure
# followed by a Rust failure overwrote the TS record, and clearing the Rust
# file then re-opened the gate with the TS violation still live. The same
# clobber happened between two files of the SAME language.
#
# Now every failing file owns an entry under `entries` (keyed by file path).
# Top-level fields mirror the most recent failure and aggregate all violations,
# so readers (pre-tool gate, statusline, session-start, user-prompt-submit)
# keep their existing .status / .reason / .violations contract untouched.
#
# A legacy or foreign single-slot failing record (e.g. gate-status-hook's
# command failure) is preserved by seeding it into `entries` under its `file`,
# or "__global__" when it has none. Both jq programs below start with the same
# seed step — keep them in sync.
#
# CONCURRENCY: single-writer by assumption. Both functions read-merge-write via
# `mktemp` + `mv -f`, which has a TOCTOU window — two writers that read the same
# `existing` blob would each rewrite it and the last `mv` would drop the other's
# entry. This is safe today because PostToolUse hooks fire serially per tool
# call (one writer at a time). If a parallel-edit flow is ever added, guard both
# functions with `flock` against a `${gate_file}.lock` sentinel.
#
# Public API:
#   gate_record_failure GATE_FILE FILE SOURCE REASON VIOLATIONS
#   gate_clear_file     GATE_FILE FILE SOURCE

# gate_record_failure GATE_FILE FILE SOURCE REASON VIOLATIONS
# Adds/replaces this file's entry and marks the gate failing. Writes via a
# temp file so a jq failure can never truncate the gate to an unreadable
# (and therefore silently passing) state; on any error it falls back to the
# legacy single-slot write rather than dropping the failure.
gate_record_failure() {
  local gate_file="$1" file="$2" source="$3" reason="$4" violations="$5"
  local existing='{}' now tmp
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [ -f "$gate_file" ]; then
    existing=$(cat "$gate_file" 2>/dev/null) || existing='{}'
    jq -e . <<< "$existing" >/dev/null 2>&1 || existing='{}'
  fi
  tmp=$(mktemp "${gate_file}.XXXXXX" 2>/dev/null) || tmp=""
  if [ -n "$tmp" ] && jq \
      --arg file "$file" --arg source "$source" --arg reason "$reason" \
      --arg violations "$violations" --arg now "$now" '
    (if (.entries? | type) == "object" then .entries
     elif (.status // "") == "failing" then
       { (.file // "__global__"): {
           source: (.source // ""), reason: (.reason // ""),
           violations: (.violations // ""), updatedAt: (.updatedAt // $now) } }
     else {} end) as $prev
    | ($prev + { ($file): {source: $source, reason: $reason,
                           violations: $violations, updatedAt: $now} }) as $entries
    | { status: "failing", reason: $reason, source: $source, file: $file,
        violations: ([$entries | to_entries | sort_by(.value.updatedAt // "", .key)[]
                      | (.value.violations // "")] | join("")),
        entries: $entries, updatedAt: $now }
  ' <<< "$existing" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$gate_file"
  else
    [ -n "$tmp" ] && rm -f "$tmp"
    jq -n --arg reason "$reason" --arg source "$source" --arg file "$file" \
      --arg violations "$violations" --arg updatedAt "$now" \
      '{status: "failing", reason: $reason, source: $source, file: $file,
        violations: $violations, updatedAt: $updatedAt}' > "$gate_file" 2>/dev/null || true
  fi
}

# gate_clear_file GATE_FILE FILE SOURCE
# Removes this file's entry IF this source owns it. Other entries are promoted
# back to the top level (gate stays failing); "passing" is written only when
# no entry remains. A failing record owned by another source/file is left
# untouched, matching the old single-slot clear semantics.
gate_clear_file() {
  local gate_file="$1" file="$2" source="$3"
  local existing now owns tmp
  [ -f "$gate_file" ] || return 0
  existing=$(cat "$gate_file" 2>/dev/null) || return 0
  # A malformed gate file can't be parsed, so a clear silently no-ops and the
  # gate stays stuck failing until the next gate_record_failure rewrites it.
  # Emit a breadcrumb so that stuck state is debuggable, not invisible.
  if ! jq -e . <<< "$existing" >/dev/null 2>&1; then
    printf 'gate-file: malformed JSON at %s; ignoring clear (gate stays failing until next write)\n' "$gate_file" >&2
    return 0
  fi
  [ "$(jq -r '.status // ""' <<< "$existing" 2>/dev/null)" = "failing" ] || return 0
  owns=$(jq -r --arg f "$file" --arg s "$source" '
    if (.entries? | type) == "object"
    then (((.entries[$f]? // {}) | .source // "") == $s)
    else ((.source // "") == $s and (.file // "") == $f)
    end' <<< "$existing" 2>/dev/null)
  [ "$owns" = "true" ] || return 0
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tmp=$(mktemp "${gate_file}.XXXXXX" 2>/dev/null) || return 0
  if jq --arg file "$file" --arg source "$source" --arg now "$now" '
    ((if (.entries? | type) == "object" then .entries
      elif (.status // "") == "failing" then
        { (.file // "__global__"): {
            source: (.source // ""), reason: (.reason // ""),
            violations: (.violations // ""), updatedAt: (.updatedAt // $now) } }
      else {} end) | del(.[$file])) as $left
    | if ($left | length) == 0
      then { status: "passing", source: $source, updatedAt: $now }
      else (($left | to_entries | sort_by(.value.updatedAt // "", .key)) as $sorted
        | ($sorted | last) as $latest
        | { status: "failing",
            reason: ($latest.value.reason // "Quality gate failing"),
            source: ($latest.value.source // ""),
            file: $latest.key,
            violations: ([$sorted[] | (.value.violations // "")] | join("")),
            entries: $left, updatedAt: $now })
      end
  ' <<< "$existing" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$gate_file"
  else
    rm -f "$tmp"
  fi
}

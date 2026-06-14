#!/usr/bin/env bash
# byte-savings-report.sh <ledger.jsonl>
#
# Aggregates a per-session byte-savings ledger (written by the post-tools
# byte-savings instrumentation module) into a per-kind summary: bytes each tool
# returned into context (with a ~token estimate at 4 bytes/token) and, for
# single-file Reads, the targeting saving vs reading the whole file. Read-only.
set -u

ledger="${1:-}"
command -v jq >/dev/null 2>&1 || { echo "byte-savings-report: jq required" >&2; exit 1; }
[ -n "$ledger" ] && [ -f "$ledger" ] || {
  echo "usage: byte-savings-report.sh <ledger.jsonl>" >&2; exit 1; }

jq -rs '
  group_by(.kind)
  | map({ kind: .[0].kind,
          n: length,
          returned: (map(.returned) | add),
          full: (map(.full) | add) }) as $g
  | ($g | map(.returned) | add) as $tot
  | ( $g[]
      | if .kind == "read" and .full > 0
        then "\(.kind): returned=\(.returned) full=\(.full) saved=\((((.full - .returned) * 100) / .full) | floor)% (n=\(.n))"
        else "\(.kind): returned=\(.returned) (n=\(.n))"
        end ),
    "TOTAL returned: \($tot) bytes (~\(($tot / 4) | floor) tok)"
' "$ledger"

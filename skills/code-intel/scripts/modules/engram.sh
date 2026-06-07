#!/bin/bash
# engram CLI wrapper — persistent memory for AI agents
# Defaults to the current project (git toplevel basename) + strict project filtering.
# Override with MY_CLAUDE_ENGRAM_PROJECT=<name>.
# NOTE: this inline detection is a stand-in for the detect_project_name helper
# that lands in Phase 4 (Task 35); Task 46 will swap this block for the helper.
set -euo pipefail

PROJECT="${MY_CLAUDE_ENGRAM_PROJECT:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo unknown)}"

subcmd="${1:-}"
shift 2>/dev/null || true

usage() {
  cat <<'USAGE'
Usage: engram.sh <subcommand> [args...]

Subcommands:
  search <query> [flags]              Search memories (--project <detected> --limit 20, strict filter)
  save <title> <content> [flags]      Save observation (--project <detected>)
  context                             Recent session context for current project
  timeline <id> [flags]               Chronological context (--before 3 --after 3)
  get <id>                            Full observation content (timeline workaround)
  summary <content>                   Save session summary (--type session_summary)
  stats                               System statistics

Pass-through flags: --type <type>, --scope <scope>, --topic <key>, --limit N
USAGE
  exit 1
}

# Filter engram output to only show records belonging to this project.
# Records start with "[N]" lines. Buffer each record, emit only if "project: <proj>".
filter_project() {
  local tmpbody tmpraw
  tmpraw=$(mktemp)
  tmpbody=$(mktemp)
  # shellcheck disable=SC2064  # Expand $tmpraw/$tmpbody now so they are captured in the RETURN trap.
  trap "rm -f '$tmpraw' '$tmpbody'" RETURN

  # Capture raw input
  cat > "$tmpraw"

  # Parse records, emit only matching project
  awk -v proj="$PROJECT" '
    NR == 1 { next }

    /^\[/ {
      if (buf != "" && matched) {
        kept++
        idx = index(buf, "] ")
        if (idx > 0) body = substr(buf, idx+1)
        else body = buf
        printf "[%d] %s\n\n", kept, body
      }
      buf = ""
      matched = 0
    }

    { if (buf == "") buf = $0; else buf = buf "\n" $0 }

    $0 ~ "project: " proj { matched = 1 }

    END {
      if (buf != "" && matched) {
        kept++
        idx = index(buf, "] ")
        if (idx > 0) body = substr(buf, idx+1)
        else body = buf
        printf "[%d] %s\n", kept, body
      }
      # Write count to stderr
      printf "%d\n", kept+0 > "/dev/stderr"
    }
  ' "$tmpraw" > "$tmpbody" 2>"${tmpbody}.count"

  local count
  count=$(cat "${tmpbody}.count")
  rm -f "${tmpbody}.count"

  echo "Found ${count} memories (filtered to ${PROJECT}):"
  echo ""
  cat "$tmpbody"
}

case "$subcmd" in
  search)
    query="${1:?search requires a query}"
    shift
    # Over-fetch then strict-filter to compensate for dropped cross-project results
    engram search "$query" --project "$PROJECT" --limit 20 "$@" | filter_project
    ;;
  save)
    title="${1:?save requires a title}"
    content="${2:?save requires content}"
    shift 2
    exec engram save "$title" "$content" --project "$PROJECT" "$@"
    ;;
  context)
    exec engram context "$PROJECT" "$@"
    ;;
  timeline)
    obs_id="${1:?timeline requires an observation ID}"
    shift
    exec engram timeline "$obs_id" --before 3 --after 3 "$@"
    ;;
  get)
    obs_id="${1:?get requires an observation ID}"
    shift
    exec engram timeline "$obs_id" --before 0 --after 0 "$@"
    ;;
  summary)
    content="${1:?summary requires content}"
    shift
    exec engram save "Session summary" "$content" --type session_summary --project "$PROJECT" "$@"
    ;;
  stats)
    exec engram stats "$@"
    ;;
  *)
    usage
    ;;
esac

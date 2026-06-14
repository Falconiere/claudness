#!/usr/bin/env bash
set -euo pipefail

# Context7 CLI — search libraries and query documentation
# Usage: ./search.sh <command> [options]
#
# Reads CONTEXT7_API_KEY from the environment (never from .env).

command -v jq   >/dev/null 2>&1 || { echo "context7: jq required" >&2;   exit 1; }
command -v curl >/dev/null 2>&1 || { echo "context7: curl required" >&2; exit 1; }

C7_API_KEY="${CONTEXT7_API_KEY:-}"
C7_URL="https://context7.com/api/v2"

urlencode() {
  python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

c7_get() {
  local endpoint="$1"
  shift
  local url="$C7_URL/$endpoint"

  # Build query string from remaining args (key=value pairs)
  local sep="?"
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    url="${url}${sep}${key}=$(urlencode "$val")"
    sep="&"
  done

  local headers=(-H "Accept: application/json")
  if [[ "${C7_API_KEY:-}" == ctx7sk* ]]; then
    headers+=(-H "Authorization: Bearer $C7_API_KEY")
  fi

  curl -sS --fail-with-body "${headers[@]}" "$url"
}

# ── search ──────────────────────────────────────────────────
cmd_search() {
  local library="" query=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--library) library="$2"; shift 2;;
      -q|--query)   query="$2"; shift 2;;
      *)
        # first bare arg = library, second = query
        if [[ -z "$library" ]]; then library="$1"; shift
        elif [[ -z "$query" ]]; then query="$1"; shift
        else echo "Unknown option: $1" >&2; exit 1; fi
        ;;
    esac
  done

  if [[ -z "$library" ]]; then
    echo "Usage: search.sh search <library> [query]" >&2
    echo "  Searches for libraries matching the name" >&2
    echo "" >&2
    echo "  -l, --library  Library name (required)" >&2
    echo "  -q, --query    Context for ranking results" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  search.sh search react" >&2
    echo "  search.sh search tokio \"async runtime for Rust\"" >&2
    exit 1
  fi

  # Default query to library name if not provided
  query="${query:-$library}"

  c7_get "libs/search" "libraryName=$library" "query=$query" | jq '.'
}

# ── docs ────────────────────────────────────────────────────
cmd_docs() {
  local library_id="" query="" output_type="json" fast=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--library-id) library_id="$2"; shift 2;;
      -q|--query)      query="$2"; shift 2;;
      -t|--type)       output_type="$2"; shift 2;;
      --fast)          fast="true"; shift;;
      *)
        # first bare arg = library_id, second = query
        if [[ -z "$library_id" ]]; then library_id="$1"; shift
        elif [[ -z "$query" ]]; then query="$1"; shift
        else echo "Unknown option: $1" >&2; exit 1; fi
        ;;
    esac
  done

  if [[ -z "$library_id" || -z "$query" ]]; then
    echo "Usage: search.sh docs <library_id> <query>" >&2
    echo "  Retrieves documentation context for a library" >&2
    echo "" >&2
    echo "  -l, --library-id  Context7 library ID, e.g. /vercel/next.js (required)" >&2
    echo "  -q, --query       Your question (required)" >&2
    echo "  -t, --type        Output format: json|txt (default: json; txt is LLM-prompt-ready)" >&2
    echo "  --fast            Skip LLM reranking, return top vector-search hits (lower latency)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  search.sh docs /vercel/next.js \"app router file conventions\"" >&2
    echo "  search.sh docs /tokio-rs/tokio \"spawn async tasks\" -t txt" >&2
    echo "" >&2
    echo "Tip: Run 'search.sh search <name>' first to find the library ID." >&2
    exit 1
  fi

  local params=("libraryId=$library_id" "query=$query" "type=$output_type")
  if [[ -n "$fast" ]]; then
    params+=("fast=true")
  fi

  c7_get "context" "${params[@]}" | \
    if [[ "$output_type" == "json" ]]; then jq '.'; else cat; fi
}

# ── main ────────────────────────────────────────────────────
usage() {
  echo "Context7 CLI — Library Documentation Lookup" >&2
  echo "" >&2
  echo "Usage: search.sh <command> [options]" >&2
  echo "" >&2
  echo "Environment:" >&2
  echo "  CONTEXT7_API_KEY  Optional. If set and starts with 'ctx7sk', sent as Bearer token." >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  search  Find libraries by name (resolve library ID)" >&2
  echo "  docs    Query documentation for a library" >&2
  echo "" >&2
  echo "Workflow:" >&2
  echo "  1. search.sh search <library>    # find the library ID" >&2
  echo "  2. search.sh docs <id> <query>   # query its docs" >&2
  echo "" >&2
  echo "Run 'search.sh <command>' with no args for command-specific help." >&2
  exit 1
}

case "${1:-}" in
  -h|--help|"") usage;;
  search)  shift; cmd_search "$@";;
  docs)    shift; cmd_docs "$@";;
  *)
    # bare args — default to search
    cmd_search "$@"
    ;;
esac

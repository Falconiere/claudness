#!/bin/bash
set -euo pipefail

# Exa API CLI — search, crawl, and find similar content
# Usage: ./search.sh <command> [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_ENV="$SCRIPT_DIR/../.env"
EXA_API_KEY="$(grep '^EXA_API_KEY=' "$TOOLING_ENV" 2>/dev/null | cut -d= -f2 || true)"
EXA_URL="https://api.exa.ai"

if [[ -z "$EXA_API_KEY" ]]; then
  echo "Error: EXA_API_KEY not found in $TOOLING_ENV" >&2
  exit 1
fi

exa_post() {
  local endpoint="$1"
  local body="$2"
  curl -sS --fail-with-body \
    -X POST "$EXA_URL/$endpoint" \
    -H "x-api-key: $EXA_API_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$body"
}

# ── search ──────────────────────────────────────────────────
cmd_search() {
  local query="" num_results=10 search_type="auto" category=""
  local include_domains="" exclude_domains=""
  local start_date="" end_date=""
  local include_text="" exclude_text=""
  local highlights_chars=4000 with_text="false" lean="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q|--query)       query="$2"; shift 2;;
      -n|--num-results) num_results="$2"; shift 2;;
      -t|--type)        search_type="$2"; shift 2;;
      -c|--category)    category="$2"; shift 2;;
      --include-domains) include_domains="$2"; shift 2;;
      --exclude-domains) exclude_domains="$2"; shift 2;;
      --start-date)     start_date="$2"; shift 2;;
      --end-date)       end_date="$2"; shift 2;;
      --include-text)   include_text="$2"; shift 2;;
      --exclude-text)   exclude_text="$2"; shift 2;;
      --highlights)     highlights_chars="$2"; shift 2;;
      --with-text)      with_text="true"; shift;;
      --lean)           lean="true"; shift;;
      *)
        # treat bare arg as query
        if [[ -z "$query" ]]; then query="$1"; shift
        else echo "Unknown option: $1" >&2; exit 1; fi
        ;;
    esac
  done

  if [[ -z "$query" ]]; then
    echo "Usage: search.sh search -q <query> [options]" >&2
    echo "  -n, --num-results  Number of results (default: 10)" >&2
    echo "  -t, --type         instant|fast|auto|deep-lite|deep|deep-reasoning (default: auto)" >&2
    echo "  -c, --category     company|research paper|news|personal site|financial report|people" >&2
    echo "  --include-domains  Comma-separated domains to include" >&2
    echo "  --exclude-domains  Comma-separated domains to exclude" >&2
    echo "  --start-date       Start published date (YYYY-MM-DD)" >&2
    echo "  --end-date         End published date (YYYY-MM-DD)" >&2
    echo "  --include-text     Text that must appear in results" >&2
    echo "  --exclude-text     Text to exclude from results" >&2
    echo "  --highlights N     Max highlight chars (default: 4000)" >&2
    echo "  --with-text        Include full text in results" >&2
    echo "  --lean             Strip image/favicon/subpages/entities for AI prompts" >&2
    exit 1
  fi

  # Build JSON with jq to handle escaping properly
  local body
  body=$(jq -n \
    --arg q "$query" \
    --arg t "$search_type" \
    --argjson n "$num_results" \
    --argjson hc "$highlights_chars" \
    --argjson wt "$with_text" \
    '{query: $q, type: $t, numResults: $n, contents: {highlights: {maxCharacters: $hc}}}
     | if $wt then .contents.text = true else . end')

  # Add optional fields
  if [[ -n "$category" ]]; then
    body=$(echo "$body" | jq --arg c "$category" '.category = $c')
  fi
  if [[ -n "$include_domains" ]]; then
    body=$(echo "$body" | jq --arg d "$include_domains" '.includeDomains = ($d | split(","))')
  fi
  if [[ -n "$exclude_domains" ]]; then
    body=$(echo "$body" | jq --arg d "$exclude_domains" '.excludeDomains = ($d | split(","))')
  fi
  if [[ -n "$start_date" ]]; then
    body=$(echo "$body" | jq --arg d "${start_date}T00:00:00.000Z" '.startPublishedDate = $d')
  fi
  if [[ -n "$end_date" ]]; then
    body=$(echo "$body" | jq --arg d "${end_date}T00:00:00.000Z" '.endPublishedDate = $d')
  fi
  if [[ -n "$include_text" ]]; then
    body=$(echo "$body" | jq --arg t "$include_text" '.includeText = [$t]')
  fi
  if [[ -n "$exclude_text" ]]; then
    body=$(echo "$body" | jq --arg t "$exclude_text" '.excludeText = [$t]')
  fi

  if [[ "$lean" == "true" ]]; then
    exa_post "search" "$body" | jq '{
      requestId,
      results: [(.results // [])[] | {
        title,
        url,
        publishedDate,
        author,
        highlights,
        text,
        summary
      } | with_entries(select(.value != null and .value != ""))]
    }'
  else
    exa_post "search" "$body" | jq '.'
  fi
}

# ── crawl ───────────────────────────────────────────────────
cmd_crawl() {
  local max_chars=3000
  local urls=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--max-chars) max_chars="$2"; shift 2;;
      *)              urls+=("$1"); shift;;
    esac
  done

  if [[ ${#urls[@]} -eq 0 ]]; then
    echo "Usage: search.sh crawl <url> [url...] [-m max_chars]" >&2
    echo "  Extracts content from one or more URLs" >&2
    echo "  -m, --max-chars  Max characters per page (default: 3000)" >&2
    exit 1
  fi

  # Build URL array as JSON
  local urls_json
  urls_json=$(printf '%s\n' "${urls[@]}" | jq -R . | jq -s .)

  local body
  body=$(jq -n \
    --argjson mc "$max_chars" \
    --argjson urls "$urls_json" \
    '{urls: $urls, text: true, highlights: {maxCharacters: $mc}}')

  exa_post "contents" "$body" | jq '.'
}

# ── similar ─────────────────────────────────────────────────
cmd_similar() {
  local url="" num_results=10 highlights_chars=4000

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--num-results) num_results="$2"; shift 2;;
      --highlights)     highlights_chars="$2"; shift 2;;
      *)
        if [[ -z "$url" ]]; then url="$1"; shift
        else echo "Unknown option: $1" >&2; exit 1; fi
        ;;
    esac
  done

  if [[ -z "$url" ]]; then
    echo "Usage: search.sh similar <url> [-n num_results]" >&2
    echo "  Finds pages similar to the given URL" >&2
    echo "  -n, --num-results  Number of results (default: 10)" >&2
    echo "  --highlights N     Max highlight chars (default: 4000)" >&2
    exit 1
  fi

  local body
  body=$(jq -n \
    --arg u "$url" \
    --argjson n "$num_results" \
    --argjson hc "$highlights_chars" \
    '{url: $u, numResults: $n, contents: {highlights: {maxCharacters: $hc}}}')

  exa_post "findSimilar" "$body" | jq '.'
}

# ── main ────────────────────────────────────────────────────
usage() {
  echo "Exa Search CLI" >&2
  echo "" >&2
  echo "Usage: search.sh <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  search   Search the web (default if no command given)" >&2
  echo "  crawl    Extract content from URLs" >&2
  echo "  similar  Find pages similar to a URL" >&2
  echo "" >&2
  echo "Run 'search.sh <command>' with no args for command-specific help." >&2
  exit 1
}

case "${1:-}" in
  -h|--help|"") usage;;
  search)  shift; cmd_search "$@";;
  crawl)   shift; cmd_crawl "$@";;
  similar) shift; cmd_similar "$@";;
  # bare query — default to search
  *)       cmd_search "$@";;
esac

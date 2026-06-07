#!/usr/bin/env bash
# Claudness runtime config loader.
#
# Reads two layers of JSON config and merges them (project override wins):
#   1. ~/.claude/claudness.config.json
#   2. $CLAUDE_PROJECT_DIR/.claude/claudness.config.json
#
# Public API:
#   claudness_load_config          - load + cache the merged config
#   claudness_enabled CAT NAME     - 0 if enabled (default), 1 if disabled
#   claudness_disabled_skills      - print disabled skill names, one per line
#
# Defaults: missing key = enabled. Malformed JSON or missing jq = all enabled
# with a single stderr warning.

CLAUDNESS_CFG_CACHE="${TMPDIR:-/tmp}/claudness-cfg-$$.json"
CLAUDNESS_CFG_LOADED=0

_claudness_warn() {
  printf 'claudness-config: %s\n' "$1" >&2
}

_claudness_user_cfg() {
  printf '%s/.claude/claudness.config.json' "$HOME"
}

_claudness_project_cfg() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  [ -z "$root" ] && root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [ -z "$root" ] && return 0
  printf '%s/.claude/claudness.config.json' "$root"
}

claudness_load_config() {
  [ "$CLAUDNESS_CFG_LOADED" = "1" ] && return 0
  CLAUDNESS_CFG_LOADED=1

  if ! command -v jq >/dev/null 2>&1; then
    _claudness_warn "jq missing; all components enabled"
    printf '{}' > "$CLAUDNESS_CFG_CACHE"
    return 0
  fi

  local user_cfg project_cfg user_json='{}' project_json='{}'
  user_cfg=$(_claudness_user_cfg)
  project_cfg=$(_claudness_project_cfg)

  if [ -f "$user_cfg" ]; then
    if ! user_json=$(jq -e . "$user_cfg" 2>/dev/null); then
      _claudness_warn "malformed JSON in $user_cfg; ignoring"
      user_json='{}'
    fi
  fi

  if [ -n "$project_cfg" ] && [ -f "$project_cfg" ]; then
    if ! project_json=$(jq -e . "$project_cfg" 2>/dev/null); then
      _claudness_warn "malformed JSON in $project_cfg; ignoring"
      project_json='{}'
    fi
  fi

  jq -n --argjson u "$user_json" --argjson p "$project_json" \
    '$u * $p' > "$CLAUDNESS_CFG_CACHE" 2>/dev/null || printf '{}' > "$CLAUDNESS_CFG_CACHE"
}

claudness_enabled() {
  local category="$1" name="$2"
  claudness_load_config
  command -v jq >/dev/null 2>&1 || return 0
  local val
  val=$(jq -r --arg c "$category" --arg n "$name" \
    'if (.[$c]? // {}) | has($n) then .[$c][$n] | tostring else "missing" end' \
    "$CLAUDNESS_CFG_CACHE" 2>/dev/null)
  [ "$val" = "false" ] && return 1
  return 0
}

claudness_disabled_skills() {
  claudness_load_config
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.skills // {} | to_entries[] | select(.value == false) | .key' \
    "$CLAUDNESS_CFG_CACHE" 2>/dev/null
}

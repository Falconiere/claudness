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
#   claudness_comemory_state       - print 'available' | 'missing' | 'disabled'
#   claudness_config_exists        - 0 if any config file is on disk (cheap stat-only check)
#
# Defaults: missing key = enabled. Malformed JSON or missing jq = all enabled
# with a single stderr warning.

# Merged config is held in memory, not a temp file: hooks are short-lived
# processes, and a per-PID cache file under $TMPDIR was never cleaned up —
# one leaked file per hook invocation. $(...) subshells inherit the variable
# exactly like they inherited the file path, so load-once semantics hold.
CLAUDNESS_CFG_JSON='{}'
CLAUDNESS_CFG_LOADED=0
_CLAUDNESS_HAS_JQ=""

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

  if command -v jq >/dev/null 2>&1; then
    _CLAUDNESS_HAS_JQ=1
  else
    _CLAUDNESS_HAS_JQ=0
    _claudness_warn "jq missing; all components enabled"
    CLAUDNESS_CFG_JSON='{}'
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

  CLAUDNESS_CFG_JSON=$(jq -cn --argjson u "$user_json" --argjson p "$project_json" \
    '$u * $p' 2>/dev/null) || CLAUDNESS_CFG_JSON='{}'
}

claudness_enabled() {
  local category="$1" name="$2"
  claudness_load_config
  [ "$_CLAUDNESS_HAS_JQ" = "1" ] || return 0
  local val
  val=$(jq -r --arg c "$category" --arg n "$name" \
    'if (.[$c]? // {}) | has($n) then .[$c][$n] | tostring else "missing" end' \
    <<< "$CLAUDNESS_CFG_JSON" 2>/dev/null)
  [ "$val" = "false" ] && return 1
  return 0
}

# Like claudness_enabled but DEFAULT OFF: returns 0 only when the key is
# explicitly `true`. For opt-in components (e.g. the session-end comemory
# reminder) where the default-enabled opt-out semantics are wrong. Missing jq or
# a missing/non-true value -> 1 (disabled).
claudness_enabled_explicit() {
  local category="$1" name="$2"
  claudness_load_config
  [ "$_CLAUDNESS_HAS_JQ" = "1" ] || return 1
  local val
  val=$(jq -r --arg c "$category" --arg n "$name" \
    '(.[$c]? // {})[$n]? | tostring' <<< "$CLAUDNESS_CFG_JSON" 2>/dev/null)
  [ "$val" = "true" ] && return 0
  return 1
}

# Return 0 if any config file is on disk. Stat-only; no jq, no load. Used by
# hot-path hooks (e.g. mcp-blocker) to skip config-load entirely when no
# user has opted in.
claudness_config_exists() {
  local user_cfg project_cfg
  user_cfg=$(_claudness_user_cfg)
  [ -f "$user_cfg" ] && return 0
  project_cfg=$(_claudness_project_cfg)
  [ -n "$project_cfg" ] && [ -f "$project_cfg" ] && return 0
  return 1
}

# Print comemory availability for hook reminder text:
#   'available' — CLI installed AND skills.comemory != false
#   'missing'   — CLI absent AND skills.comemory != false (emit install hint)
#   'disabled'  — skills.comemory == false (silent; user opted out)
#
# Centralizes the tri-state so pre-compact / session-end / user-prompt-submit
# do not each hand-roll the branching.
claudness_comemory_state() {
  if ! claudness_enabled skills comemory; then
    printf 'disabled'
    return 0
  fi
  if command -v comemory >/dev/null 2>&1; then
    printf 'available'
  else
    printf 'missing'
  fi
}


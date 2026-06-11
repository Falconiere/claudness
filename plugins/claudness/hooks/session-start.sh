#!/usr/bin/env bash
# SessionStart hook
# Event-aware: tailors context for startup, resume, clear, compact.
# Project-agnostic: detects project name, language, and package manager.

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Disable bash 5.2+ patsub_replacement so `&` in ${var//pat/repl} values is
# literal. No-op (option unknown) on older bash, including macOS /bin/bash 3.2.
shopt -u patsub_replacement 2>/dev/null || true

# shellcheck source=lib/detect.sh
. "$HOOK_DIR/lib/detect.sh"
# shellcheck source=lib/config.sh
. "$HOOK_DIR/lib/config.sh"

if ! claudness_enabled hooks session-start; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

PROJECT_ROOT="$(detect_project_root)"
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
PROJECT_NAME="$(detect_project_name)"
NODE_PM="$(detect_node_pm)"
HAS_RUST="$(detect_rust)"
HAS_TS="$(detect_ts)"

GATE_FILE="$PROJECT_ROOT/.claude/tmp/quality-gate-status.json"

# ── Parse stdin to detect event type ────────────────────────────────────────
input=$(cat 2>/dev/null || echo "{}")
event="startup"
if command -v jq >/dev/null 2>&1; then
  # Claude Code sends the SessionStart event type in `source`
  # (startup | resume | clear | compact); keep legacy fields as fallbacks.
  event=$(jq -r '.source // .session_event // .event // "startup"' <<< "$input" 2>/dev/null || echo "startup")
fi
[[ -z "$event" || "$event" == "null" ]] && event="startup"

# ── Render the main session doc with project tokens substituted ─────────────
render_doc() {
  local src="$1"
  [ -f "$src" ] || { echo ""; return 0; }
  local content
  content=$(cat "$src")
  # Substitute placeholders with bash-native replacement — immune to sed
  # metacharacters (|, &, \) in project names or package manager values.
  # Replacement is deliberately UNQUOTED: quoting inside ${} inserts literal
  # quote characters on bash 3.2 (stock macOS). Literal-& safety on bash 5.2+
  # comes from `shopt -u patsub_replacement` at the top of this script.
  local name="${PROJECT_NAME:-this project}"
  local pm="${NODE_PM:-your package manager}"
  content="${content//\{\{project_name\}\}/$name}"
  content="${content//\{\{node_pm\}\}/$pm}"
  printf '%s' "$content"
}

# ── Git context (branch + dirty count) ──────────────────────────────────────
git_ctx=""
if command -v git >/dev/null 2>&1; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -n "$branch" ]]; then
    dirty_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$dirty_count" -gt 0 ]]; then
      git_ctx="Branch: $branch ($dirty_count uncommitted files)"
    else
      git_ctx="Branch: $branch (clean)"
    fi
  fi
fi

# ── Quality gate status ─────────────────────────────────────────────────────
gate_hint=""
if [[ -f "$GATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
  gate_status=$(jq -r '.status // ""' "$GATE_FILE" 2>/dev/null)
  if [[ "$gate_status" == "failing" ]]; then
    reason=$(jq -r '.reason // "Unknown"' "$GATE_FILE" 2>/dev/null)
    gate_hint="WARNING: Quality gate failing — $reason. Fix before other work."
  fi
fi

# ── Build context based on event type ───────────────────────────────────────
parts=()
title=""

main_doc=$(render_doc "$HOOK_DIR/docs/session-start.md")

case "$event" in
  startup)
    title="Session started"
    [ -n "$main_doc" ] && parts+=("$main_doc")
    ;;
  resume)
    title="Session resumed"
    [ -n "$main_doc" ] && parts+=("$main_doc")
    ;;
  clear)
    title="Context cleared"
    [ -n "$main_doc" ] && parts+=("$main_doc")
    ;;
  compact)
    title="Context compacted"
    compaction=$(cat "$HOOK_DIR/docs/post-compaction.md" 2>/dev/null || echo "")
    [[ -n "$compaction" ]] && parts+=("$compaction")
    [ -n "$main_doc" ] && parts+=("$main_doc")
    ;;
esac

# Per-toolchain snippets — opt-in via $CLAUDNESS_VERBOSE to save tokens.
# Default off: the session-start.md core already covers project rules.
# Set CLAUDNESS_VERBOSE=1 to re-enable per-toolchain blocks. Any value other
# than "0" / unset / empty enables (so `=true`, `=on`, `=1` all work, but a
# user who sets `=0` to disable is not surprised).
if [ "${CLAUDNESS_VERBOSE:-0}" != "0" ] && [ -n "${CLAUDNESS_VERBOSE:-}" ]; then
  if [ "$HAS_TS" = "ts" ]; then
    ts_doc=$(render_doc "$HOOK_DIR/docs/session-start-ts.md")
    [ -n "$ts_doc" ] && parts+=("$ts_doc")
  fi
  if [ "$HAS_RUST" = "rust" ]; then
    rust_doc=$(render_doc "$HOOK_DIR/docs/session-start-rust.md")
    [ -n "$rust_doc" ] && parts+=("$rust_doc")
  fi
fi

# Append project line only when name was detected.
if [ -n "$PROJECT_NAME" ]; then
  parts+=("Project: $PROJECT_NAME")
fi

# Warn when optional tools referenced by docs/skills are missing — keeps the
# session start honest about which capabilities are actually available.
HAS_ENGRAM="$(detect_engram)"
HAS_ASTGREP="$(detect_ast_grep)"
missing_tools=()
if [ "$HAS_ENGRAM" != "engram" ] && claudness_enabled skills engram; then
  missing_tools+=("engram (persistent memory recall/save)")
fi
if [ "$HAS_ASTGREP" != "ast-grep" ] && claudness_enabled skills ast-grep; then
  missing_tools+=("ast-grep (structural code search)")
fi
if [ "${#missing_tools[@]}" -gt 0 ]; then
  warn="WARN: optional tools missing — features that depend on them are disabled:"
  for t in "${missing_tools[@]}"; do
    warn+="
  • $t"
  done
  parts+=("$warn")
fi

# Verify required plugin dependencies declared in plugin.json `dependencies`
# (Claude Code's official schema: array of "name" strings or
# {name, marketplace?, version?} objects). Auto-install only fires when the
# dep's marketplace is already configured; we surface the exact
# `/plugin install …` command so the user can fix in one paste.
#
# Scope: the check only fires when we can locate the claudness plugin manifest
# (via CLAUDE_PLUGIN_ROOT, set by Claude Code when this hook runs from the
# installed plugin, or via the in-repo path when working inside the claudness
# checkout itself). Outside both — e.g., a hook run by another project that
# inherits these helpers — the block silently no-ops. Intentional: repo-A
# should not WARN about plugin deps declared in repo-B's manifest.
plugin_manifest=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
  plugin_manifest="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
elif [ -f "$PROJECT_ROOT/plugins/claudness/.claude-plugin/plugin.json" ]; then
  plugin_manifest="$PROJECT_ROOT/plugins/claudness/.claude-plugin/plugin.json"
fi
if [[ -n "$plugin_manifest" && -f "$plugin_manifest" ]] && command -v jq >/dev/null 2>&1; then
  missing_plugins=()
  indeterminate=0
  while IFS= read -r req_spec; do
    [ -z "$req_spec" ] && continue
    installed=$(detect_plugin_installed "$req_spec")
    rc=$?
    if [ "$rc" -eq 2 ]; then
      # Registry/jq unavailable on this box — suppress all WARNs in this
      # block so we don't spam every required plugin as "missing" on a
      # machine where the registry was moved or jq was uninstalled.
      indeterminate=1
      break
    fi
    if [ -z "$installed" ]; then
      missing_plugins+=("/plugin install ${req_spec}")
    fi
  done < <(jq -r '
    (.dependencies // [])[]
    | if type == "string" then .
      elif (.name | type) != "string" then empty
      elif .marketplace then "\(.name)@\(.marketplace)"
      else .name end
  ' "$plugin_manifest" 2>/dev/null)
  if [ "$indeterminate" -eq 0 ] && [ "${#missing_plugins[@]}" -gt 0 ]; then
    pwarn="WARN: required plugins missing — review/simplify pipelines will fail. Install:"
    for cmd in "${missing_plugins[@]}"; do
      pwarn+="
  • $cmd"
    done
    parts+=("$pwarn")
  fi
fi

# Append git context and gate status
[[ -n "$git_ctx" ]] && parts+=("$git_ctx")
[[ -n "$gate_hint" ]] && parts+=("$gate_hint")

# ── Join and output ─────────────────────────────────────────────────────────
full_context=""
for part in "${parts[@]}"; do
  if [[ -z "$full_context" ]]; then
    full_context="$part"
  else
    full_context="$full_context

$part"
  fi
done

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$full_context" --arg title "$title" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $ctx
    },
    "systemMessage": $title
  }'
fi

exit 0

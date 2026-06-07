#!/bin/bash
# SessionStart hook
# Event-aware: tailors context for startup, resume, clear, compact.

HOOK_DIR="$(dirname "$0")"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GATE_FILE="$PROJECT_ROOT/.claude/tmp/quality-gate-status.json"

# ── Parse stdin to detect event type ────────────────────────────────────────
input=$(cat 2>/dev/null || echo "{}")
# SessionStart matcher gives us: startup, resume, clear, compact
event=$(jq -r '.session_event // .event // "startup"' <<< "$input" 2>/dev/null || echo "startup")
# Fallback: if we got empty or null, default to startup
[[ -z "$event" || "$event" == "null" ]] && event="startup"

# ── Git context (branch + dirty count) ──────────────────────────────────────
git_ctx=""
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ -n "$branch" ]]; then
  dirty_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$dirty_count" -gt 0 ]]; then
    git_ctx="Branch: $branch ($dirty_count uncommitted files)"
  else
    git_ctx="Branch: $branch (clean)"
  fi
fi

# ── Quality gate status ─────────────────────────────────────────────────────
gate_hint=""
if [[ -f "$GATE_FILE" ]]; then
  gate_status=$(jq -r '.status // ""' "$GATE_FILE" 2>/dev/null)
  if [[ "$gate_status" == "failing" ]]; then
    reason=$(jq -r '.reason // "Unknown"' "$GATE_FILE" 2>/dev/null)
    gate_hint="WARNING: Quality gate failing — $reason. Fix before other work."
  fi
fi

# ── Build context based on event type ───────────────────────────────────────
parts=()
title=""

case "$event" in
  startup)
    title="Session started"
    # Full protocol on fresh start
    context=$(cat "$HOOK_DIR/docs/session-start.md" 2>/dev/null || echo "Session started.")
    parts+=("$context")
    ;;
  resume)
    title="Session resumed"
    # Lighter — protocol already loaded, just refresh state
    context=$(cat "$HOOK_DIR/docs/session-start.md" 2>/dev/null || echo "Session resumed.")
    parts+=("$context")
    ;;
  clear)
    title="Context cleared"
    # Full reinit after clear — context is gone
    context=$(cat "$HOOK_DIR/docs/session-start.md" 2>/dev/null || echo "Context cleared.")
    parts+=("$context")
    ;;
  compact)
    title="Context compacted"
    # Recovery-focused: post-compaction + protocol refresh
    compaction=$(cat "$HOOK_DIR/docs/post-compaction.md" 2>/dev/null || echo "")
    context=$(cat "$HOOK_DIR/docs/session-start.md" 2>/dev/null || echo "")
    [[ -n "$compaction" ]] && parts+=("$compaction")
    parts+=("$context")
    ;;
esac

# Append git context and gate status
[[ -n "$git_ctx" ]] && parts+=("$git_ctx")
[[ -n "$gate_hint" ]] && parts+=("$gate_hint")

# Compact reminder (shared across all events)
reminder="MANDATORY: recall via .claude/skills/code-intel/scripts/mod.sh engram search before explore. Save reusable learnings via mod.sh engram save. Do not proceed while quality gate fails. Max 3% duplication (jscpd). No #[allow()] or #[expect()] in Rust. TS tests in co-located __tests__/. Never run git push. Never bypass quality gates."
parts+=("$reminder")

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


jq -n --arg ctx "$full_context" --arg title "$title" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  },
  "systemMessage": $title
}'

exit 0

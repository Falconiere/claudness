#!/usr/bin/env bash
# UserPromptSubmit hook
# Validates prompts, injects optional per-project context, git context, intent hints.
# Project-agnostic: no project literals. Per-project hints opt-in via $root/.claude/context.sh.

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/detect.sh
. "$HOOK_DIR/lib/detect.sh"
# shellcheck source=lib/config.sh
. "$HOOK_DIR/lib/config.sh"

if ! claudness_enabled hooks user-prompt-submit; then
  cat > /dev/null 2>&1 || true
  exit 0
fi

input=$(cat)
prompt=""
if command -v jq >/dev/null 2>&1; then
  prompt=$(jq -r '.prompt // ""' <<< "$input" 2>/dev/null || echo "")
fi

[[ -z "$prompt" ]] && exit 0

PROJECT_ROOT="$(detect_project_root)"
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
GATE_FILE="$PROJECT_ROOT/.claude/tmp/quality-gate-status.json"
prompt_lower=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')

# ── Skip trivial prompts (confirmations, short replies) ───────────────────────
if [[ "$prompt_lower" =~ ^(y|n|yes|no|ok|sure|thanks|thank\ you|go\ ahead|looks\ good|lgtm|correct|exactly|right|done|nah|nope|yep|yup|continue)[\.\!\?]?$ ]]; then
  exit 0
fi

# ── Skip slash commands — skills handle their own context ─────────────────────
if [[ "$prompt_lower" =~ ^/ ]]; then
  exit 0
fi

# ── Block vague one-word prompts ──────────────────────────────────────────────
if [[ "$prompt_lower" =~ ^(fix|help|debug|check|look|see|run|do|try)[[:space:]]*$ ]]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n '{"decision": "block", "reason": "Prompt too vague - specify what file/feature/error needs attention"}'
  fi
  exit 0
fi

# ── Quality gate warning (not block) ─────────────────────────────────────────
quality_gate_hint=""
if [[ -f "$GATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
  gate_json=$(cat "$GATE_FILE" 2>/dev/null)
  gate_status=$(jq -r '.status // ""' <<< "$gate_json" 2>/dev/null)
  if [[ "$gate_status" == "failing" ]]; then
    if ! [[ "$prompt_lower" =~ (fix|resolve|error|warning|test|lint|check|type) ]]; then
      reason=$(jq -r '.reason // "Unknown quality failure"' <<< "$gate_json" 2>/dev/null)
      quality_gate_hint="Quality gate failing: $reason. Prefer fixing before unrelated work."
    fi
  fi
fi

# ── Build context parts ──────────────────────────────────────────────────────
# Token-budget rule: every part below must be opt-in via prompt content.
# We do NOT re-inject SessionStart material (branch, gates, recall protocol)
# on every prompt — that duplicates context already in the session.

HAS_ASTGREP="$(detect_ast_grep)"
if ! claudness_enabled skills ast-grep; then
  HAS_ASTGREP=""
fi

# Word-boundary helpers — bash extended regex has no `\b`. WB/WE wrap each
# alternation so e.g. `impl` does NOT match `implement` and `move` does NOT
# match `remove`. Also dropped overly short tokens that no boundary trick
# can rescue: `impl` (vs implement), `ast` (vs fast/past/last), `drop`
# (vs dropdown). Inflected forms (tested, fixing) won't match — users
# typically write the base verb in a directive prompt, and silence is
# safer than the wrong hint.
WB='(^|[^a-z])'
WE='([^a-z]|$)'

# 1. Memory recall hint — only when prompt explicitly invites recall.
recall=""
if [[ "$prompt_lower" =~ ${WB}(remember|recall|what\ did|previously|earlier|engram|architecture|how\ does|where\ is|file-map|prior\ decision|history)${WE} ]]; then
  case "$(claudness_engram_state)" in
    available)
      recall="Recall first: \`mod.sh engram search\` before reading files."
      ;;
    missing)
      recall="WARN: engram CLI not installed — persistent memory recall disabled."
      ;;
  esac
fi

# 2. Intent hint — at most ONE. Most-specific pattern wins.
intent=""
if [[ "$prompt_lower" =~ ${WB}(pattern|struct|trait|interface|all\ functions|all\ methods|every\ function|every\ method|syntax|code\ structure|signature|return\ type|where\ clause|lifetime|closure|macro|decorator|annotation)${WE} ]]; then
  if [ "$HAS_ASTGREP" = "ast-grep" ]; then
    intent="Structural pattern: use \`ast-grep run --pattern\` (not Grep)."
  else
    intent="WARN: ast-grep not installed — install via brew/cargo for structural matching."
  fi
elif [[ "$prompt_lower" =~ ${WB}(rename|move|extract|split)${WE} ]]; then
  intent="Rename: find all refs (ast-grep + Grep on configs) before rewriting."
elif [[ "$prompt_lower" =~ ${WB}(test|spec|coverage)${WE} ]]; then
  intent="Tests: real-world data only, NO mocks."
elif [[ "$prompt_lower" =~ ${WB}(fix|debug|error|bug|issue)${WE} ]]; then
  intent="Fix in code. Never suppress with disable comments."
elif [[ "$prompt_lower" =~ ${WB}(delete|remove|clean\ up)${WE} ]]; then
  intent="Verify no deps before removing."
elif [[ "$prompt_lower" =~ ${WB}(review|audit)${WE} ]]; then
  intent="Review: forbidden syntax, quality gates, test coverage."
fi

# 3. Per-project context hook — opt-in. Project may emit any string.
project_ctx=""
if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/context.sh" ]; then
  # shellcheck disable=SC1091  # path is project-specific; sourced only if present
  project_ctx=$(PROMPT="$prompt" bash "$PROJECT_ROOT/.claude/context.sh" 2>/dev/null || true)
fi

# ── Combine and output ───────────────────────────────────────────────────────
parts=()
[[ -n "$recall" ]] && parts+=("$recall")
[[ -n "$intent" ]] && parts+=("$intent")
[[ -n "$project_ctx" ]] && parts+=("$project_ctx")
[[ -n "$quality_gate_hint" ]] && parts+=("$quality_gate_hint")

# Join parts with " | "
context=""
if [[ ${#parts[@]} -gt 0 ]]; then
  context="${parts[0]}"
  for part in "${parts[@]:1}"; do
    context="$context | $part"
  done
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$context" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": $ctx
    }
  }'
fi

exit 0

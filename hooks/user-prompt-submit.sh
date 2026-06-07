#!/usr/bin/env bash
# UserPromptSubmit hook
# Validates prompts, injects optional per-project context, git context, intent hints.
# Project-agnostic: no project literals. Per-project hints opt-in via $root/.claude/context.sh.

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/detect.sh
. "$HOOK_DIR/lib/detect.sh"

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

# 1. Memory recall — only when engram CLI is installed. Warn (once per prompt) otherwise.
HAS_ENGRAM="$(detect_engram)"
HAS_ASTGREP="$(detect_ast_grep)"

if [ "$HAS_ENGRAM" = "engram" ]; then
  recall="MANDATORY: $(cat "$HOOK_DIR/docs/vector-helper-recall.md" 2>/dev/null || echo "Recall prior context (engram/memory) before exploring.")"
else
  recall="WARN: engram CLI not installed — persistent memory recall disabled. Install to enable: https://github.com/orgs/Falconiere/repositories?q=engram"
fi

# 2. Git branch + dirty state (with file count)
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

# 3. Intent-specific hints (accumulate — multiple can match) — generic only
hints=()

if [[ "$prompt_lower" =~ (test|spec|coverage) ]]; then
  hints+=("Tests: real-world data only, NO mocks.")
fi
if [[ "$prompt_lower" =~ (fix|debug|error|bug|issue) ]]; then
  hints+=("Fix in code directly, never suppress with disable comments.")
fi
if [[ "$prompt_lower" =~ (commit|push|[[:space:]]pr[[:space:]]|pull.?request) ]]; then
  hints+=("Never run git push. PR prep only. Verify diff covers only expected scope before committing.")
fi
if [[ "$prompt_lower" =~ (explore|find|understand|where|how\ does|trace|architecture|what\ does|who\ calls|caller|flow|search|look\ for|locate|what\ is|change|modify|update|move|rename|refactor|fix|debug|implement|add|create|build|write|delete|remove) ]]; then
  if [ "$HAS_ASTGREP" = "ast-grep" ]; then
    hints+=("Search hierarchy: ast-grep FIRST for structural patterns on code files. Grep for exact literals on non-code files. Glob for file finding only.")
  else
    hints+=("Search hierarchy: Grep for exact literals on code/non-code files. Glob for file finding only. (ast-grep not installed — structural matching disabled.)")
  fi
fi
if [[ "$prompt_lower" =~ (rename|move|extract|split) ]]; then
  if [ "$HAS_ASTGREP" = "ast-grep" ]; then
    hints+=("Rename safely: find all references first (ast-grep + Grep on non-code configs), then rewrite.")
  else
    hints+=("Rename safely: find all references first (Grep across codebase + configs), then rewrite.")
  fi
fi
if [[ "$prompt_lower" =~ (pattern|struct|impl|trait|interface|all\ functions|all\ methods|all\ types|every\ function|every\ method|ast|syntax|code\ structure|derive|enum|generic|signature|return\ type|parameter|argument|where\ clause|lifetime|closure|macro|decorator|annotation|component|hook|provider|module|inject) ]]; then
  if [ "$HAS_ASTGREP" = "ast-grep" ]; then
    hints+=("ast-grep MANDATORY: use for structural AST pattern matching. \`ast-grep run --pattern 'pattern' --lang <lang> .\` NEVER use Grep/rg for structural code patterns.")
  else
    hints+=("WARN: ast-grep not installed — structural pattern matching unavailable. Install via \`cargo install ast-grep\` or \`brew install ast-grep\`. Fallback: use Grep with strict regex, expect false positives.")
  fi
fi
if [[ "$prompt_lower" =~ (review|check\ (this|my|the)|look\ at) ]]; then
  hints+=("Review against project rules. Check forbidden syntax, quality gates, test coverage.")
fi
if [[ "$prompt_lower" =~ (explain|walk\ me|how\ does|why\ does|what\ is) ]]; then
  hints+=("Tailor depth to user expertise level.")
fi
if [[ "$prompt_lower" =~ (delete|remove|drop|clean\ up) ]]; then
  hints+=("Verify nothing depends on target before removing.")
fi

# Join hints
intent=""
if [[ ${#hints[@]} -gt 0 ]]; then
  intent=$(printf '%s ' "${hints[@]}")
fi

# 4. Per-project context hook — opt-in. Project may emit any string.
project_ctx=""
if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/context.sh" ]; then
  # shellcheck disable=SC1091  # path is project-specific; sourced only if present
  project_ctx=$(PROMPT="$prompt" bash "$PROJECT_ROOT/.claude/context.sh" 2>/dev/null || true)
fi

# ── Combine and output ───────────────────────────────────────────────────────
parts=("$recall")
[[ -n "$git_ctx" ]] && parts+=("$git_ctx")
[[ -n "$intent" ]] && parts+=("$intent")
[[ -n "$project_ctx" ]] && parts+=("$project_ctx")
[[ -n "$quality_gate_hint" ]] && parts+=("$quality_gate_hint")

# Join parts with " | "
context="${parts[0]}"
for part in "${parts[@]:1}"; do
  context="$context | $part"
done

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$context" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": $ctx
    }
  }'
fi

exit 0

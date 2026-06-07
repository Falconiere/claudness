#!/bin/bash
# UserPromptSubmit hook
# Validates prompts, injects engram recall + git context + intent hints

input=$(cat)
prompt=$(jq -r '.prompt // ""' <<< "$input" 2>/dev/null || echo "")

[[ -z "$prompt" ]] && exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GATE_FILE="$PROJECT_ROOT/.claude/tmp/quality-gate-status.json"
prompt_lower=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')

# ── Skip trivial prompts (confirmations, short replies) ───────────────────────
if [[ "$prompt_lower" =~ ^(y|n|yes|no|ok|sure|thanks|thank you|go ahead|looks good|lgtm|correct|exactly|right|done|nah|nope|yep|yup|stop caveman|normal mode|continue)[\.\!\?]?$ ]]; then
  exit 0
fi

# ── Skip slash commands — skills handle their own context ─────────────────────
if [[ "$prompt_lower" =~ ^/ ]]; then
  exit 0
fi

# ── Block vague one-word prompts ──────────────────────────────────────────────
if [[ "$prompt_lower" =~ ^(fix|help|debug|check|look|see|run|do|try)[[:space:]]*$ ]]; then
  jq -n '{"decision": "block", "reason": "Prompt too vague - specify what file/feature/error needs attention"}'
  exit 0
fi

# ── Quality gate warning (not block) ─────────────────────────────────────────
quality_gate_hint=""
if [[ -f "$GATE_FILE" ]]; then
  gate_json=$(cat "$GATE_FILE" 2>/dev/null)
  gate_status=$(jq -r '.status // ""' <<< "$gate_json" 2>/dev/null)
  if [[ "$gate_status" == "failing" ]]; then
    if ! [[ "$prompt_lower" =~ (fix|resolve|error|warning|test|lint|check|type|clippy|ts:check|rust:check) ]]; then
      reason=$(jq -r '.reason // "Unknown quality failure"' <<< "$gate_json" 2>/dev/null)
      quality_gate_hint="Quality gate failing: $reason. Prefer fixing before unrelated work."
    fi
  fi
fi

# ── Build context parts ──────────────────────────────────────────────────────

# 1. Memory recall
recall="MANDATORY: $(cat "$(dirname "$0")/docs/vector-helper-recall.md" 2>/dev/null || echo "Run .claude/skills/code-intel/scripts/mod.sh engram search before exploring.")"

# 2. Git branch + dirty state (with file count)
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

# 3. Intent-specific hints (accumulate — multiple can match)
hints=()

if [[ "$prompt_lower" =~ (test|spec|coverage) ]]; then
  hints+=("Tests: real-world data only, NO mocks. TS: co-located __tests__/. Rust: tests/ dir.")
fi
if [[ "$prompt_lower" =~ (fix|debug|error|bug|issue) ]]; then
  hints+=("Fix in code directly, NEVER #[allow()] or disable comments. Save learning via mod.sh engram save.")
fi
if [[ "$prompt_lower" =~ (commit|push|[[:space:]]pr[[:space:]]|pull.?request) ]]; then
  hints+=("Never run git push. PR prep only. Verify diff covers only expected scope before committing.")
fi
if [[ "$prompt_lower" =~ (refactor|optimi[sz]e|improve|simplif) ]]; then
  hints+=("Max 3% duplication (jscpd). No #[allow()] or #[expect()] in Rust. Save decisions via mod.sh engram save.")
fi
if [[ "$prompt_lower" =~ (implement|add|create|build|write) ]]; then
  hints+=("ZERO errors/warnings, type safe. Max 3% duplication. No #[allow()] or #[expect()] in Rust.")
fi
if [[ "$prompt_lower" =~ (explore|find|understand|where|how\ does|trace|architecture|what\ does|who\ calls|caller|flow|search|look\ for|locate|what\ is|change|modify|update|move|rename|refactor|fix|debug|implement|add|create|build|write|delete|remove) ]]; then
  hints+=("Search hierarchy: ast-grep FIRST for structural patterns on code files. Grep for exact literals on non-code files (*.toml, *.md, *.yaml). Glob for file finding only.")
fi
if [[ "$prompt_lower" =~ (rename|move|extract|split) ]]; then
  hints+=("Rename safely: find all references first (ast-grep + Grep on non-code configs), then rewrite. Verify nothing depends on target.")
fi
if [[ "$prompt_lower" =~ (pattern|struct|impl|trait|interface|all\ functions|all\ methods|all\ types|every\ function|every\ method|ast|syntax|code\ structure|derive|enum|generic|signature|return\ type|parameter|argument|where\ clause|lifetime|closure|macro|decorator|annotation|component|hook|provider|module|inject) ]]; then
  hints+=("ast-grep MANDATORY: use for structural AST pattern matching. \`ast-grep run --pattern 'pattern' --lang rust/typescript .\` NEVER use Grep/rg for structural code patterns.")
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
if [[ "$prompt_lower" =~ (migrat|schema|database|db[[:space:]]) ]]; then
  hints+=("Migrations need --> statement-breakpoint separators for libsql. Test with real DB.")
fi

# Join hints
intent=""
if [[ ${#hints[@]} -gt 0 ]]; then
  intent=$(printf '%s ' "${hints[@]}")
fi

# ── Combine and output ───────────────────────────────────────────────────────
parts=("$recall")
[[ -n "$git_ctx" ]] && parts+=("$git_ctx")
[[ -n "$intent" ]] && parts+=("$intent")
[[ -n "$quality_gate_hint" ]] && parts+=("$quality_gate_hint")

# Join parts with " | "
context="${parts[0]}"
for part in "${parts[@]:1}"; do
  context="$context | $part"
done

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'

exit 0

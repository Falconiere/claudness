#!/usr/bin/env bash
# Post-tool check: Quality gate state tracking
# Persists global gate state to .claude/tmp/quality-gate-status.json based on
# the exit code of recognized quality/test commands.
#
# Inputs (from parent dispatcher post-tools/mod.sh, via `export`):
#   $tool_name     - name of the tool being invoked
#   $input         - raw JSON payload on stdin
#   $PROJECT_ROOT  - repository root

: "${tool_name:=}"
: "${input:=}"
: "${PROJECT_ROOT:=$(pwd)}"

# Cursor Agent uses tool_name "Shell"; Claude Code uses "Bash".
[[ "$tool_name" != "Bash" && "$tool_name" != "Shell" ]] && exit 0

GATE_DIR="$PROJECT_ROOT/.claude/tmp"
GATE_FILE="$GATE_DIR/quality-gate-status.json"
mkdir -p "$GATE_DIR"

command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
exit_code=$(echo "$input" | jq -r '.tool_response.metadata.exit_code // .tool_response.exit_code // .tool_output.exit_code // empty' 2>/dev/null || echo "")
if [[ -z "$exit_code" || "$exit_code" == "null" ]]; then
  tool_output_raw=$(echo "$input" | jq -r '.tool_output // empty' 2>/dev/null || echo "")
  if [[ -n "$tool_output_raw" ]]; then
    exit_code=$(echo "$tool_output_raw" | jq -r '.exitCode // .exit_code // empty' 2>/dev/null || echo "")
  fi
fi

# Don't overwrite a failing gate owned by a file-level quality hook
# (ts-quality-hook, rust-quality-hook, ...): those hooks manage their own
# lifecycle and only clear the gate when the offending file is re-edited
# clean. A passing quality command here must not mask their failures.
if [[ -f "$GATE_FILE" ]]; then
  current_source=$(jq -r '.source // ""' "$GATE_FILE" 2>/dev/null || echo "")
  current_status=$(jq -r '.status // ""' "$GATE_FILE" 2>/dev/null || echo "")
  if [[ "$current_source" == *-quality-hook && "$current_status" == "failing" ]]; then
    exit 0
  fi
fi

# Quality / test commands that should toggle the global gate:
#   * Project tool wrappers: tools/<name>/{check,test,format}.sh (any project basename)
#   * TS/JS: bun run script aliases, bun test, vitest, jest, tsc, ./scripts/ts-check.sh
#   * Rust: cargo clippy/test/build/nextest
# The wrapper-path regex is project-agnostic; per-project naming lives in the
# wrapper script, not here.
#
# Anchor every alternative at a COMMAND boundary so substring false positives
# (`cat tsconfig.json` → `tsc`, `vitests-helper` → `vitest`) no longer flip the
# gate. Unlike quality-gate.sh (which only anchors at start-of-line, inspecting
# the leading command of a push), gate-status must still detect a quality
# command that appears AFTER a shell operator in a compound command
# (`cd crate && cargo test`), so the prefix also matches after a separator.
# The trailing `|` (single pipe) in this alternation is BY DESIGN: a quality
# command after a pipe (`find . | cargo test`) still ran, so it must trigger
# gate registration. Do not drop it. (Locked in by gate-status.bats.)
GATE_TRIGGER_PREFIX='(^|[[:space:]]|&&|\|\||;|\|)[[:space:]]*'
GATE_TRIGGER_SUFFIX='([[:space:]]|$|&&|\|\||;|\|)'
GATE_TRIGGER_ALTERNATION='tools/[A-Za-z0-9_.-]+/(check|test|format)\.sh|bun run (check|check:fix|check:duplication|ts:check|ts:check:fix|rust:check|rust:test|check-types|lint|lint:fix|format|format:check|format:fix|build|test)|bun test|vitest|jest|tsc|\./scripts/ts-check\.sh|cargo (clippy|test|build|nextest)'
if ! echo "$command" | grep -qE "${GATE_TRIGGER_PREFIX}(${GATE_TRIGGER_ALTERNATION})${GATE_TRIGGER_SUFFIX}"; then
  exit 0
fi

if [[ "$exit_code" =~ ^[0-9]+$ && "$exit_code" -ne 0 ]]; then
  jq -n \
    --arg status "failing" \
    --arg reason "Quality command failed: $command (exit $exit_code)" \
    --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      status: $status,
      reason: $reason,
      source: "gate-status-hook",
      updatedAt: $updatedAt
    }' > "$GATE_FILE"

  jq -n --arg ctx "Global quality gate failing. Fix all errors/warnings/tests before new tasks.\nFailed: $command (exit $exit_code)" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $ctx
    }
  }'
  exit 0
fi

if [[ "$exit_code" == "0" ]]; then
  jq -n \
    --arg status "passing" \
    --arg source "$command" \
    --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      status: $status,
      source: $source,
      updatedAt: $updatedAt
    }' > "$GATE_FILE"
fi

exit 0

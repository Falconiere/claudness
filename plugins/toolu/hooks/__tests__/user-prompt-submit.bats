#!/usr/bin/env bats
# Tests for hooks/user-prompt-submit.sh — must remain project-agnostic.

HOOK="${BATS_TEST_DIRNAME}/../user-prompt-submit.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

build_input() {
  jq -n --arg p "$1" '{prompt: $p}'
}

@test "user-prompt-submit: runs without context.sh present" {
  payload=$(build_input "implement a new feature for the dashboard")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
}

@test "user-prompt-submit: sources .claude/context.sh when present" {
  mkdir -p .claude
  cat > .claude/context.sh <<'CTX'
#!/usr/bin/env bash
echo "CUSTOM_PROJECT_CONTEXT_MARKER"
CTX
  chmod +x .claude/context.sh
  payload=$(build_input "implement a new feature")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUSTOM_PROJECT_CONTEXT_MARKER"
}

@test "user-prompt-submit: output does not mention yamless or routo" {
  payload=$(build_input "refactor the engine module")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}

@test "user-prompt-submit: trivial prompt exits without output" {
  payload=$(build_input "yes")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "user-prompt-submit: no recall hint when prompt does not invite recall" {
  payload=$(build_input "implement a new dashboard widget")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'Recall first'
  ! echo "$output" | grep -q 'comemory search'
}

@test "user-prompt-submit: recall hint NOT emitted for 'paste' (substring of past)" {
  payload=$(build_input "paste this snippet at the top of the file")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'Recall first'
  ! echo "$output" | grep -q 'comemory search'
}

@test "user-prompt-submit: recall hint emitted when prompt mentions architecture" {
  payload=$(build_input "explain the architecture of the auth module")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  # Recall hint only when comemory is available; warning when missing.
  # Either way the response must mention comemory or a warn, not be silent.
  echo "$output" | grep -qE 'comemory|Recall first|WARN'
}

@test "user-prompt-submit: emits at most one intent hint per prompt" {
  # Prompt matches multiple regex categories (fix + test + delete + review).
  payload=$(build_input "fix and remove the failing test review the code")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  # Count hint markers; should be 0 or 1, never more.
  count=0
  echo "$ctx" | grep -q 'Fix in code'       && count=$((count+1))
  echo "$ctx" | grep -q 'real-world data'   && count=$((count+1))
  echo "$ctx" | grep -q 'Verify no deps'    && count=$((count+1))
  echo "$ctx" | grep -q 'Review: forbidden' && count=$((count+1))
  echo "$ctx" | grep -q 'Structural pattern' && count=$((count+1))
  echo "$ctx" | grep -q 'Rename:'           && count=$((count+1))
  [ "$count" -le 1 ]
}

@test "user-prompt-submit: 'implement' does NOT trigger structural pattern hint" {
  # Regression: `impl` was an alternation token and matched as substring of
  # `implement`. Dropped from the structural alternation and word-boundary
  # wrapped so this prompt now produces NO intent hint at all.
  payload=$(build_input "implement a new feature")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ! echo "$ctx" | grep -q 'Structural pattern'
  ! echo "$ctx" | grep -q 'ast-grep'
}

@test "user-prompt-submit: 'remove' does NOT trigger rename hint" {
  # Regression: `move` matched as substring of `remove`. Word boundary now
  # gates this; `remove` falls through to the delete branch.
  payload=$(build_input "remove the old helper")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ! echo "$ctx" | grep -q 'Rename:'
  echo "$ctx" | grep -q 'Verify no deps'
}

@test "user-prompt-submit: 'fast' does NOT trigger structural pattern hint" {
  # Regression: `ast` matched as substring of `fast`/`past`/`last`. Dropped
  # entirely from the structural alternation.
  payload=$(build_input "make this loop faster")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ! echo "$ctx" | grep -q 'Structural pattern'
}

@test "user-prompt-submit: 'dropdown' does NOT trigger delete hint" {
  # Regression: `drop` matched as substring of `dropdown`. Dropped from the
  # delete alternation.
  payload=$(build_input "create a dropdown menu component")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ! echo "$ctx" | grep -q 'Verify no deps'
}

@test "user-prompt-submit: 'preview' does NOT trigger review hint" {
  # Regression: `review` matched as substring of `preview`. Word boundary
  # now gates this.
  payload=$(build_input "preview the changes")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ! echo "$ctx" | grep -q 'Review: forbidden'
}

write_failing_gate() {
  mkdir -p .claude/tmp
  printf '%s\n' '{"status":"failing","reason":"forced"}' > .claude/tmp/quality-gate-status.json
}

@test "user-prompt-submit: 'prefix' does NOT suppress the failing-gate hint" {
  # Regression: suppression matched `fix` as a substring, so any prompt
  # containing `prefix` silently dropped the quality-gate warning.
  write_failing_gate
  payload=$(build_input "add a prefix to the logger module")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Quality gate failing'
}

@test "user-prompt-submit: 'fix the gate' suppresses the failing-gate hint" {
  write_failing_gate
  payload=$(build_input "fix the gate so the build passes")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'Quality gate failing'
}

@test "user-prompt-submit: omits branch/git context (moved to SessionStart)" {
  payload=$(build_input "implement a new feature")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'Branch: .*(clean|uncommitted)'
}

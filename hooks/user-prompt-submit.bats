#!/usr/bin/env bats
# Tests for hooks/user-prompt-submit.sh — must remain project-agnostic.

HOOK="${BATS_TEST_DIRNAME}/user-prompt-submit.sh"

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
  ! echo "$output" | grep -q 'engram search'
}

@test "user-prompt-submit: recall hint emitted when prompt mentions architecture" {
  payload=$(build_input "explain the architecture of the auth module")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  # Recall hint only when engram is available; warning when missing.
  # Either way the response must mention engram or a warn, not be silent.
  echo "$output" | grep -qE 'engram|Recall first|WARN'
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

@test "user-prompt-submit: omits branch/git context (moved to SessionStart)" {
  payload=$(build_input "implement a new feature")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'Branch: .*(clean|uncommitted)'
}

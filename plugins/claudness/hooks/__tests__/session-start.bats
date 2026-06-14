#!/usr/bin/env bats
# Tests for hooks/session-start.sh — must remain project-agnostic.

HOOK="${BATS_TEST_DIRNAME}/../session-start.sh"

setup() {
  TMP=$(mktemp -d)
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "session-start: runs without error in an empty git repo" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
}

@test "session-start: does not print project-specific yamless/routo literals" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}

@test "session-start: runs without error outside any git repo" {
  cd /tmp
  run bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
}

@test "session-start: orphan sweep removes the legacy statusline symlink" {
  cd "$TMP"
  mkdir -p "$TMP/cfg/claudness"
  ln -s "$TMP/cfg/claudness/gone.sh" "$TMP/cfg/claudness/statusline.sh"
  run env CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/cfg/claudness/statusline.sh" ]
  [ ! -e "$TMP/cfg/claudness/statusline.sh" ]
}

@test "session-start: orphan sweep never deletes a real statusline file" {
  cd "$TMP"
  mkdir -p "$TMP/cfg/claudness"
  printf 'user-owned' > "$TMP/cfg/claudness/statusline.sh"
  run env CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  [ -f "$TMP/cfg/claudness/statusline.sh" ]
  [ "$(cat "$TMP/cfg/claudness/statusline.sh")" = "user-owned" ]
}

@test "session-start: emits per-toolchain doc only when toolchain detected" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  # No tsconfig, no Cargo.toml — neither block should appear.
  run bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'TypeScript notes'
  ! echo "$output" | grep -q 'Rust notes'
}

@test "session-start: toolchain block stays off by default even when detected" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  # Track a tsconfig so detect_ts returns "ts", but omit CLAUDNESS_VERBOSE.
  echo '{}' > tsconfig.json
  git -c user.email=t@t -c user.name=t add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m ts
  unset CLAUDNESS_VERBOSE
  run bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'TypeScript notes'
}

@test "session-start: CLAUDNESS_VERBOSE=0 keeps toolchain block off" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  echo '{}' > tsconfig.json
  git -c user.email=t@t -c user.name=t add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m ts
  export CLAUDNESS_VERBOSE=0
  run bash "$HOOK" <<<'{"source":"startup"}'
  unset CLAUDNESS_VERBOSE
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'TypeScript notes'
}

@test "session-start: source=compact triggers compact branch with post-compaction doc" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.systemMessage')" = "Context compacted" ]
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'Recover memories'
}

@test "session-start: source=resume triggers resume branch" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"source":"resume"}'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.systemMessage')" = "Session resumed" ]
}

@test "session-start: project name with sed metacharacters renders safely" {
  mkdir -p "$TMP/we|ird&name"
  cd "$TMP/we|ird&name"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -re '.hookSpecificOutput.additionalContext')
  # Exact substitution: name appears verbatim in the rendered doc header,
  # without literal surrounding quotes and without leftover tokens.
  echo "$ctx" | grep -qF 'Session Protocol — we|ird&name'
  ! echo "$ctx" | grep -qF '"we|ird&name"'
  ! echo "$ctx" | grep -qF '{{project_name}}'
}

@test "session-start: rendering is exact under stock /bin/bash (3.2 on macOS)" {
  mkdir -p "$TMP/we|ird&name"
  cd "$TMP/we|ird&name"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run /bin/bash "$HOOK" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  ctx=$(echo "$output" | jq -re '.hookSpecificOutput.additionalContext')
  echo "$ctx" | grep -qF 'Session Protocol — we|ird&name'
  ! echo "$ctx" | grep -qF '"we|ird&name"'
  ! echo "$ctx" | grep -qF '{{project_name}}'
}

@test "session-start: toolchain block emits when CLAUDNESS_VERBOSE=1 and detected" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  echo '{}' > tsconfig.json
  git -c user.email=t@t -c user.name=t add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m ts
  export CLAUDNESS_VERBOSE=1
  run bash "$HOOK" <<<'{"source":"startup"}'
  unset CLAUDNESS_VERBOSE
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'TypeScript notes'
}

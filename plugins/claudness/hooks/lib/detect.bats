#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -m init -q
}

teardown() {
  rm -rf "$TMP"
}

source_lib() {
  # shellcheck disable=SC1091
  . "${BATS_TEST_DIRNAME}/detect.sh"
}

@test "detect_project_root returns git toplevel" {
  source_lib
  run detect_project_root
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "detect_project_name returns basename" {
  source_lib
  run detect_project_name
  [ "$status" -eq 0 ]
  [ "$output" = "$(basename "$(pwd -P)")" ]
}

@test "detect_project_name returns 0 outside a git repo under set -e (fallback survives)" {
  # A bare `[ -n "$root" ] && basename` exits 1 here; under set -e that aborts
  # a caller before its own fallback runs. The helper must exit 0 and print "".
  run bash -c 'set -euo pipefail; . "'"${BATS_TEST_DIRNAME}"'/detect.sh"; cd /tmp
    P="${X:-$(detect_project_name)}"; [ -z "$P" ] && P="unknown"; echo "name=[$P]"'
  [ "$status" -eq 0 ]
  [ "$output" = "name=[unknown]" ]
}

@test "detect_node_pm returns bun when bun.lock present" {
  touch bun.lock
  source_lib
  run detect_node_pm
  [ "$output" = "bun" ]
}

@test "detect_node_pm returns pnpm when pnpm-lock.yaml present" {
  touch pnpm-lock.yaml
  source_lib
  run detect_node_pm
  [ "$output" = "pnpm" ]
}

@test "detect_node_pm returns npm when package-lock.json present" {
  touch package-lock.json
  source_lib
  run detect_node_pm
  [ "$output" = "npm" ]
}

@test "detect_node_pm returns empty when no lock file" {
  source_lib
  run detect_node_pm
  [ -z "$output" ]
}

@test "detect_rust returns rust when Cargo.toml present" {
  touch Cargo.toml
  source_lib
  run detect_rust
  [ "$output" = "rust" ]
}

@test "detect_rust returns empty when no Cargo.toml" {
  source_lib
  run detect_rust
  [ -z "$output" ]
}

@test "detect_ts returns ts when tsconfig.json present" {
  echo '{}' > tsconfig.json
  git add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m tsconfig
  source_lib
  run detect_ts
  [ "$output" = "ts" ]
}

@test "detect_base_branch falls back to main when no remote" {
  source_lib
  run detect_base_branch
  [ "$output" = "main" ]
}

@test "detect_project_root returns empty outside git" {
  cd /tmp
  source_lib
  run detect_project_root
  [ -z "$output" ]
}

@test "to_relative_path strips git toplevel prefix from absolute path" {
  source_lib
  root=$(detect_project_root)
  run to_relative_path "$root/hooks/lib/detect.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "hooks/lib/detect.sh" ]
}

@test "to_relative_path passes through a relative path unchanged" {
  source_lib
  run to_relative_path "hooks/lib/detect.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "hooks/lib/detect.sh" ]
}

@test "to_relative_path passes through an abs path outside the repo unchanged" {
  source_lib
  run to_relative_path "/etc/passwd"
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/passwd" ]
}

@test "to_relative_path on empty input returns empty" {
  source_lib
  run to_relative_path ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "strip_heredocs: <<EOF > /tmp/x body is stripped, trailing command preserved" {
  source_lib
  out=$(printf '%s\n' "cat <<EOF > /tmp/x" "body1" "body2" "EOF" "echo after" | strip_heredocs)
  [[ "$out" == *"cat <<EOF > /tmp/x"* ]]
  [[ "$out" == *"echo after"* ]]
  [[ "$out" != *"body1"* ]]
  [[ "$out" != *"body2"* ]]
}

@test "strip_heredocs: <<-END (tab-indented form) is stripped" {
  source_lib
  out=$(printf '%s\n' "cat <<-END" $'\tbody1' $'\tbody2' $'\tEND' "echo end" | strip_heredocs)
  [[ "$out" == *"cat <<-END"* ]]
  [[ "$out" == *"echo end"* ]]
  [[ "$out" != *"body1"* ]]
}

@test "strip_heredocs: <<DOC alternate delimiter is stripped" {
  source_lib
  out=$(printf '%s\n' "cat <<DOC" "x" "y" "DOC" "echo end" | strip_heredocs)
  [[ "$out" == *"echo end"* ]]
  [[ "$out" != *"^x$"* ]]
  printf '%s\n' "$out" | grep -qxF "x" && return 1
  return 0
}

@test "strip_heredocs: plain command (no heredoc) passes through unchanged" {
  source_lib
  out=$(printf '%s\n' "echo hello" "ls -la" | strip_heredocs)
  [ "$out" = "$(printf '%s\n' "echo hello" "ls -la")" ]
}

@test "strip_heredocs: <<EOF | tee (pipe after heredoc start) strips body" {
  source_lib
  out=$(printf '%s\n' "cat <<EOF | tee /tmp/x" "secret cargo test inside body" "EOF" "echo done" | strip_heredocs)
  [[ "$out" != *"secret cargo test inside body"* ]]
  [[ "$out" == *"echo done"* ]]
}

@test "read_list: missing file returns no output" {
  source_lib
  run read_list "$BATS_TEST_TMPDIR/nope.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "read_list: skips comments and blank lines" {
  source_lib
  f="$BATS_TEST_TMPDIR/list.txt"
  printf '%s\n' "# comment" "" "real-line" "  # indented comment" "another" > "$f"
  run read_list "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' 'real-line' 'another')" ]
}

@test "detect_plugin_installed: echoes spec when registry contains the key" {
  source_lib
  reg="$BATS_TEST_TMPDIR/installed.json"
  printf '%s\n' '{"plugins":{"code-simplifier@claude-plugins-official":[{"scope":"user"}]}}' > "$reg"
  CLAUDE_PLUGINS_REGISTRY="$reg" run detect_plugin_installed "code-simplifier@claude-plugins-official"
  [ "$status" -eq 0 ]
  [ "$output" = "code-simplifier@claude-plugins-official" ]
}

@test "detect_plugin_installed: empty + exit 0 when key absent" {
  source_lib
  reg="$BATS_TEST_TMPDIR/installed.json"
  printf '%s\n' '{"plugins":{"other@marketplace":[]}}' > "$reg"
  CLAUDE_PLUGINS_REGISTRY="$reg" run detect_plugin_installed "code-simplifier@claude-plugins-official"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_plugin_installed: tolerates non-array value (regression for length>0 bug)" {
  source_lib
  reg="$BATS_TEST_TMPDIR/installed.json"
  # Value is a number — prior `.plugins[$s] | length > 0` filter errored;
  # `has($s)` returns true (key is present, regardless of value shape).
  printf '%s\n' '{"plugins":{"caveman@caveman":42}}' > "$reg"
  CLAUDE_PLUGINS_REGISTRY="$reg" run detect_plugin_installed "caveman@caveman"
  [ "$status" -eq 0 ]
  [ "$output" = "caveman@caveman" ]
}

@test "detect_plugin_installed: indeterminate (exit 2) when registry missing" {
  source_lib
  CLAUDE_PLUGINS_REGISTRY="$BATS_TEST_TMPDIR/does-not-exist.json" \
    run detect_plugin_installed "code-simplifier@claude-plugins-official"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "detect_plugin_installed: indeterminate (exit 2) when registry malformed" {
  source_lib
  reg="$BATS_TEST_TMPDIR/installed.json"
  printf '%s\n' 'not json' > "$reg"
  CLAUDE_PLUGINS_REGISTRY="$reg" run detect_plugin_installed "code-simplifier@claude-plugins-official"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "detect_plugin_installed: indeterminate (exit 2) when plugins key wrong type" {
  source_lib
  reg="$BATS_TEST_TMPDIR/installed.json"
  printf '%s\n' '{"plugins":"not-an-object"}' > "$reg"
  CLAUDE_PLUGINS_REGISTRY="$reg" run detect_plugin_installed "code-simplifier@claude-plugins-official"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "detect_plugin_installed: empty spec returns 0 + empty" {
  source_lib
  run detect_plugin_installed ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

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

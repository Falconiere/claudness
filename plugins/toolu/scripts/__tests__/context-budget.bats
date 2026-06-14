#!/usr/bin/env bats
# Unit tests for context-budget.sh — drive the parser/enforcer on real fixture
# files so the guard is verified independent of the live harness docs.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../context-budget.sh"
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX"
}

@test "extract_description reads a single-line description" {
  source "$SCRIPT"
  printf -- '---\nname: x\ndescription: hello there world\n---\n' > "$FIX/single.md"
  run extract_description "$FIX/single.md"
  [ "$status" -eq 0 ]
  [ "$output" = "hello there world" ]
}

@test "extract_description joins a folded (>) block scalar" {
  source "$SCRIPT"
  printf -- '---\nname: x\ndescription: >\n  alpha beta\n  gamma delta\n---\n' > "$FIX/folded.md"
  run extract_description "$FIX/folded.md"
  [ "$status" -eq 0 ]
  [ "$output" = "alpha beta gamma delta" ]
}

@test "extract_description fails on a missing file" {
  source "$SCRIPT"
  run extract_description "$FIX/nope.md"
  [ "$status" -ne 0 ]
}

@test "count_words fails on a missing file" {
  source "$SCRIPT"
  run count_words "$FIX/nope.md"
  [ "$status" -ne 0 ]
}

@test "check_doc flags an over-budget file as RED" {
  source "$SCRIPT"
  ROOT="$FIX"
  mkdir -p "$FIX/d"
  printf 'one two three four five\n' > "$FIX/d/x.md"   # 5 words
  fail=0
  check_doc x d/x.md 3
  [ "$fail" -eq 1 ]
}

@test "check_doc passes an under-budget file" {
  source "$SCRIPT"
  ROOT="$FIX"
  mkdir -p "$FIX/d"
  printf 'one two\n' > "$FIX/d/x.md"   # 2 words
  fail=0
  check_doc x d/x.md 3
  [ "$fail" -eq 0 ]
}

@test "check_doc fails closed when the target file is missing" {
  source "$SCRIPT"
  ROOT="$FIX"
  fail=0
  check_doc gone d/missing.md 9999
  [ "$fail" -eq 1 ]
}

@test "check_skill flags a missing trigger phrase even when under budget" {
  source "$SCRIPT"
  ROOT="$FIX"
  mkdir -p "$FIX/s"
  printf -- '---\nname: s\ndescription: short blurb without the marker\n---\n' > "$FIX/s/SKILL.md"
  fail=0
  check_skill s s/SKILL.md 50 "must keep this"
  [ "$fail" -eq 1 ]
}

@test "check_skill passes when under budget and phrase present" {
  source "$SCRIPT"
  ROOT="$FIX"
  mkdir -p "$FIX/s"
  printf -- '---\nname: s\ndescription: blurb that must keep this marker intact\n---\n' > "$FIX/s/SKILL.md"
  fail=0
  check_skill s s/SKILL.md 50 "must keep this"
  [ "$fail" -eq 0 ]
}

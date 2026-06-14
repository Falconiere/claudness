#!/usr/bin/env bats
# Real-data tests for parse-verdict.sh. The primary fixture (pr31-verdict.txt) is
# the captured real CI review bot comment from PR #31 — no mocks.

PV="${BATS_TEST_DIRNAME}/../parse-verdict.sh"
FIX="${BATS_TEST_DIRNAME}/fixtures"

@test "parse-verdict: PR#31 real comment is complete + approved" {
  out=$(bash "$PV" < "$FIX/pr31-verdict.txt")
  [ "$(jq -r .is_review_comment <<<"$out")" = "true" ]
  [ "$(jq -r .state <<<"$out")" = "complete" ]
  [ "$(jq -r .complete <<<"$out")" = "true" ]
  [ "$(jq -r .verdict <<<"$out")" = "approved" ]
  [ "$(jq -r .verdict_label <<<"$out")" = "agent-merge-approved" ]
}

@test "parse-verdict: PR#31 yields exactly 6 findings, all low" {
  out=$(bash "$PV" < "$FIX/pr31-verdict.txt")
  [ "$(jq '.findings | length' <<<"$out")" -eq 6 ]
  [ "$(jq -r '[.findings[].severity] | unique | join(",")' <<<"$out")" = "low" ]
}

@test "parse-verdict: PR#31 parses path + line + key correctly" {
  out=$(bash "$PV" < "$FIX/pr31-verdict.txt")
  # first finding: session-start.sh line 17
  [ "$(jq -r '.findings[0].path' <<<"$out")" = "plugins/claudness/hooks/session-start.sh" ]
  [ "$(jq -r '.findings[0].line' <<<"$out")" = "17" ]
  # the bats finding has NO line number → null
  [ "$(jq -r '.findings[2].path' <<<"$out")" = "plugins/claudness/hooks/__tests__/session-start.bats" ]
  [ "$(jq -r '.findings[2].line' <<<"$out")" = "null" ]
  # keys are present and unique
  [ "$(jq -r '[.findings[].key] | length' <<<"$out")" -eq 6 ]
  [ "$(jq -r '[.findings[].key] | unique | length' <<<"$out")" -eq 6 ]
}

@test "parse-verdict: keys are stable across runs (deterministic)" {
  a=$(bash "$PV" < "$FIX/pr31-verdict.txt" | jq -c '[.findings[].key]')
  b=$(bash "$PV" < "$FIX/pr31-verdict.txt" | jq -c '[.findings[].key]')
  [ "$a" = "$b" ]
}

@test "parse-verdict: in-progress comment is not complete" {
  out=$(bash "$PV" < "$FIX/in-progress.txt")
  [ "$(jq -r .is_review_comment <<<"$out")" = "true" ]
  [ "$(jq -r .state <<<"$out")" = "in_progress" ]
  [ "$(jq -r .complete <<<"$out")" = "false" ]
}

@test "parse-verdict: comment with markers but no checklist is unknown (degrade)" {
  out=$(bash "$PV" < "$FIX/no-checkbox.txt")
  [ "$(jq -r .is_review_comment <<<"$out")" = "true" ]
  [ "$(jq -r .state <<<"$out")" = "unknown" ]
  [ "$(jq -r .complete <<<"$out")" = "false" ]
}

@test "parse-verdict: non-review / garbage input is not a review comment" {
  out=$(printf 'just a normal human comment, nothing here' | bash "$PV")
  [ "$(jq -r .is_review_comment <<<"$out")" = "false" ]
  [ "$(jq '.findings | length' <<<"$out")" -eq 0 ]
}

@test "parse-verdict: empty input is handled" {
  out=$(printf '' | bash "$PV")
  [ "$(jq -r .is_review_comment <<<"$out")" = "false" ]
}

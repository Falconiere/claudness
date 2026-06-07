#!/usr/bin/env bash
# Pre-tool check: block `git push` until branch has been reviewed.
# Project-agnostic: base branch is detected via detect_base_branch
# (or env-overridden with $PUSH_REVIEW_BASE for tests).
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload (also piped to stdin; this module reads the env var)
#
# State file: .claude/tmp/push-review/<branch-slug>.json
# Override via $STATE_DIR for testing.

# pipefail so a `git diff | git hash-object` failure surfaces; without it,
# an empty diff stream succeeds and yields the well-known empty-blob SHA,
# which a stale state file can cache and reuse across any future empty-diff
# state on the same branch (including post-force-reset).
set -o pipefail

: "${tool_name:=}"
: "${input:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

[[ "$tool_name" != "Bash" ]] && exit 0

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // ""')
cmd_only=$(printf '%s\n' "$command" | strip_heredocs)

echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)git\s+push(\s|$)' || exit 0

_branch_slug() {
  local branch="$1"
  local slug
  slug=$(echo "$branch" | tr '/' '_' | tr -cd 'a-zA-Z0-9_-')
  [[ -z "$slug" ]] && slug="_default"
  echo "$slug"
}

current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
slug=$(_branch_slug "$current_branch")

# Resolve state dir: env override takes precedence; else project-root default.
state_dir=${STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/tmp/push-review}
state_file="$state_dir/${slug}.json"

# Base branch: env override > detect_base_branch.
base_branch="${PUSH_REVIEW_BASE:-$(detect_base_branch)}"

# Verify base branch exists locally.
if ! git rev-parse --verify --quiet "$base_branch" >/dev/null; then
  jq -n --arg base "$base_branch" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("base branch '\''" + $base + "'\'' not found locally; run `git fetch origin " + $base + ":" + $base + "`")
    }
  }'
  exit 0
fi

# Detect detached HEAD (current_branch == "HEAD" from rev-parse).
if [[ "$current_branch" == "HEAD" || -z "$current_branch" ]]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "detached HEAD — checkout a branch before push"
    }
  }'
  exit 0
fi

# Pushing the base branch itself (e.g. fast-forwarded main after a local merge)
# is not a feature-review scenario — `<base>...<base>` has empty diff by
# definition. Allow without state-file gate.
if [[ "$current_branch" == "$base_branch" ]]; then
  exit 0
fi

# Compute branch diff SHA (content-addressed, survives amend/rebase).
# Well-known git empty-blob SHA — the value `git hash-object --stdin` produces
# for an empty stream. We refuse to cache or trust this value: a state file
# bearing it would be reusable across any future empty-diff state on the same
# branch (e.g. after a force reset wipes commits).
EMPTY_BLOB_SHA="e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"

current_diff_sha=$(git diff --no-color "${base_branch}...HEAD" 2>/dev/null | git hash-object --stdin 2>/dev/null || echo "")
if [[ -z "$current_diff_sha" ]]; then
  # git diff failed (disk full, etc). Allow push; underlying push will surface real failure.
  echo "push-review: git diff ${base_branch}...HEAD failed; allowing push to surface real error" >&2
  exit 0
fi

if [[ "$current_diff_sha" == "$EMPTY_BLOB_SHA" ]]; then
  # Empty diff against base: nothing to review and nothing to push. Treat as
  # a sentinel that NEVER satisfies the cache check, then deny the push so
  # the user is forced to confirm intent rather than push a no-op.
  current_diff_sha="empty-diff"
  jq -n --arg base "$base_branch" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "Refusing to push: diff against " + $base + " is empty. " +
        "Either no commits diverged from base, or the branch was force-reset. " +
        "Verify intent before pushing."
      )
    }
  }'
  exit 0
fi

# State file gate.
if [[ ! -f "$state_file" ]]; then
  jq -n --arg sha "$current_diff_sha" --arg base "$base_branch" --arg file "$state_file" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "Code review required before push.\n\n" +
        "Diff SHA: " + $sha + "\n" +
        "Base branch: " + $base + "\n" +
        "State file: " + $file + " (missing)\n\n" +
        "Run all three reviewers in parallel (single message, three Agent tool calls) against `git diff " + $base + "...HEAD`:\n" +
        "  1. Spawn `code-simplifier:code-simplifier` on the diff.\n" +
        "  2. Spawn `caveman:cavecrew-reviewer` on the diff.\n" +
        "  3. Invoke the `code-review` skill with args `xhigh --fix` (auto-applies findings to the working tree).\n" +
        "  4. Merge all findings from the three reviewers. Apply any not auto-fixed by `code-review --fix`.\n" +
        "  5. Stage and commit the fixes (diff SHA will change after each round).\n" +
        "  6. Re-run all three reviewers on the new diff. Loop until every reviewer returns zero findings.\n" +
        "  7. atomically write state file at " + $file + " (write to '\''<file>.tmp'\'' then mv) with schema:\n" +
        "     { version: 1, branch, diff_sha, base_branch, reviewed_at, reviewers, findings_count, findings }\n" +
        "     `reviewers` MUST be [\"code-simplifier\", \"caveman:cavecrew-reviewer\", \"code-review:xhigh\"] and `findings_count` MUST be 0.\n" +
        "  8. Retry git push."
      )
    }
  }'
  exit 0
fi

# Validate state file: version, diff_sha, findings_count.
state_version=$(jq -r '.version // ""' "$state_file" 2>/dev/null || echo "")
state_sha=$(jq -r '.diff_sha // ""' "$state_file" 2>/dev/null || echo "")
state_findings=$(jq -r '.findings_count // ""' "$state_file" 2>/dev/null || echo "")

if [[ "$state_version" != "1" || -z "$state_sha" || -z "$state_findings" ]]; then
  jq -n --arg file "$state_file" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("state file corrupted at " + $file + "; delete and re-review")
    }
  }'
  exit 0
fi

if [[ "$state_sha" != "$current_diff_sha" ]]; then
  jq -n --arg sha "$current_diff_sha" --arg file "$state_file" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "Code review required: diff changed since review.\n" +
        "Current diff SHA: " + $sha + "\n" +
        "State file: " + $file + " (stale)\n" +
        "Re-run reviewers on the new diff and rewrite the state file."
      )
    }
  }'
  exit 0
fi

if [[ "$state_findings" != "0" ]]; then
  jq -n --arg count "$state_findings" --arg file "$state_file" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": (
        "Code review has open findings (" + $count + ").\n" +
        "State file: " + $file + "\n" +
        "Address every finding (any finding blocks). Re-commit. Re-run reviewers. Rewrite state file with findings_count=0."
      )
    }
  }'
  exit 0
fi

# All gates pass: allow push.
exit 0

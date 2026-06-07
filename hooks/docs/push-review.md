# push-review hook

PreToolUse hook on `Bash(git push)`. Blocks pushes until a clean code review is recorded in `.claude/tmp/push-review/<branch-slug>.json`.

## Flow

1. Agent runs `git push`.
2. Hook computes `git diff development...HEAD | git hash-object --stdin`.
3. Hook reads `.claude/tmp/push-review/<branch-slug>.json`.
4. If the state file is missing, has a stale `diff_sha`, or has `findings_count > 0` → DENY with instructions.
5. Agent runs three reviewers in parallel against the diff:
   - `code-simplifier:code-simplifier`
   - `caveman:cavecrew-reviewer`
   - `code-review` skill invoked with `xhigh --fix` (auto-applies findings to the working tree)
6. Agent merges findings from all three; commits any auto-applied fixes plus manual fixes for the rest.
7. Agent re-runs all three reviewers on the new diff and loops until every reviewer returns zero findings.
8. Agent writes state file atomically (`<file>.tmp` then `mv`) with `findings_count: 0` and the new SHA.
9. Agent retries `git push` → hook allows.

## State schema

```json
{
  "version": 1,
  "branch": "feat/x",
  "diff_sha": "<git-hash-object output>",
  "base_branch": "development",
  "reviewed_at": "<iso8601>",
  "reviewers": ["code-simplifier:code-simplifier", "caveman:cavecrew-reviewer", "code-review:xhigh"],
  "findings_count": 0,
  "findings": []
}
```

## Failure modes the hook denies

- State file missing.
- State file SHA != current diff SHA (diff changed).
- `findings_count > 0`.
- Corrupted JSON or schema drift (wrong `version`, missing `diff_sha`/`findings_count`).
- Base branch `development` not present locally.
- Detached HEAD.

## Tests

`.claude/hooks/pre-tools/modules/__tests__/push-review.bats` — run with:

```bash
bats .claude/hooks/pre-tools/modules/__tests__/push-review.bats
```

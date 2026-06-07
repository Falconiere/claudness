# push-review hook

PreToolUse hook on `Bash(git push)`. Blocks pushes until a clean code review is recorded in `.claude/tmp/push-review/<branch-slug>.json`.

## Flow

1. Agent runs `git push`.
2. Hook computes `git diff development...HEAD | git hash-object --stdin`.
3. Hook reads `.claude/tmp/push-review/<branch-slug>.json`.
4. If the state file is missing, has a stale `diff_sha`, or has `findings_count > 0` → DENY with instructions.
5. Agent runs four reviewers against the diff:
   - `caveman:cavecrew-reviewer` (subagent, spawned via the Agent tool)
   - `simplify` skill (auto-applies simplification fixes to the working tree)
   - `code-review` skill invoked with `xhigh --fix` (auto-applies findings to the working tree)
   - `security-review` skill (reports security findings on pending changes; no auto-fix)
6. Agent merges findings from all four; commits the auto-applied fixes plus any cavecrew/security finding the two auto-fix skills didn't cover.
7. Agent re-runs all four reviewers on the new diff and loops until every reviewer returns zero findings.
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
  "reviewers": ["simplify", "caveman:cavecrew-reviewer", "code-review:xhigh", "security-review"],
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

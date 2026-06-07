# push-review hook

PreToolUse hook on `Bash(git push)`. Blocks pushes until a clean code review is recorded in `.claude/tmp/push-review/<branch-slug>.json`.

## Flow

1. Agent runs `git push`.
2. Hook computes `git diff development...HEAD | git hash-object --stdin`.
3. Hook reads `.claude/tmp/push-review/<branch-slug>.json`.
4. If the state file is missing, has a stale `diff_sha`, or has `findings_count > 0` → DENY with instructions.
5. Agent spawns `caveman:cavecrew-reviewer` + `code-simplifier:code-simplifier` in parallel against the diff.
6. Agent merges findings, writes state file atomically (`<file>.tmp` then `mv`).
7. Agent fixes any findings, re-runs reviewers, re-writes state file with new SHA + `findings_count: 0`.
8. Agent retries `git push` → hook allows.

## State schema

```json
{
  "version": 1,
  "branch": "feat/x",
  "diff_sha": "<git-hash-object output>",
  "base_branch": "development",
  "reviewed_at": "<iso8601>",
  "reviewers": ["caveman:cavecrew-reviewer", "code-simplifier"],
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

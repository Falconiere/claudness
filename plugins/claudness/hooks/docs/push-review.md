# push-review hook

PreToolUse hook on `Bash(git push)`. Blocks pushes until a clean code review is recorded in `.claude/tmp/push-review/<branch-slug>.json`.

## Flow

1. Agent runs `git push`.
2. Hook computes `git diff <base>...HEAD | git hash-object --stdin`, where `<base>` is resolved dynamically via `detect_base_branch` (origin/HEAD, falling back to `main`; `$PUSH_REVIEW_BASE` overrides for tests).
3. Hook reads `.claude/tmp/push-review/<branch-slug>.json`.
4. If the state file is missing, has a stale `diff_sha`, or has `findings_count > 0` → DENY with instructions.
5. Agent runs two reviewers against the diff **sequentially** (code-simplifier first):
   1. `code-simplifier` (subagent from the `code-simplifier@claude-plugins-official` plugin — declared in `plugin.json` `dependencies`). Spawn via the Agent tool, apply its rewrites to the working tree, and commit.
   2. `caveman:cavecrew-reviewer` (subagent from the `caveman@caveman` plugin — declared in `plugin.json` `dependencies`). Review the post-simplification diff and apply findings.
6. Re-run both reviewers on the new diff and loop until both return zero findings.
7. Agent writes state file atomically (`<file>.tmp` then `mv`) with `findings_count: 0` and the new SHA.
8. Agent retries `git push` → hook allows.

## State schema

```json
{
  "version": 1,
  "branch": "feat/x",
  "diff_sha": "<git-hash-object output>",
  "base_branch": "main",
  "reviewed_at": "<iso8601>",
  "reviewers": ["code-simplifier", "caveman:cavecrew-reviewer"],
  "findings_count": 0,
  "findings": [],
  "review_round": 1
}
```

`review_round` starts at 1 and must bump by 1 on every rewrite of the state
file (each fix→re-review loop). The hook treats a missing field as round 1
for backward compatibility and denies with an escalation message once the
round exceeds 3 (`MAX_ROUNDS`), so the loop cannot run unbounded.

## Security posture

`security-review` is **no longer enforced** by this gate (dropped in v1.2.0 per project decision). For diffs that touch authentication, secret handling, request parsing, or other security-sensitive code, run `/security-review` manually before push. The gate's two required reviewers (`code-simplifier`, `caveman:cavecrew-reviewer`) catch correctness and clarity bugs but make no security guarantees.

## Failure modes the hook denies

- State file missing.
- State file SHA != current diff SHA (diff changed).
- `findings_count > 0`.
- Corrupted JSON or schema drift (wrong `version`, missing `diff_sha`/`findings_count`).
- `reviewers` missing any required entry.
- `review_round` exceeds the max (3) — escalation deny.
- Detected base branch not present locally.
- Detached HEAD.
- Empty diff against base (no-op push or force-reset branch).

## Tests

`hooks/pre-tools/modules/__tests__/push-review.bats` — run from the repo root with:

```bash
bats plugins/claudness/hooks/pre-tools/modules/__tests__/push-review.bats
```

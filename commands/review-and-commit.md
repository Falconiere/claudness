# Review, Fix & Commit Completed Work
Run AFTER all tasks are completed. Reviews changes on the current branch, fixes gaps, and commits. Does NOT merge. Does NOT push.

## 1. Identify scope
- Current branch: `git rev-parse --abbrev-ref HEAD`.
- Committed changes: `git log development..HEAD --oneline` + `git diff development...HEAD --stat`.
- Uncommitted changes: `git status --short` + `git diff --stat HEAD`.
- If no changes exist (committed or working-tree), STOP and report "nothing to review".
- Group changed files by package/crate.

## 2. Launch review subagents
Required plugin dependencies (declared in `plugins/claudness/.claude-plugin/plugin.json` `requires`; SessionStart warns when missing):
- `code-simplifier@claude-plugins-official` → `code-simplifier`
- `caveman@caveman` → `caveman:cavecrew-reviewer`

**Across packages: concurrent.** Each package's pair runs in its own subagent stream (use `superpowers:dispatching-parallel-agents` to fan out one pair per package). **Within a package: strictly sequential** — `code-simplifier` first, then `caveman:cavecrew-reviewer` reviews the post-simplification diff. Never invoke the two in parallel within the same package: cavecrew must see the simplified code, not the pre-simplification noise.

Per package:

1. **`code-simplifier`** — point it at the recently modified files in the package. It rewrites for clarity/consistency without changing behavior (duplicated logic collapsed, verbose constructs simplified, unnecessary abstractions removed). Apply its rewrites directly to the working tree, run the package's relevant tests, then commit before invoking the reviewer.
2. **`caveman:cavecrew-reviewer`** — point it at the (now simplified) changed files in the package's scope. It returns one-line, severity-tagged findings (caveman-compressed) covering gaps, missing error handling at boundaries, untested paths, dead code, over-engineering, unclear naming, and tests that mock instead of using real data.

Every finding must include file path and line number — no vague feedback accepted. If a package has no changed files, skip its review.

## 3. Fix all reported issues
- Apply every cavecrew finding. Re-run the relevant tests after each batch.
- Fix any pre-existing errors or warnings in touched files (zero tolerance).
- Same approach failed twice? STOP — change hypothesis, don't retry harder.

## 4. Run full quality gates
- `./tools/yamless/check.sh ts` — ZERO errors, ZERO warnings.
- `./tools/yamless/check.sh rust` — ZERO errors, ZERO warnings (fast gates; tests separate).
- `./tools/yamless/test.sh` — full Rust suite must be green.
- If any gate fails, fix and re-run ALL gates until fully green. No exceptions.

## 5. Commit
- Stage intentionally: `git add` only files that belong in this commit — no drive-by staging.
- Use conventional commit messages: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`.
- One logical change per commit — split into multiple commits if scope requires it.
- Never use `--no-verify`. If hooks fail, fix the underlying issue and retry.

## 6. Completion
- Report: what was reviewed, what was fixed, final gate status, commit hashes produced.
- Do not mark complete unless all gates are green AND working tree is clean.

# Plan — pr-babysit + code-review plugins, smarter verdict loop

## Context

The PR babysitter (`/claudness:address-pr-comments`) decides "done" from GitHub check conclusions and filters all `[bot]` comments, so it never reads the CI Claude-review bot's in-place-edited verdict comment — and stops "green" while low/nit findings sit unaddressed (the PR #31 rework). This change extracts the babysitter into its own plugin, gives it a **deterministic** verdict parser that drives a zero-findings fix loop, and adds a project-tuned pre-push `code-review` skill so the bot finds nothing on first push. Per the approved spec `docs/claudness/specs/2026-06-13-pr-babysit-codereview-design.md`.

## Approach

Three plugins, `statusline` extraction as the template (marketplace `plugins[]` entry + `.claude-plugin/plugin.json`, deps only where real). Parsing is a **script**, not prompt text, so it's deterministic + bats-testable. The push-review gate (`plugins/claudness/hooks/pre-tools/modules/push-review.sh`) stays the single source of truth for the diff-SHA/base/slug contract; the code-review skill **replicates the gate's exact recipe** and a bats **cross-check test** asserts the two agree (drift guard) — chosen over refactoring the fail-closed gate (lower blast radius on security-critical code).

**Gate contract the skill MUST match (verbatim from push-review.sh):**
- base: `${PUSH_REVIEW_BASE:-$(detect_base_branch)}` (line 55) — **the gate's local base, NOT the GitHub PR base** (corrects spec §2).
- diff_sha: `set -o pipefail; git diff --no-color "${base}...HEAD" | git hash-object --stdin` (line 95).
- slug: `echo "$branch" | tr '/' '_' | tr -cd 'a-zA-Z0-9_-'` (lines 39-44).
- state file: `${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/tmp/push-review/<slug>.json` (line 51).
- accepted iff `reviewers[]` ∩ accepted list ≠ ∅ (line 174), `version==1`, `findings_count==0` (line 229), `review_round<=MAX_ROUNDS` (line 196), `diff_sha==current` (line 213).

## Steps (ordered, each lands clean)

### 1. `code-review@falconiere` plugin
- `plugins/code-review/.claude-plugin/plugin.json` (mirror statusline shape; **no dependencies**; keywords `["claude-code","code-review","push-review","quality"]`).
- **`plugins/code-review/skills/review/scripts/write-state.sh` (DETERMINISTIC — resolves plan-review B1):** the testable part lives in a script, not the prompt. Args: `--findings-count N --reviewers '["code-review:review"]' --findings '<json>'`. It computes:
  - `base` = `git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's#refs/remotes/origin/##'`, fallback `main` (faithful to `detect_base_branch`'s core; honored env override `$PUSH_REVIEW_BASE`). **Resolves B2** — no replication of `detect_project_root`; the skill runs in the repo worktree.
  - `slug` = `echo "$branch" | tr '/' '_' | tr -cd 'a-zA-Z0-9_-'` (mirror push-review.sh:39-44).
  - `diff_sha` = `set -o pipefail; git diff --no-color "${base}...HEAD" | git hash-object --stdin` (mirror push-review.sh:95) — comment it "MIRROR of push-review.sh — cross-checked by state-writer.bats".
  - `review_round` = read existing state `// 0`, `+1`. Writes `${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/tmp/push-review/<slug>.json` atomically (tmp + `mv`). If the claudness gate isn't present the file is harmless (no-op) — note this in the SKILL.
- `plugins/code-review/skills/review/SKILL.md` — frontmatter `name: review`, description with triggers (explicit + babysit-invoked, NOT auto-fire-every-push — spec Q4 default). Body = the **bot-mirrored checklist** (correctness, security, perf, **test coverage for every new behavior**, doc/comment accuracy [no stale "one-time"], **tight assertions: full-path not suffix**, in-session migration WARNs) + loop review→fix→re-review until clean, then call `write-state.sh` with `findings_count:0`.
- `plugins/code-review/skills/review/scripts/__tests__/state-writer.bats` — real-data, in temp git repos: (i) **non-main base** — set `git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop`, assert `write-state.sh`'s `diff_sha` == `git diff --no-color develop...HEAD | git hash-object --stdin`; (ii) **main fallback** (no origin/HEAD) — same equality vs `main...HEAD`; (iii) slug `feat/x-y`→`feat_x-y`; (iv) atomic write + schema shape + `review_round` bump (0→1, 1→2).
- Add `code-review` entry to `.claude-plugin/marketplace.json`.

### 2. claudness push-review edits (6 touch-points)
- `push-review.sh`: add `"code-review:review"` to `accepted_reviewers` (line 174); add it to the `reviewer_hint` text (lines 125-127); bump `MAX_ROUNDS` 3→**5** (line 196). **Edit only these — do not refactor the deny logic** (fail-closed, security-critical).
- `hooks/docs/push-review.md`: add `code-review:review` to the accepted list; note `MAX_ROUNDS=5`.
- `hooks/pre-tools/modules/__tests__/push-review.bats`: add a case asserting a state file with `reviewers:["code-review:review"]`+`findings_count:0` is accepted. **Round-cap (resolves plan-review-c):** the existing case asserts denial at `review_round>3` — read it first; bumping `MAX_ROUNDS`→5 means any case feeding `review_round=4` (or 3 expecting denial) now flips to ALLOW. Enumerate every round-cap case, update the boundary value to 5, and add an explicit `review_round=6`→deny case + a `review_round=5`→allow case.
- `README.md:124`: push-review bullet — mention `code-review:review` accepted + round cap 5.

### 3. `pr-babysit@falconiere` plugin
- `plugins/pr-babysit/scripts/parse-verdict.sh` — **single responsibility**: stdin = comment body → stdout JSON `{is_review_comment,state(in_progress|complete|unknown),complete,verdict(approved|changes|none),verdict_label,findings:[{path,line,severity,text,key}]}`. Identify via checklist (`- [ ]`/`- [x]`) AND (job-link line OR `Code Review`/`agent-merge-*` token) — robust to both header states. `complete` = ≥1 checkbox AND no unchecked `- [ ]`; **no checkboxes → state=unknown** (degrade). `key` = `<path>:<line>:` + first 8 of `sha1(text)`. `set -o pipefail`; defensive (empty/garbage stdin → `is_review_comment:false`).
- `plugins/pr-babysit/scripts/__tests__/fixtures/pr31-verdict.txt` — the **already-captured real** 7-finding comment body (resolves plan-review-b: do NOT re-fetch live at execution — comment 4700031141 is mutable and may drift from the asserted 7 findings; commit the known-good captured body, which is still real data). One-time provenance: `gh api repos/Falconiere/claudness/issues/comments/4700031141 --jq .body`. Add an in-progress fixture (a `- [ ]` variant) + a no-checkbox fixture, hand-derived from the same format.
- `plugins/pr-babysit/scripts/__tests__/parse-verdict.bats` — assert pr31 fixture → `complete:true,verdict:approved`, **exactly 7 findings**, correct path/severity/text, stable keys; in-progress → `complete:false,state:in_progress`; no-checkbox → `state:unknown`.
- `git mv plugins/claudness/commands/address-pr-comments.md plugins/pr-babysit/commands/babysit.md`; rewrite **all** internal slugs `address-pr-comments`→`pr-babysit` (cron `pr-babysit:${SLOT}`, state `/tmp/pr-babysit-${SLOT}.json`, tick `/pr-babysit:babysit --tick <owner>/<repo>#<n>`, invocation `/pr-babysit:babysit`, keep `stop`). Wire the new loop into the command body: call `parse-verdict.sh`; act only when `complete`; feed findings through Accept/Reject/Unclear triage; loop fix→`code-review:review`→push→re-read until findings empty AND verdict approved AND no human threads AND CI green; caps 5 rounds / same-`key`-twice→escalate; **rejection-of-bot-finding routes to escalation** (bot ignores replies); per-round summary comment; degrade to check-conclusion + flag when parser returns `unknown`/`is_review_comment:false`.
- `plugins/pr-babysit/.claude-plugin/plugin.json` (depends on `claudness@falconiere`); add `pr-babysit` entry to `marketplace.json`.

### 4. Docs + rename cleanup
- `README.md`: line 125 `/address-pr-comments`→`/pr-babysit:babysit`; line ~162 file-tree (command moves out of claudness); add `pr-babysit` + `code-review` rows to the plugin table (line ~62 area) and file-tree.
- Ensure `grep -rn address-pr-comments plugins/ README.md` returns nothing.

## Critical files

Create: `plugins/code-review/{.claude-plugin/plugin.json, skills/review/SKILL.md, skills/review/scripts/write-state.sh, skills/review/scripts/__tests__/state-writer.bats}`; `plugins/pr-babysit/{.claude-plugin/plugin.json, scripts/parse-verdict.sh, scripts/__tests__/parse-verdict.bats, scripts/__tests__/fixtures/{pr31-verdict.txt, in-progress.txt, no-checkbox.txt}}`.
Move: `plugins/claudness/commands/address-pr-comments.md` → `plugins/pr-babysit/commands/babysit.md` (git mv + rewrite).
Edit: `.claude-plugin/marketplace.json` (2 entries); `plugins/claudness/hooks/pre-tools/modules/push-review.sh`; `plugins/claudness/hooks/docs/push-review.md`; `plugins/claudness/hooks/pre-tools/modules/__tests__/push-review.bats`; `README.md`.

## Verification

- `[bats]` `bats plugins/code-review/skills/review/scripts/__tests__/state-writer.bats` — SHA cross-check vs gate passes for non-main base AND main fallback (acceptance #9 + diff_sha contract).
- `[bats]` `bats plugins/pr-babysit/scripts/__tests__/parse-verdict.bats` — 7-findings parse + in-progress + no-checkbox (acceptance #2,#3).
- `[bats]` `bats plugins/claudness/hooks/pre-tools/modules/__tests__/push-review.bats` — `code-review:review` accepted + round cap 5 (acceptance #9, Q1).
- `[bats]` full suite green: `find plugins -name '*.bats' -print0 | xargs -0 bats` (run with `GIT_CONFIG_GLOBAL=/dev/null` locally — forced gpg signing breaks the git-commit cases, CI-clean).
- `shellcheck` clean on `parse-verdict.sh`, edited `push-review.sh`; `jq -e .` on both new `plugin.json` + `marketplace.json`.
- `grep -rn address-pr-comments plugins/ README.md` → empty (acceptance #8).
- `[sandbox]` live in `~/.claude-work` (memory `claudness-dev-sandbox.md`): install `pr-babysit@falconiere` + `code-review@falconiere`, `bash ~/.claude-work/relink-falconiere-dev.sh`, then exercise `/pr-babysit:babysit` against a real PR with bot findings (acceptance #1,#4,#5,#6) and run `code-review:review` against the PR#31 diff to confirm it flags the missing-bats + stale-comment gaps (acceptance #10).
- Quality gate stays green throughout (bash/md/json only; Rust/TS gate untouched). `babysit.md` is a large markdown command — not under TS/Rust ceilings; `parse-verdict.sh` stays a focused single-responsibility script.

## Risks

- **SHA drift** between skill and gate — mitigated by the cross-check bats test (fails CI if they diverge). If they ever must share code, extract a helper published to the claudness registry root (statusline pattern) — deferred (avoids refactoring the fail-closed gate now).
- **Bot comment format** owned by external `Falconiere/workflows` — parser degrades to `unknown`→check-conclusion + flag on drift (acceptance #7).
- **Round-cap**: gate now 5, babysit 5 — aligned; same-key-twice still escalates earlier.

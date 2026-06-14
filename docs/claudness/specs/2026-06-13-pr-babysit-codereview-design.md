# PR-Babysit + Code-Review Plugins — Design

**Date:** 2026-06-13   **Status:** Approved   **Author:** Falconiere   **Topic:** Split the PR babysitter into its own plugin, teach it to chase the CI review bot's in-place verdict findings to zero, and add a project-tuned pre-push review skill to cut rework.

## Problem

The PR babysitter (`/claudness:address-pr-comments`) decides a PR is "done" from GitHub **check conclusions** and **review threads**, and it filters out every `[bot]` comment. But this repo's CI review bot posts its findings as ONE `claude[bot]` issue comment that it **edits in place** — and the `review / review` check reports `SUCCESS` even when that comment lists unaddressed `low`/nit findings (verdict can be Approved-with-findings). Result: the babysitter stops "all green" while real findings sit unread, and the human then hand-fixes them — exactly the rework loop we hit on PR #31 (6 low findings, never surfaced). Separately, the 388-line babysitter is buried inside the omnibus `claudness` plugin, and there is no in-repo reviewer to catch these findings *before* the push that triggers the bot.

## Non-Goals

1. **Not** changing the CI review workflow itself — its comment format is owned by the external `Falconiere/workflows` repo and is out of scope; we consume it, we don't define it.
2. **Not** auto-merging PRs — babysit stops at "ready to merge"; the human merges.
3. **Not** replacing the external `/code-review` or `caveman:cavecrew-reviewer` reviewers — the new `code-review:review` is an additional, project-tuned reviewer, not a removal.
4. **Not** resolving GitHub *review threads* for bot findings — bot findings live in one edited comment, not threads; thread handling for human reviewers is unchanged.
5. **Not** building a configurable severity threshold — the loop chases all findings incl. low (the "configurable threshold" option was rejected in brainstorm).
6. **Not** touching `code-intel` / `lang-quality`.

## Architecture

Three plugins (mirrors the `statusline` extraction template — `marketplace.json` entry + `.claude-plugin/plugin.json`, deps only where real):

| Plugin | Contents | Depends on |
|---|---|---|
| `pr-babysit@falconiere` | `commands/babysit.md` (the babysitter, renamed from `address-pr-comments.md`), `__tests__/` | `claudness@falconiere` (the push-review gate + reviewer registry live there) |
| `code-review@falconiere` | `skills/review/SKILL.md` (bot-mirrored pre-push checklist) + `__tests__/` | none hard (uses gh/git/jq at runtime) |
| `claudness` | unchanged except: register `code-review:review` as an accepted push-review reviewer | — |

**Driving trade-off:** *blast radius vs. cohesion.* Three plugins (not one cohesive "PR-quality" plugin) was chosen so each piece installs and versions independently — you can run the babysitter without the reviewer and vice-versa. The cost is cross-plugin coupling: the babysitter and the reviewer both depend on the push-review gate that stays in `claudness`, and the reviewer name must be registered in `claudness`'s hardcoded accepted list. We accept that coupling because the gate is a `claudness` responsibility and a single hardcoded list is simpler than a discovery mechanism.

**Reuse / prior art:**
- Extraction mechanics: `statusline` template (`.claude-plugin/plugin.json`, `marketplace.json` `plugins[]` entry, README + file-tree updates). Commands are auto-discovered from `commands/` — no manifest registration needed; only `README.md:125,162` reference the old name.
- The babysitter's existing machinery is kept: cron scheduling, slot isolation, `EnterWorktree` per code-change tick, the Accept/Reject/Unclear triage, Step-5 CI handling, adaptive backoff, the `stop` arg.
- Push-review gate: `plugins/claudness/hooks/pre-tools/modules/push-review.sh` — accepted-reviewer list at line 174, state schema in the deny message at line 141, `MAX_ROUNDS` round cap, `findings_count == 0` requirement.

**The rename** rewrites every internal slug `address-pr-comments` → `pr-babysit`: command invocation `/pr-babysit:babysit`, cron name `pr-babysit:${SLOT}`, state file `/tmp/pr-babysit-${SLOT}.json`, tick prompt `/pr-babysit:babysit --tick <owner>/<repo>#<n>`, `stop` arg preserved. README refs updated.

## Interfaces / Schema

### 1. Bot-verdict parsing contract (the core new behavior)

**Determinism (resolves spec-review B1):** parsing is NOT left to the babysit prompt — it lives in a deterministic script `plugins/pr-babysit/scripts/parse-verdict.sh` (stdin: raw comment body; stdout: the normalized JSON below; exit 0). The command calls it and acts on its output. This makes the contract testable on real data (bats against a captured comment fixture) instead of LLM-dependent.

```
parse-verdict.sh  < comment-body.txt  →  stdout:
{ "is_review_comment": true,          # markers matched
  "state": "in_progress|complete|unknown",
  "complete": false,                  # true only when state==complete
  "verdict": "approved|changes|none",
  "verdict_label": "agent-merge-approved",
  "findings": [ {path,line,severity,text,key} ] }
```

**Identification (resolves B2-id):** the CI review is ONE `claude[bot]` issue comment edited in place; its header changes across states (`PR Review in Progress` → `Claude finished … Code Review —`). Identify it as the `claude[bot]`/`github-actions[bot]` issue comment containing a markdown task checklist (`- [ ] / - [x]`) AND (the job-link line OR a `Code Review` / `agent-merge-*` token) — robust to both states. `is_review_comment=false` otherwise.

**Completeness = checkbox state ONLY:** `complete` iff the comment has ≥1 checkbox and **no unchecked `- [ ]`**. Any `- [ ]` remaining → `state=in_progress` → keep-going tick (do not parse findings, do not stop). **No checkboxes at all** → `state=unknown` → degradation path (§ below), NOT "complete".

**Finding extraction** — under `### Findings`, each finding is a line:
```
<path>:<line-or-blank>: <severity>: <text>
```
`severity ∈ {blocker, high, medium, low, nit}` (observed: `low`). Produce a normalized list:
```json
[ { "path": "plugins/.../x.sh", "line": 23, "severity": "low", "text": "...", "key": "<path>:<line>:<sha1(text)[:8]>" } ]
```
`key` is the dedupe/same-finding identity used by the round cap.

**Verdict extraction** — the trailing `**Approved**`/`**Changes requested**` line and the `agent-merge-*` label.

**Stop condition (success)** — ALL true on the same tick:
1. CI: every `statusCheckRollup` check `SUCCESS`/`NEUTRAL`/`SKIPPED`,
2. Findings list is **empty**,
3. Verdict is approved (`agent-merge-approved`),
4. No unresolved human review threads / conversation items (existing Step-1 filter).

**Loop** — when findings non-empty: triage each (Accept/Reject/Unclear) → fix accepted in a worktree → run `code-review:review` → push (re-triggers CI; bot edits its comment) → next tick re-reads. Rejected findings get a reply (conversation comment) with reasoning. **Caps:** ≤5 fix-rounds per PR per session; a finding `key` seen on two consecutive rounds → escalate. Per round, post one summary conversation comment (`Round N: fixed A, B; rejected C — <reason>`).

**Rejection semantic (resolves B-S1):** the bot re-derives findings from the diff and does NOT read reply comments, so a *rejected* finding will reappear in the next in-place verdict. By the same-finding-twice rule this routes to **escalation** — i.e. rejecting a bot finding does not silently skip it; it surfaces the disagreement to the human (intended). Only fixes that change the diff can clear a finding from the next verdict.

**Degradation** — if the bot comment is absent or its markers don't match (format drift), fall back to the legacy check-conclusion + thread behavior AND emit a flag: `⚠️ PR #N: review-bot comment not in the expected format — verify findings manually: <link>`.

### 2. `code-review:review` skill interface

**Invocation:** as a skill (auto-trigger description + explicit call). **Job:** review the working-tree/branch diff against the bot-mirrored checklist, then **write the push-review state file** so the push gate passes.

**Review dimensions (checklist):** correctness; security; performance (hot paths); **test coverage for every new behavior** (e.g. a new code path must have a colocated bats/test); **doc/comment accuracy** (no stale wording like "one-time" on an every-run block); **tight test assertions** (full-path match, not suffix); **in-session migration WARNs** for breaking changes.

**Output:** `.claude/tmp/push-review/<branch-slug>.json`, matching the gate schema:
```json
{ "version": 1, "branch": "...", "diff_sha": "<gate-canonical sha>",
  "base_branch": "<PR base, derived>", "reviewed_at": "<ISO8601>",
  "reviewers": ["code-review:review"], "findings_count": <int>,
  "findings": [ { "path": "...", "severity": "...", "text": "..." } ],
  "review_round": <int> }
```
Written atomically (tmp + `mv`). The gate passes only when `findings_count == 0`, so the skill loops (review → fix → re-review) until clean before writing the final `0`-findings state, OR surfaces the remaining findings for the caller to fix.

**diff_sha contract (resolves B2):** the push-review gate computes its OWN expected `diff_sha` and rejects a mismatch as **stale** — so the skill MUST emit the gate's exact value. The canonical source is the SHA the gate prints in its deny message (`diff SHA <sha>, base <branch>`); the skill reads that, or replicates the gate's exact algorithm in `push-review.sh` (single source of truth — do not invent a parallel `git diff | sha` recipe). `base_branch` is **derived from the PR base** (`gh pr view --json baseRefName`), never hardcoded `main` (babysit may run on PRs targeting other bases).

**review_round contract (resolves B-S3):** the skill READS the existing state file's `review_round` (default 0) and writes `+1` each rewrite — it does not emit a constant. This is the value the gate's round cap checks; see Open Q1 for the cap value.

### 3. Reviewer registration (claudness touch-points)

Add `"code-review:review"` to:
- `plugins/claudness/hooks/pre-tools/modules/push-review.sh:174` — `accepted_reviewers` JSON array.
- `plugins/claudness/hooks/pre-tools/modules/push-review.sh:141` — the deny-message reviewer hint.
- `plugins/claudness/hooks/docs/push-review.md:11` — accepted-list doc.
- `plugins/claudness/hooks/pre-tools/modules/__tests__/push-review.bats` — a case asserting `code-review:review` is accepted; update the round-cap case to `MAX_ROUNDS=5`.
- `plugins/claudness/hooks/pre-tools/modules/push-review.sh` — bump `MAX_ROUNDS` 3 → 5 (per Open Q1).
- `README.md:124` — the push-review bullet.

### File inventory

- New: `plugins/pr-babysit/{.claude-plugin/plugin.json, commands/babysit.md, scripts/parse-verdict.sh, scripts/__tests__/parse-verdict.bats, scripts/__tests__/fixtures/pr31-verdict.txt}`
- New: `plugins/code-review/{.claude-plugin/plugin.json, skills/review/SKILL.md, __tests__/*.bats}`
- Move: `plugins/claudness/commands/address-pr-comments.md` → `plugins/pr-babysit/commands/babysit.md` (git mv + slug rewrite)
- Edit: `.claude-plugin/marketplace.json` (2 new entries), `push-review.sh` (`accepted_reviewers` + deny hint), `push-review.md` (accepted list), `push-review.bats`, `README.md:124,125,162`

> Note: push-review line numbers above are indicative — reference by symbol (`accepted_reviewers`, the deny-message block, `MAX_ROUNDS`) when editing, as lines drift.

## Acceptance criteria

**Test method (resolves B-S4):** `[bats]` = scriptable real-data bats; `[sandbox]` = manual verification in the `~/.claude-work` live session (LLM-driven command/skill behavior, not unit-testable). The deterministic parser + reviewer-registration are `[bats]`; full babysit loop + LLM review judgment are `[sandbox]`.

1. `[bats]` (parser) + `[sandbox]` (loop) **Falsely-green bug fixed:** given a real PR whose bot comment is checklist-complete and lists ≥1 `low` finding under `### Findings` while `review / review` is `SUCCESS`, babysit does NOT success-stop — it extracts the finding(s) and enters the fix loop. (Reproduces the PR #31 scenario.)
2. **In-progress is not parsed:** given a bot comment containing any `- [ ]`, babysit treats it as in-progress (keep-going tick), extracts no findings, does not stop.
3. `[bats]` **Finding parse:** `parse-verdict.sh < fixtures/pr31-verdict.txt` (the captured real comment body, sourced via `gh api repos/Falconiere/claudness/issues/comments/4700031141`) yields `complete:true`, `verdict:approved`, and exactly the 7 findings with correct `path`/`severity`/`text` and stable `key`s.
4. **Zero-findings stop:** given a bot comment with an empty `### Findings` (or "none") + `agent-merge-approved` + all checks green + no human threads, babysit success-stops with the "ready to merge" message and clears its cron/state.
5. **Same-finding-twice escalation:** a finding whose `key` recurs on two consecutive rounds triggers the escalation message and stops the loop (no 3rd attempt on it).
6. **Round cap:** ≥5 fix-rounds in a session without reaching zero → escalation message, loop stops.
7. **Format-drift degradation:** given a `claude[bot]` comment missing the markers, babysit falls back to check-conclusion behavior and emits the manual-verify flag.
8. **Rename complete:** `grep -rn address-pr-comments plugins/` returns nothing; `/pr-babysit:babysit` is discoverable; cron/state/tick slugs all read `pr-babysit`; `stop` still cancels.
9. `[bats]` **Reviewer accepted:** with a push-review state file recording `reviewers:["code-review:review"]` and `findings_count:0`, `git push` on a feature branch is allowed by the gate; `push-review.bats` asserts the name is in the accepted list.
10. `[sandbox]` **Code-review skill catches a real gap:** run against the PR #31 diff *before* its push, the skill reports the missing orphan-sweep bats coverage and the stale "one-time" comment (the two real findings the bot later raised).
11. **Conventions:** new command/skill files named after their export, each `__tests__/` is real-data bats (no mocks), CI auto-discovers them; manifests are jq-valid; `shellcheck` clean.

## Open Questions

1. **Round-cap collision — RESOLVED.** The push-review gate caps `review_round` at `MAX_ROUNDS=3` (`push-review.sh`), but babysit wants up to **5** fix-rounds, each a push with a bumped `review_round` — the gate would block at 3 before babysit's cap fires. **Decision:** bump push-review `MAX_ROUNDS` to **5** so the two caps agree and babysit owns the escalation (acceptance #6). Reversible; `push-review.bats` round-cap case updates to 5. (Adds a 6th claudness touch-point to §3.)
2. **Bot identity beyond markers (owner: Falconiere).** Is the review always authored by `claude[bot]`, or can it be `github-actions[bot]`? Marker-matching covers both, but confirm the author set so we don't match an unrelated bot's comment.
3. **Reviewer name vs. built-in (owner: Falconiere).** `code-review:review` is distinct from the built-in `/code-review` (recorded as `code-review`). Confirm we want a distinct accepted entry (chosen) rather than reusing `code-review` (no hook edit, but opaque).
4. **Skill auto-trigger scope (owner: Falconiere).** Should `code-review:review` auto-fire before every push (via description triggers) or only when explicitly invoked / by babysit? Default: explicit + babysit-invoked, to avoid surprising the user mid-edit.

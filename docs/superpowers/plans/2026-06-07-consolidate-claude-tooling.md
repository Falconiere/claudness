# Consolidate Claude tooling from routo.io and yamless.io — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Claude Code configuration from `/Volumes/Projects/routo.io` and `/Volumes/Projects/yamless.io` into the standalone `/Volumes/Projects/my-claude` repo so any future project can symlink it. Every script must be project-agnostic.

**Architecture:** Single flat layout per the existing `README.md` (`skills/`, `agents/`, `commands/`, `hooks/`, `tooling/`, `settings/`, `mcp/`). Per-file diff resolution for the 26 files that overlap between the two repos. Data-over-code refactor for all shell hooks: hardcoded lists move into `settings/*.txt` data files; auto-detection replaces hardcoded paths and package managers; missing tools become a silent no-op.

**Tech Stack:** Bash, bats-core for tests, jq for JSON merges, shellcheck for lint, git.

**Source spec:** `docs/superpowers/specs/2026-06-07-consolidate-claude-tooling-design.md`.

**Working directory for all commands:** `/Volumes/Projects/my-claude` unless otherwise stated.

**File-resolution inventory (locked at plan time):**

- 26 divergent files — diff-resolve interactively per Task 8–33.
- 3 identical files — copy once (Task 6).
- 3 routo-only files migrate after generic-check — Task 7.
- 10 yamless-only files migrate as-is — Task 5.
- 13 routo-only files **skip:** `mobile-e2e.md`, `settings.local.json`, `code-intel/scripts/modules/{gitnexus,grepai}.sh`, all `skills/gitnexus/**`, `skills/grepai/SKILL.md`.
- 2 yamless-only files **skip:** `.tooling/.env`, `.tooling/.env.example` (secrets documented instead).

---

## Phase 0 — Repo skeleton

### Task 1: Create directory skeleton

**Files:**
- Create: `skills/`, `agents/`, `commands/`, `hooks/pre-tools/modules/`, `hooks/pre-tools/modules/__tests__/`, `hooks/post-tools/modules/`, `hooks/docs/`, `tooling/__tests__/`, `settings/`, `mcp/`

- [ ] **Step 1: Create directories**

```bash
mkdir -p skills agents commands \
  hooks/pre-tools/modules/__tests__ \
  hooks/post-tools/modules \
  hooks/docs \
  tooling/__tests__ \
  settings mcp
```

- [ ] **Step 2: Add .gitkeep to empty dirs**

```bash
touch skills/.gitkeep agents/.gitkeep commands/.gitkeep \
  hooks/.gitkeep settings/.gitkeep mcp/.gitkeep
```

- [ ] **Step 3: Verify tree**

Run: `find . -type d -not -path './.git*' -not -path './docs*' -not -path './node_modules*' | sort`
Expected: lists every directory created above.

- [ ] **Step 4: Commit**

```bash
git add skills agents commands hooks tooling settings mcp
git commit -m "chore: scaffold consolidation directory layout"
```

### Task 2: Add .shellcheckrc

**Files:**
- Create: `.shellcheckrc`

- [ ] **Step 1: Inspect routo's .shellcheckrc**

Run: `cat /Volumes/Projects/routo.io/.shellcheckrc`
Expected: see existing shellcheck config (likely `external-sources=true`, `shell=bash`, possibly disabled checks).

- [ ] **Step 2: Copy verbatim**

```bash
cp /Volumes/Projects/routo.io/.shellcheckrc .shellcheckrc
```

- [ ] **Step 3: Verify generic**

Run: `cat .shellcheckrc`
Expected: no routo-specific paths or source-paths. If any line references `/Volumes/Projects/routo.io` or `routo`, delete that line.

- [ ] **Step 4: Verify shellcheck installed**

Run: `command -v shellcheck && shellcheck --version`
Expected: prints version. If missing, install via `brew install shellcheck` first.

- [ ] **Step 5: Commit**

```bash
git add .shellcheckrc
git commit -m "chore: add shellcheckrc"
```

### Task 3: Install bats-core if missing

**Files:** (none — verification only)

- [ ] **Step 1: Check bats**

Run: `command -v bats && bats --version`
Expected: prints version. If missing:

```bash
brew install bats-core
```

- [ ] **Step 2: Verify**

Run: `bats --version`
Expected: `Bats X.Y.Z`. No commit.

---

## Phase 1 — Lossless copies (no decisions)

### Task 4: Copy the 3 identical files

**Files:**
- Create:
  - `hooks/docs/post-compaction.md` (from either repo)
  - `hooks/post-tools/mod.sh`
  - `hooks/pre-tools/mod.sh`

- [ ] **Step 1: Copy from yamless (arbitrary — identical to routo)**

```bash
cp /Volumes/Projects/yamless.io/.claude/hooks/docs/post-compaction.md   hooks/docs/post-compaction.md
cp /Volumes/Projects/yamless.io/.claude/hooks/post-tools/mod.sh         hooks/post-tools/mod.sh
cp /Volumes/Projects/yamless.io/.claude/hooks/pre-tools/mod.sh          hooks/pre-tools/mod.sh
chmod +x hooks/post-tools/mod.sh hooks/pre-tools/mod.sh
```

- [ ] **Step 2: Verify identical to source**

Run: `diff hooks/post-tools/mod.sh /Volumes/Projects/routo.io/.claude/hooks/post-tools/mod.sh && echo ok`
Expected: `ok`.

- [ ] **Step 3: Shellcheck the dispatchers**

Run: `shellcheck hooks/post-tools/mod.sh hooks/pre-tools/mod.sh`
Expected: no output (clean). If failures, do not fix yet — note for the refactor phase.

- [ ] **Step 4: Commit**

```bash
git add hooks/docs/post-compaction.md hooks/post-tools/mod.sh hooks/pre-tools/mod.sh
git commit -m "feat(hooks): copy identical dispatcher and docs from source repos"
```

### Task 5: Copy yamless-only files

**Files:**
- Create:
  - `hooks/docs/push-review.md`
  - `hooks/post-tools/modules/rust-quality.sh`
  - `hooks/pre-tools/modules/mcp-blocker.sh`
  - `hooks/pre-tools/modules/push-review.sh`
  - `hooks/pre-tools/modules/__tests__/helpers.bash`
  - `hooks/pre-tools/modules/__tests__/push-review.bats`
  - `skills/code-intel/references/ast-grep-advanced.md`
  - `skills/code-intel/scripts/modules/ast-grep.sh`
  - `tooling/__tests__/context7.bats`
  - `tooling/__tests__/exa-search.bats`
  - `tooling/__tests__/helpers.bash`

- [ ] **Step 1: Copy hook scripts and docs**

```bash
Y=/Volumes/Projects/yamless.io
cp "$Y/.claude/hooks/docs/push-review.md"                          hooks/docs/push-review.md
cp "$Y/.claude/hooks/post-tools/modules/rust-quality.sh"           hooks/post-tools/modules/rust-quality.sh
cp "$Y/.claude/hooks/pre-tools/modules/mcp-blocker.sh"             hooks/pre-tools/modules/mcp-blocker.sh
cp "$Y/.claude/hooks/pre-tools/modules/push-review.sh"             hooks/pre-tools/modules/push-review.sh
chmod +x hooks/post-tools/modules/rust-quality.sh \
         hooks/pre-tools/modules/mcp-blocker.sh \
         hooks/pre-tools/modules/push-review.sh
```

- [ ] **Step 2: Copy bats tests**

```bash
cp "$Y/.claude/hooks/pre-tools/modules/__tests__/helpers.bash"     hooks/pre-tools/modules/__tests__/helpers.bash
cp "$Y/.claude/hooks/pre-tools/modules/__tests__/push-review.bats" hooks/pre-tools/modules/__tests__/push-review.bats
cp "$Y/.tooling/__tests__/context7.bats"                            tooling/__tests__/context7.bats
cp "$Y/.tooling/__tests__/exa-search.bats"                          tooling/__tests__/exa-search.bats
cp "$Y/.tooling/__tests__/helpers.bash"                             tooling/__tests__/helpers.bash
```

- [ ] **Step 3: Copy skill files**

```bash
mkdir -p skills/code-intel/references skills/code-intel/scripts/modules
cp "$Y/.claude/skills/code-intel/references/ast-grep-advanced.md"   skills/code-intel/references/ast-grep-advanced.md
cp "$Y/.claude/skills/code-intel/scripts/modules/ast-grep.sh"       skills/code-intel/scripts/modules/ast-grep.sh
chmod +x skills/code-intel/scripts/modules/ast-grep.sh
```

- [ ] **Step 4: Run bats suite (expected to fail — paths still source-relative)**

Run: `bats hooks/pre-tools/modules/__tests__ tooling/__tests__ || true`
Expected: failures because the bats files still reference paths that don't exist yet in `my-claude` (the modules they test get copied/refactored later). Document this expected failure — do not fix yet.

- [ ] **Step 5: Shellcheck the new scripts**

Run: `shellcheck hooks/post-tools/modules/rust-quality.sh hooks/pre-tools/modules/mcp-blocker.sh hooks/pre-tools/modules/push-review.sh skills/code-intel/scripts/modules/ast-grep.sh`
Expected: may show warnings — note for refactor phase, do not fix yet.

- [ ] **Step 6: Commit**

```bash
git add hooks/docs/push-review.md \
        hooks/post-tools/modules/rust-quality.sh \
        hooks/pre-tools/modules/mcp-blocker.sh \
        hooks/pre-tools/modules/push-review.sh \
        hooks/pre-tools/modules/__tests__ \
        skills/code-intel/references/ast-grep-advanced.md \
        skills/code-intel/scripts/modules/ast-grep.sh \
        tooling/__tests__
git commit -m "feat: copy yamless-only hooks, tests, and code-intel modules"
```

### Task 6: Copy routo-only files (after generic check)

**Files:**
- Create:
  - `skills/agent-memory/SKILL.md`
  - `skills/ast-grep/SKILL.md`
  - `skills/code-intel/references/cypher.md` (only if generic)

- [ ] **Step 1: Inspect agent-memory and ast-grep skills for routo coupling**

```bash
R=/Volumes/Projects/routo.io
grep -nE 'routo|console-app|/Volumes/Projects/routo' \
  "$R/.claude/skills/agent-memory/SKILL.md" \
  "$R/.claude/skills/ast-grep/SKILL.md" || echo "no hits — generic"
```

Expected: `no hits — generic`. If hits exist, list them; remove or generalize each line during the copy (Step 2).

- [ ] **Step 2: Copy agent-memory and ast-grep**

```bash
mkdir -p skills/agent-memory skills/ast-grep
cp "$R/.claude/skills/agent-memory/SKILL.md"  skills/agent-memory/SKILL.md
cp "$R/.claude/skills/ast-grep/SKILL.md"      skills/ast-grep/SKILL.md
```

If any routo-specific lines were flagged in Step 1, edit them out now with the Edit tool (replace project names / paths with generic phrasing).

- [ ] **Step 3: Inspect cypher.md — does it reference GitNexus internals?**

```bash
grep -nE 'gitnexus|GitNexus|routo' "$R/.claude/skills/code-intel/references/cypher.md" || echo "no hits"
```

If `no hits`, the file is generic — proceed to Step 4. If hits exist, **skip the file**: do not copy it. (Cypher is a query language; the reference is only useful as a generic Cypher cheatsheet, not as a GitNexus-coupled doc.)

- [ ] **Step 4: Copy cypher.md if generic, else skip**

If Step 3 said `no hits`:

```bash
cp "$R/.claude/skills/code-intel/references/cypher.md" skills/code-intel/references/cypher.md
```

Else: skip silently.

- [ ] **Step 5: Commit**

```bash
git add skills/agent-memory skills/ast-grep
git add skills/code-intel/references/cypher.md 2>/dev/null || true
git commit -m "feat(skills): copy routo-only agent-memory, ast-grep, and (if generic) cypher reference"
```

### Task 7: Copy SKILL.md scripts/mod.sh from divergent (deferred to Phase 2)

This task is intentionally part of Phase 2 because `skills/code-intel/scripts/mod.sh` is divergent. Resolved in Task 27.

---

## Phase 2 — Per-file diff resolution (26 files)

Each task in this phase follows the same template:

1. Show the diff to the user.
2. The engineer presents both versions side-by-side, asks which to keep (R = routo, Y = yamless, M = manual merge).
3. Apply the chosen version (with manual hunks if M).
4. Shellcheck if `.sh`.
5. Commit.

**Decision recording:** every task ends with a one-line entry appended to `docs/superpowers/plans/2026-06-07-consolidate-resolutions.log` with the format `<path>\t<R|Y|M>\t<reason>` so the choices are auditable.

### Task 8: Resolve `.claude/agents/deep-explore.md`

**Files:**
- Create: `agents/deep-explore.md`

- [ ] **Step 1: Show diff**

Run: `diff -u /Volumes/Projects/routo.io/.claude/agents/deep-explore.md /Volumes/Projects/yamless.io/.claude/agents/deep-explore.md`

- [ ] **Step 2: Ask user — keep R, Y, or merge?**

Present both diffs. Wait for user decision: `R`, `Y`, or `M` (with merge instructions).

- [ ] **Step 3: Apply choice**

```bash
# R:
cp /Volumes/Projects/routo.io/.claude/agents/deep-explore.md agents/deep-explore.md
# Y:
cp /Volumes/Projects/yamless.io/.claude/agents/deep-explore.md agents/deep-explore.md
# M: cat the chosen base into agents/deep-explore.md then Edit with hunks from the other
```

- [ ] **Step 4: Record decision**

```bash
echo -e "agents/deep-explore.md\t<R|Y|M>\t<reason>" >> docs/superpowers/plans/2026-06-07-consolidate-resolutions.log
```

- [ ] **Step 5: Commit**

```bash
git add agents/deep-explore.md docs/superpowers/plans/2026-06-07-consolidate-resolutions.log
git commit -m "feat(agents): consolidate deep-explore"
```

### Task 9: Resolve `.claude/commands/commit.md`

Same template as Task 8, paths:
- diff source: `/Volumes/Projects/{routo.io,yamless.io}/.claude/commands/commit.md`
- destination: `commands/commit.md`
- commit subject: `feat(commands): consolidate commit command`

### Task 10: Resolve `.claude/commands/review-and-commit.md`

Same template. Destination `commands/review-and-commit.md`. Commit: `feat(commands): consolidate review-and-commit command`.

### Task 11: Resolve `.claude/hooks/pre-compact.sh`

Same template. Destination `hooks/pre-compact.sh`. Chmod +x. Run shellcheck after copy. Commit: `feat(hooks): consolidate pre-compact`.

### Task 12: Resolve `.claude/hooks/session-end.sh`

Same template. Destination `hooks/session-end.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate session-end`.

### Task 13: Resolve `.claude/hooks/session-start.sh`

Same template. Destination `hooks/session-start.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate session-start`.

> Note: known coupling here. Will be refactored in Task 36. For Phase 2, just pick a base.

### Task 14: Resolve `.claude/hooks/user-prompt-submit.sh`

Same template. Destination `hooks/user-prompt-submit.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate user-prompt-submit`.

> Refactored in Task 37.

### Task 15: Resolve `.claude/hooks/docs/session-start.md`

Same template. Destination `hooks/docs/session-start.md`. Commit: `docs(hooks): consolidate session-start doc`.

### Task 16: Resolve `.claude/hooks/docs/vector-helper-recall.md`

Same template. Destination `hooks/docs/vector-helper-recall.md`. Commit: `docs(hooks): consolidate vector-helper-recall doc`.

### Task 17: Resolve `.claude/hooks/docs/vector-helper-save.md`

Same template. Destination `hooks/docs/vector-helper-save.md`. Commit: `docs(hooks): consolidate vector-helper-save doc`.

### Task 18: Resolve `.claude/hooks/post-tools/modules/gate-status.sh`

Same template. Destination `hooks/post-tools/modules/gate-status.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate gate-status`.

### Task 19: Resolve `.claude/hooks/post-tools/modules/ts-quality.sh`

Same template. Destination `hooks/post-tools/modules/ts-quality.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate ts-quality`.

> Refactored in Task 38.

### Task 20: Resolve `.claude/hooks/pre-tools/modules/bash-commands.sh`

Same template. Destination `hooks/pre-tools/modules/bash-commands.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate bash-commands`.

> Refactored in Task 39 (data extraction).

### Task 21: Resolve `.claude/hooks/pre-tools/modules/code-edit-rules.sh`

Same template. Destination `hooks/pre-tools/modules/code-edit-rules.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate code-edit-rules`.

> Refactored in Task 40.

### Task 22: Resolve `.claude/hooks/pre-tools/modules/commit-gate.sh`

Same template. Destination `hooks/pre-tools/modules/commit-gate.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate commit-gate`.

> Refactored in Task 41.

### Task 23: Resolve `.claude/hooks/pre-tools/modules/protected-files.sh`

Same template. Destination `hooks/pre-tools/modules/protected-files.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate protected-files`.

> Refactored in Task 42.

### Task 24: Resolve `.claude/hooks/pre-tools/modules/quality-gate.sh`

Same template. Destination `hooks/pre-tools/modules/quality-gate.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate quality-gate`.

> Refactored in Task 43.

### Task 25: Resolve `.claude/hooks/pre-tools/modules/search-nudge.sh`

Same template. Destination `hooks/pre-tools/modules/search-nudge.sh`. Chmod +x. Shellcheck. Commit: `feat(hooks): consolidate search-nudge`.

### Task 26: Resolve `.claude/skills/code-intel/SKILL.md`

Same template. Destination `skills/code-intel/SKILL.md`. Commit: `feat(skills): consolidate code-intel SKILL.md`.

> Manual scrub during/after copy: remove any reference to `gitnexus` and `grepai` since those modules are not migrating. Keep references to `ast-grep` and `engram` only.

### Task 27: Resolve `.claude/skills/code-intel/scripts/mod.sh`

Same template. Destination `skills/code-intel/scripts/mod.sh`. Chmod +x. Shellcheck. Commit: `feat(skills): consolidate code-intel mod.sh`.

> Manual scrub: remove any case branches that dispatch to `gitnexus.sh` or `grepai.sh`. Only `ast-grep.sh` and `engram.sh` should remain.

### Task 28: Resolve `.claude/skills/code-intel/scripts/modules/engram.sh`

Same template. Destination `skills/code-intel/scripts/modules/engram.sh`. Chmod +x. Shellcheck. Commit: `feat(skills): consolidate engram module`.

> Refactored in Task 46.

### Task 29: Resolve `.claude/skills/context7/SKILL.md`

Same template. Destination `skills/context7/SKILL.md`. Commit: `feat(skills): consolidate context7 SKILL.md`.

### Task 30: Resolve `.claude/skills/exa-search/SKILL.md`

Same template. Destination `skills/exa-search/SKILL.md`. Commit: `feat(skills): consolidate exa-search SKILL.md`.

### Task 31: Resolve `.tooling/context7/search.sh`

Same template. Destination `tooling/context7/search.sh`. Chmod +x. Shellcheck. Commit: `feat(tooling): consolidate context7 search`.

> Refactored in Task 44.

### Task 32: Resolve `.tooling/exa-search/search.sh`

Same template. Destination `tooling/exa-search/search.sh`. Chmod +x. Shellcheck. Commit: `feat(tooling): consolidate exa-search search`.

> Refactored in Task 45.

### Task 33: Resolve `.claude/settings.json` (raw copy → fragment extraction)

**Files:**
- Stash: `settings/_raw/routo-settings.json`, `settings/_raw/yamless-settings.json`

- [ ] **Step 1: Stash both raw settings for the fragment-extraction step**

```bash
mkdir -p settings/_raw
cp /Volumes/Projects/routo.io/.claude/settings.json   settings/_raw/routo-settings.json
cp /Volumes/Projects/yamless.io/.claude/settings.json settings/_raw/yamless-settings.json
```

- [ ] **Step 2: Show diff for user awareness**

Run: `diff -u settings/_raw/routo-settings.json settings/_raw/yamless-settings.json`

- [ ] **Step 3: Commit raw stash**

```bash
git add settings/_raw
git commit -m "chore(settings): stash raw source settings for fragment extraction"
```

> Fragments built in Tasks 50–51. `settings/_raw/` will be removed in Task 52.

---

## Phase 3 — Agnosticism audit

### Task 34: Run agnosticism audit and triage

**Files:**
- Create: `docs/superpowers/plans/2026-06-07-agnosticism-audit.md`

- [ ] **Step 1: Run grep for hardcoded coupling**

```bash
grep -rEn 'routo|yamless|/Volumes/Projects/(routo|yamless)|console-app' \
  hooks/ tooling/ skills/ settings/ 2>/dev/null \
  | tee docs/superpowers/plans/2026-06-07-agnosticism-audit.md.raw
```

- [ ] **Step 2: Triage every hit**

Open `2026-06-07-agnosticism-audit.md.raw`. For each hit, write a row in `docs/superpowers/plans/2026-06-07-agnosticism-audit.md`:

```markdown
| File:line | Hit | Action | Refactor task |
|---|---|---|---|
| hooks/session-start.sh:42 | hardcoded "routo" project name | Replace with `basename "$(git rev-parse --show-toplevel)"` | Task 36 |
```

Each hit must map to a refactor task (36–46) or get an inline fix in this task if it is a trivial typo (delete and move on).

- [ ] **Step 3: Run grep for package-manager assumptions**

```bash
grep -rEn '\b(bun|pnpm|npm|yarn|cargo|turbo)\b' hooks/ tooling/ skills/ 2>/dev/null \
  | tee -a docs/superpowers/plans/2026-06-07-agnosticism-audit.md.raw
```

Add rows for any hardcoded tool to the audit table. Map to a refactor task.

- [ ] **Step 4: Commit audit doc**

```bash
git add docs/superpowers/plans/2026-06-07-agnosticism-audit.md \
        docs/superpowers/plans/2026-06-07-agnosticism-audit.md.raw
git commit -m "docs: agnosticism audit before refactor pass"
```

### Task 35: Add shared helper `hooks/lib/detect.sh`

**Files:**
- Create: `hooks/lib/detect.sh`

- [ ] **Step 1: Write detect.sh**

```bash
mkdir -p hooks/lib
cat > hooks/lib/detect.sh <<'SH'
#!/usr/bin/env bash
# Shared detection helpers for project-agnostic hooks.
# Source via:   . "${BASH_SOURCE%/*}/../lib/detect.sh"

# Print the absolute project root (git toplevel) or "" if not in a git repo.
detect_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || true
}

# Print the project name (basename of the git toplevel) or "" if not in a git repo.
detect_project_name() {
  local root
  root=$(detect_project_root) || return 0
  [ -n "$root" ] && basename "$root"
}

# Print the package manager: bun | pnpm | npm | yarn | "" (none detected).
detect_node_pm() {
  local root
  root=$(detect_project_root)
  [ -z "$root" ] && return 0
  [ -f "$root/bun.lock" ]          && echo bun && return
  [ -f "$root/bun.lockb" ]         && echo bun && return
  [ -f "$root/pnpm-lock.yaml" ]    && echo pnpm && return
  [ -f "$root/yarn.lock" ]         && echo yarn && return
  [ -f "$root/package-lock.json" ] && echo npm && return
}

# Echo "rust" if a Cargo.toml exists at the project root.
detect_rust() {
  local root
  root=$(detect_project_root)
  [ -z "$root" ] && return 0
  [ -f "$root/Cargo.toml" ] && echo rust
}

# Echo "ts" if a tsconfig*.json exists anywhere in the project.
detect_ts() {
  local root
  root=$(detect_project_root)
  [ -z "$root" ] && return 0
  git -C "$root" ls-files '**/tsconfig*.json' 'tsconfig*.json' 2>/dev/null \
    | grep -q . && echo ts
}

# Return the base branch from origin/HEAD, or "main" if remote is missing.
detect_base_branch() {
  local root ref
  root=$(detect_project_root)
  [ -z "$root" ] && { echo main; return; }
  ref=$(git -C "$root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    echo "${ref#refs/remotes/origin/}"
  else
    echo main
  fi
}

# Print the data dir for settings/ lookups. Override with $MY_CLAUDE_SETTINGS_DIR.
detect_settings_dir() {
  if [ -n "${MY_CLAUDE_SETTINGS_DIR:-}" ]; then
    echo "$MY_CLAUDE_SETTINGS_DIR"
  elif [ -d "${HOME}/.claude/settings" ]; then
    echo "${HOME}/.claude/settings"
  else
    # Fall back to the directory two levels above this helper.
    local self
    self=$(cd "${BASH_SOURCE%/*}/.." && pwd)
    echo "$self/../settings"
  fi
}
SH
chmod +x hooks/lib/detect.sh
```

- [ ] **Step 2: Write a bats test for detect.sh**

```bash
cat > hooks/lib/detect.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  load "${BATS_TEST_DIRNAME}/../pre-tools/modules/__tests__/helpers.bash" 2>/dev/null || true
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git commit --allow-empty -m init -q
}

teardown() {
  rm -rf "$TMP"
}

source_lib() {
  # shellcheck disable=SC1091
  . "${BATS_TEST_DIRNAME}/detect.sh"
}

@test "detect_project_root returns git toplevel" {
  source_lib
  run detect_project_root
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP" ] || [ "$output" = "$(cd "$TMP" && pwd -P)" ]
}

@test "detect_project_name returns basename" {
  source_lib
  run detect_project_name
  [ "$status" -eq 0 ]
  [ "$output" = "$(basename "$TMP")" ]
}

@test "detect_node_pm returns bun when bun.lock present" {
  touch bun.lock
  source_lib
  run detect_node_pm
  [ "$output" = "bun" ]
}

@test "detect_node_pm returns pnpm when pnpm-lock.yaml present" {
  touch pnpm-lock.yaml
  source_lib
  run detect_node_pm
  [ "$output" = "pnpm" ]
}

@test "detect_rust returns rust when Cargo.toml present" {
  touch Cargo.toml
  source_lib
  run detect_rust
  [ "$output" = "rust" ]
}

@test "detect_ts returns ts when tsconfig.json present" {
  echo '{}' > tsconfig.json
  git add tsconfig.json
  git commit -q -m tsconfig
  source_lib
  run detect_ts
  [ "$output" = "ts" ]
}

@test "detect_base_branch falls back to main when no remote" {
  source_lib
  run detect_base_branch
  [ "$output" = "main" ]
}

@test "detect_project_root returns empty outside git" {
  cd /tmp
  source_lib
  run detect_project_root
  [ -z "$output" ]
}
BATS
```

- [ ] **Step 3: Run the test**

Run: `bats hooks/lib/detect.bats`
Expected: all tests PASS.

- [ ] **Step 4: Shellcheck**

Run: `shellcheck hooks/lib/detect.sh`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/detect.sh hooks/lib/detect.bats
git commit -m "feat(hooks): add detect.sh shared agnostic-helpers"
```

---

## Phase 4 — Refactor pass (script-by-script)

Each task in this phase follows the same template:

1. Read the existing script (already copied in Phase 2).
2. Identify hits from the audit (Task 34).
3. Source `hooks/lib/detect.sh` where applicable.
4. Replace hardcoded values with detection calls or data-file lookups.
5. Add `command -v` guards for external tools.
6. Run shellcheck.
7. Run / write a bats test.
8. Commit.

### Task 36: Refactor `hooks/session-start.sh` for agnosticism

**Files:**
- Modify: `hooks/session-start.sh`
- Create: `hooks/session-start.bats`

- [ ] **Step 1: Read script and audit hits**

Run: `cat hooks/session-start.sh` and `grep -nE 'routo|yamless|/Volumes/Projects/(routo|yamless)|console-app' hooks/session-start.sh`

- [ ] **Step 2: Apply refactor — source detect.sh, replace hardcoded names**

For each hit:
- Project name reference → `name=$(detect_project_name)`. If empty, do not print the project section.
- Path reference → `root=$(detect_project_root)`. Use `"$root"` everywhere.
- Tool invocation (`bun`, `cargo`, `turbo`, etc.) → guard with `command -v <tool> >/dev/null 2>&1 || return 0`.

At the top of the script add:

```bash
# shellcheck source=hooks/lib/detect.sh
. "${BASH_SOURCE%/*}/lib/detect.sh"
```

- [ ] **Step 3: Write bats test**

```bash
cat > hooks/session-start.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git commit --allow-empty -m init -q
}

teardown() { rm -rf "$TMP"; }

@test "session-start runs without error in an empty git repo" {
  run "${BATS_TEST_DIRNAME}/session-start.sh"
  [ "$status" -eq 0 ]
}

@test "session-start does not print routo or yamless" {
  run "${BATS_TEST_DIRNAME}/session-start.sh"
  ! echo "$output" | grep -qiE 'routo|yamless'
}

@test "session-start runs without error outside any git repo" {
  cd /tmp
  run "${BATS_TEST_DIRNAME}/session-start.sh"
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 4: Run bats**

Run: `bats hooks/session-start.bats`
Expected: 3 PASS.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck hooks/session-start.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start.sh hooks/session-start.bats
git commit -m "refactor(hooks): make session-start project-agnostic"
```

### Task 37: Refactor `hooks/user-prompt-submit.sh`

**Files:**
- Modify: `hooks/user-prompt-submit.sh`
- Create: `hooks/user-prompt-submit.bats`

- [ ] **Step 1: Read script and audit hits**

Run: `cat hooks/user-prompt-submit.sh` and `grep -nE 'routo|yamless|/Volumes/Projects|console-app' hooks/user-prompt-submit.sh`

- [ ] **Step 2: Apply refactor**

- Source `lib/detect.sh`.
- Replace any project-specific grep/file injection with: source a per-project `.claude/context.sh` when present, no-op otherwise.

Snippet to add:

```bash
root=$(detect_project_root)
if [ -n "$root" ] && [ -f "$root/.claude/context.sh" ]; then
  # shellcheck source=/dev/null
  . "$root/.claude/context.sh"
fi
```

- [ ] **Step 3: Write bats test**

```bash
cat > hooks/user-prompt-submit.bats <<'BATS'
#!/usr/bin/env bats

setup() { TMP=$(mktemp -d); cd "$TMP"; git init -q; git commit --allow-empty -m init -q; }
teardown() { rm -rf "$TMP"; }

@test "user-prompt-submit runs without context.sh" {
  run "${BATS_TEST_DIRNAME}/user-prompt-submit.sh"
  [ "$status" -eq 0 ]
}

@test "user-prompt-submit sources context.sh when present" {
  mkdir -p .claude
  echo 'export MY_CLAUDE_TEST_FLAG=1' > .claude/context.sh
  run bash -c '. "${BATS_TEST_DIRNAME}/user-prompt-submit.sh" && echo "$MY_CLAUDE_TEST_FLAG"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^1$'
}

@test "user-prompt-submit does not mention routo or yamless" {
  run "${BATS_TEST_DIRNAME}/user-prompt-submit.sh"
  ! echo "$output" | grep -qiE 'routo|yamless'
}
BATS
```

- [ ] **Step 4: Run bats**

Run: `bats hooks/user-prompt-submit.bats`
Expected: 3 PASS.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck hooks/user-prompt-submit.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hooks/user-prompt-submit.sh hooks/user-prompt-submit.bats
git commit -m "refactor(hooks): make user-prompt-submit project-agnostic"
```

### Task 38: Refactor `hooks/post-tools/modules/ts-quality.sh`

**Files:**
- Modify: `hooks/post-tools/modules/ts-quality.sh`
- Create: `hooks/post-tools/modules/__tests__/ts-quality.bats`

- [ ] **Step 1: Read script**

Run: `cat hooks/post-tools/modules/ts-quality.sh`

- [ ] **Step 2: Apply refactor**

- Source `lib/detect.sh` (path: `../../lib/detect.sh`).
- At top: `[ "$(detect_ts)" = "ts" ] || exit 0` (no-op when no TS in project).
- Replace hardcoded `bun`/`turbo` with: `pm=$(detect_node_pm); command -v "$pm" >/dev/null 2>&1 || exit 0`.
- Pick command per package manager:

```bash
case "$pm" in
  bun)  "$pm" run typecheck 2>&1 || true ;;
  pnpm) "$pm" -w typecheck 2>&1 || true ;;
  npm|yarn) "$pm" run typecheck 2>&1 || true ;;
esac
```

(Adjust to whatever the original script's intent is. The key: never assume `bun`.)

- [ ] **Step 3: Write bats test**

```bash
cat > hooks/post-tools/modules/__tests__/ts-quality.bats <<'BATS'
#!/usr/bin/env bats

setup() { TMP=$(mktemp -d); cd "$TMP"; git init -q; git commit --allow-empty -m init -q; }
teardown() { rm -rf "$TMP"; }

@test "ts-quality no-ops outside a TS project" {
  run "${BATS_TEST_DIRNAME}/../ts-quality.sh"
  [ "$status" -eq 0 ]
}

@test "ts-quality no-ops when no package manager detected" {
  echo '{}' > tsconfig.json
  git add tsconfig.json
  git commit -q -m tsconfig
  run "${BATS_TEST_DIRNAME}/../ts-quality.sh"
  [ "$status" -eq 0 ]
}
BATS
mkdir -p hooks/post-tools/modules/__tests__
```

- [ ] **Step 4: Run bats**

Run: `bats hooks/post-tools/modules/__tests__/ts-quality.bats`
Expected: 2 PASS.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck hooks/post-tools/modules/ts-quality.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hooks/post-tools/modules/ts-quality.sh hooks/post-tools/modules/__tests__/ts-quality.bats
git commit -m "refactor(hooks): make ts-quality package-manager-agnostic"
```

### Task 39: Refactor `hooks/pre-tools/modules/bash-commands.sh` (extract data)

**Files:**
- Modify: `hooks/pre-tools/modules/bash-commands.sh`
- Create: `settings/bash-allowlist.txt`, `settings/bash-denylist.txt`
- Create: `hooks/pre-tools/modules/__tests__/bash-commands.bats`

- [ ] **Step 1: Read script and extract embedded lists**

Run: `cat hooks/pre-tools/modules/bash-commands.sh`

Identify the in-script arrays/heredocs that hold the allow/deny commands.

- [ ] **Step 2: Write the data files**

```bash
# Replace these placeholders with the actual lists extracted from the script.
# Use the contents from whichever source repo was chosen during Phase 2 — they were
# saved to the script during Task 20.
cat > settings/bash-allowlist.txt <<'EOF'
# One command (or glob) per line. Lines starting with # are ignored.
git status
git diff
git log
EOF

cat > settings/bash-denylist.txt <<'EOF'
# Same format.
rm -rf /
EOF
```

(Engineer note: copy the exact lines from the script, do not invent the lists.)

- [ ] **Step 3: Rewrite script to read from data files**

Replace the embedded list with:

```bash
. "${BASH_SOURCE%/*}/../../lib/detect.sh"
SETTINGS_DIR=$(detect_settings_dir)
allow_file="$SETTINGS_DIR/bash-allowlist.txt"
deny_file="$SETTINGS_DIR/bash-denylist.txt"

read_list() {
  [ -f "$1" ] || return 0
  grep -vE '^\s*(#|$)' "$1"
}

allowlist=$(read_list "$allow_file")
denylist=$(read_list "$deny_file")
```

Keep the matching logic intact.

- [ ] **Step 4: Write bats test**

```bash
cat > hooks/pre-tools/modules/__tests__/bash-commands.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP"
  printf "git status\ngit diff\n" > "$TMP/bash-allowlist.txt"
  printf "rm -rf /\n"             > "$TMP/bash-denylist.txt"
}

teardown() {
  rm -rf "$TMP"
  unset MY_CLAUDE_SETTINGS_DIR
}

@test "bash-commands accepts an allowed command" {
  run env CLAUDE_TOOL_INPUT_COMMAND='git status' "${BATS_TEST_DIRNAME}/../bash-commands.sh"
  [ "$status" -eq 0 ]
}

@test "bash-commands rejects a denied command" {
  run env CLAUDE_TOOL_INPUT_COMMAND='rm -rf /' "${BATS_TEST_DIRNAME}/../bash-commands.sh"
  [ "$status" -ne 0 ]
}

@test "bash-commands runs when data files are missing" {
  rm "$TMP/bash-allowlist.txt" "$TMP/bash-denylist.txt"
  run "${BATS_TEST_DIRNAME}/../bash-commands.sh"
  [ "$status" -eq 0 ]
}
BATS
```

(Engineer note: adapt the env-var name `CLAUDE_TOOL_INPUT_COMMAND` to whatever the actual hook protocol uses — read it from the existing script.)

- [ ] **Step 5: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/bash-commands.bats`
Expected: 3 PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/bash-commands.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add hooks/pre-tools/modules/bash-commands.sh \
        settings/bash-allowlist.txt settings/bash-denylist.txt \
        hooks/pre-tools/modules/__tests__/bash-commands.bats
git commit -m "refactor(hooks): bash-commands reads allow/deny from settings"
```

### Task 40: Refactor `hooks/pre-tools/modules/code-edit-rules.sh` (extract data)

**Files:**
- Modify: `hooks/pre-tools/modules/code-edit-rules.sh`
- Create: `settings/code-edit-rules.json`
- Create: `hooks/pre-tools/modules/__tests__/code-edit-rules.bats`

- [ ] **Step 1: Read script and extract embedded rules**

Run: `cat hooks/pre-tools/modules/code-edit-rules.sh`

- [ ] **Step 2: Write data file**

```bash
# Replace placeholder with actual rules extracted from the script.
cat > settings/code-edit-rules.json <<'EOF'
{
  "rules": []
}
EOF
```

- [ ] **Step 3: Rewrite script to read from data file via jq**

```bash
. "${BASH_SOURCE%/*}/../../lib/detect.sh"
SETTINGS_DIR=$(detect_settings_dir)
rules_file="$SETTINGS_DIR/code-edit-rules.json"
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$rules_file" ] || exit 0

# Iterate and apply
jq -c '.rules[]?' "$rules_file" | while IFS= read -r rule; do
  # apply $rule to the incoming Edit/Write tool payload
  :
done
```

- [ ] **Step 4: Write bats test**

```bash
cat > hooks/pre-tools/modules/__tests__/code-edit-rules.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP"
  printf '{"rules":[]}\n' > "$TMP/code-edit-rules.json"
}

teardown() { rm -rf "$TMP"; unset MY_CLAUDE_SETTINGS_DIR; }

@test "code-edit-rules no-ops with empty rules" {
  run "${BATS_TEST_DIRNAME}/../code-edit-rules.sh"
  [ "$status" -eq 0 ]
}

@test "code-edit-rules no-ops without rules file" {
  rm "$TMP/code-edit-rules.json"
  run "${BATS_TEST_DIRNAME}/../code-edit-rules.sh"
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 5: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/code-edit-rules.bats`
Expected: 2 PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/code-edit-rules.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add hooks/pre-tools/modules/code-edit-rules.sh \
        settings/code-edit-rules.json \
        hooks/pre-tools/modules/__tests__/code-edit-rules.bats
git commit -m "refactor(hooks): code-edit-rules reads from settings"
```

### Task 41: Refactor `hooks/pre-tools/modules/commit-gate.sh`

**Files:**
- Modify: `hooks/pre-tools/modules/commit-gate.sh`
- Create: `settings/commit-prefixes.txt` (if commit-gate uses a prefix list)
- Create: `hooks/pre-tools/modules/__tests__/commit-gate.bats`

- [ ] **Step 1: Read script**

Run: `cat hooks/pre-tools/modules/commit-gate.sh`

- [ ] **Step 2: Apply refactor**

- Source `lib/detect.sh`.
- If a Conventional-Commit prefix list is hardcoded, extract to `settings/commit-prefixes.txt` (one per line) and read it the same way as Task 39.
- Replace any base-branch references with `base=$(detect_base_branch)`.
- Guard external tools with `command -v`.

- [ ] **Step 3: Write data file (if extracted)**

```bash
cat > settings/commit-prefixes.txt <<'EOF'
feat
fix
chore
docs
refactor
test
perf
build
ci
style
revert
EOF
```

- [ ] **Step 4: Write bats test**

```bash
cat > hooks/pre-tools/modules/__tests__/commit-gate.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP"
  printf "feat\nfix\nchore\n" > "$TMP/commit-prefixes.txt"
  cd "$TMP"; git init -q; git commit --allow-empty -m init -q
}
teardown() { rm -rf "$TMP"; unset MY_CLAUDE_SETTINGS_DIR; }

@test "commit-gate accepts feat: prefix" {
  run env CLAUDE_TOOL_INPUT_COMMAND='git commit -m "feat: x"' "${BATS_TEST_DIRNAME}/../commit-gate.sh"
  [ "$status" -eq 0 ]
}

@test "commit-gate rejects unknown prefix" {
  run env CLAUDE_TOOL_INPUT_COMMAND='git commit -m "wip: x"' "${BATS_TEST_DIRNAME}/../commit-gate.sh"
  [ "$status" -ne 0 ]
}
BATS
```

(Adapt env-var name to actual hook protocol.)

- [ ] **Step 5: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/commit-gate.bats`
Expected: 2 PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/commit-gate.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add hooks/pre-tools/modules/commit-gate.sh \
        settings/commit-prefixes.txt \
        hooks/pre-tools/modules/__tests__/commit-gate.bats
git commit -m "refactor(hooks): commit-gate reads prefixes from settings + uses base-branch detect"
```

### Task 42: Refactor `hooks/pre-tools/modules/protected-files.sh` (extract data)

**Files:**
- Modify: `hooks/pre-tools/modules/protected-files.sh`
- Create: `settings/protected-files.txt`
- Create: `hooks/pre-tools/modules/__tests__/protected-files.bats`

- [ ] **Step 1: Read script and extract path list**

Run: `cat hooks/pre-tools/modules/protected-files.sh`

- [ ] **Step 2: Write data file**

```bash
cat > settings/protected-files.txt <<'EOF'
# One glob per line. Edits to matching paths are blocked.
.env
.env.*
**/secrets/**
.git/**
EOF
```

(Use the actual list from the script.)

- [ ] **Step 3: Rewrite script**

Same pattern as Task 39 — read globs from the data file, then match.

- [ ] **Step 4: Write bats test**

```bash
cat > hooks/pre-tools/modules/__tests__/protected-files.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d); export MY_CLAUDE_SETTINGS_DIR="$TMP"
  printf ".env\n.git/**\n" > "$TMP/protected-files.txt"
}
teardown() { rm -rf "$TMP"; unset MY_CLAUDE_SETTINGS_DIR; }

@test "protected-files blocks .env" {
  run env CLAUDE_TOOL_INPUT_FILE_PATH='.env' "${BATS_TEST_DIRNAME}/../protected-files.sh"
  [ "$status" -ne 0 ]
}

@test "protected-files allows src/foo.ts" {
  run env CLAUDE_TOOL_INPUT_FILE_PATH='src/foo.ts' "${BATS_TEST_DIRNAME}/../protected-files.sh"
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 5: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/protected-files.bats`
Expected: 2 PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/protected-files.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add hooks/pre-tools/modules/protected-files.sh \
        settings/protected-files.txt \
        hooks/pre-tools/modules/__tests__/protected-files.bats
git commit -m "refactor(hooks): protected-files reads globs from settings"
```

### Task 43: Refactor `hooks/pre-tools/modules/quality-gate.sh`

**Files:**
- Modify: `hooks/pre-tools/modules/quality-gate.sh`
- Create: `hooks/pre-tools/modules/__tests__/quality-gate.bats`

- [ ] **Step 1: Read script**

Run: `cat hooks/pre-tools/modules/quality-gate.sh`

- [ ] **Step 2: Apply refactor**

- Guard every external tool with `command -v <tool> >/dev/null 2>&1 || continue` (or `|| exit 0` for top-level).
- Source `lib/detect.sh` and use detected package manager / language.
- Respect `MY_CLAUDE_QUALITY=off` env var: top of file, `[ "${MY_CLAUDE_QUALITY:-}" = off ] && exit 0`.

- [ ] **Step 3: Write bats test**

```bash
cat > hooks/pre-tools/modules/__tests__/quality-gate.bats <<'BATS'
#!/usr/bin/env bats
setup() { TMP=$(mktemp -d); cd "$TMP"; git init -q; git commit --allow-empty -m init -q; }
teardown() { rm -rf "$TMP"; }

@test "quality-gate exits 0 with MY_CLAUDE_QUALITY=off" {
  MY_CLAUDE_QUALITY=off run "${BATS_TEST_DIRNAME}/../quality-gate.sh"
  [ "$status" -eq 0 ]
}

@test "quality-gate exits 0 with no tooling installed in a barebones repo" {
  run "${BATS_TEST_DIRNAME}/../quality-gate.sh"
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 4: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/quality-gate.bats`
Expected: 2 PASS.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/quality-gate.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hooks/pre-tools/modules/quality-gate.sh hooks/pre-tools/modules/__tests__/quality-gate.bats
git commit -m "refactor(hooks): quality-gate guards tooling and honors MY_CLAUDE_QUALITY=off"
```

### Task 44: Refactor `tooling/context7/search.sh`

**Files:**
- Modify: `tooling/context7/search.sh`

- [ ] **Step 1: Read script**

Run: `cat tooling/context7/search.sh`

- [ ] **Step 2: Apply refactor**

- Top: `command -v jq >/dev/null 2>&1 || { echo "context7: jq required" >&2; exit 1; }` and same for `curl`.
- Read `CONTEXT7_API_KEY` from env. Do not source `.env`.
- If the script previously sourced `.env`, replace with: `[ -z "${CONTEXT7_API_KEY:-}" ] && { echo "context7: CONTEXT7_API_KEY unset" >&2; exit 1; }`.

- [ ] **Step 3: Verify bats test (already copied from yamless)**

Run: `cat tooling/__tests__/context7.bats`

Update if it sourced `.env`. The test should set `CONTEXT7_API_KEY` via env, not source a file.

- [ ] **Step 4: Run bats**

Run: `CONTEXT7_API_KEY=dummy bats tooling/__tests__/context7.bats`
Expected: PASS (or skip if it makes real HTTP — confirm with the engineer).

- [ ] **Step 5: Shellcheck**

Run: `shellcheck tooling/context7/search.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add tooling/context7/search.sh tooling/__tests__/context7.bats
git commit -m "refactor(tooling): context7 reads API key from env, guards deps"
```

### Task 45: Refactor `tooling/exa-search/search.sh`

Same template as Task 44. Env var: `EXA_API_KEY`. Commit: `refactor(tooling): exa-search reads API key from env, guards deps`.

### Task 46: Refactor `skills/code-intel/scripts/modules/engram.sh`

**Files:**
- Modify: `skills/code-intel/scripts/modules/engram.sh`

- [ ] **Step 1: Read script**

Run: `cat skills/code-intel/scripts/modules/engram.sh`

- [ ] **Step 2: Apply refactor**

- Guard: `command -v engram >/dev/null 2>&1 || exit 0`.
- Honor `ENGRAM_PORT` (default `7437`) and `ENGRAM_DIR` (default `$HOME/.engram`) — do not hardcode.

- [ ] **Step 3: Shellcheck**

Run: `shellcheck skills/code-intel/scripts/modules/engram.sh`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add skills/code-intel/scripts/modules/engram.sh
git commit -m "refactor(skills): engram module respects ENGRAM_PORT/ENGRAM_DIR"
```

### Task 47: Refactor `skills/code-intel/scripts/modules/ast-grep.sh`

**Files:**
- Modify: `skills/code-intel/scripts/modules/ast-grep.sh`

- [ ] **Step 1: Read script**

Run: `cat skills/code-intel/scripts/modules/ast-grep.sh`

- [ ] **Step 2: Apply refactor**

- Guard: `command -v sg >/dev/null 2>&1 || command -v ast-grep >/dev/null 2>&1 || exit 0`.
- Auto-detect language from file extension when caller does not provide `--lang`.

- [ ] **Step 3: Shellcheck**

Run: `shellcheck skills/code-intel/scripts/modules/ast-grep.sh`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add skills/code-intel/scripts/modules/ast-grep.sh
git commit -m "refactor(skills): ast-grep module auto-detects language"
```

### Task 48: Refactor `hooks/pre-tools/modules/mcp-blocker.sh` (extract data)

**Files:**
- Modify: `hooks/pre-tools/modules/mcp-blocker.sh`
- Create: `settings/mcp-blocklist.txt`
- Create: `hooks/pre-tools/modules/__tests__/mcp-blocker.bats`

- [ ] **Step 1: Read script**

Run: `cat hooks/pre-tools/modules/mcp-blocker.sh`

- [ ] **Step 2: Extract blocklist to data file**

```bash
cat > settings/mcp-blocklist.txt <<'EOF'
# One MCP server name (or glob) per line.
EOF
```

(Use the actual list from the script.)

- [ ] **Step 3: Rewrite script to read from data file**

Same pattern as Task 39.

- [ ] **Step 4: Write bats test**

```bash
cat > hooks/pre-tools/modules/__tests__/mcp-blocker.bats <<'BATS'
#!/usr/bin/env bats
setup() {
  TMP=$(mktemp -d); export MY_CLAUDE_SETTINGS_DIR="$TMP"
  printf "evil-mcp\n" > "$TMP/mcp-blocklist.txt"
}
teardown() { rm -rf "$TMP"; unset MY_CLAUDE_SETTINGS_DIR; }

@test "mcp-blocker blocks listed server" {
  run env CLAUDE_TOOL_INPUT_MCP_SERVER='evil-mcp' "${BATS_TEST_DIRNAME}/../mcp-blocker.sh"
  [ "$status" -ne 0 ]
}

@test "mcp-blocker allows unlisted server" {
  run env CLAUDE_TOOL_INPUT_MCP_SERVER='friend-mcp' "${BATS_TEST_DIRNAME}/../mcp-blocker.sh"
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 5: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/mcp-blocker.bats`
Expected: 2 PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/mcp-blocker.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add hooks/pre-tools/modules/mcp-blocker.sh \
        settings/mcp-blocklist.txt \
        hooks/pre-tools/modules/__tests__/mcp-blocker.bats
git commit -m "refactor(hooks): mcp-blocker reads blocklist from settings"
```

### Task 49: Refactor `hooks/pre-tools/modules/push-review.sh`

**Files:**
- Modify: `hooks/pre-tools/modules/push-review.sh`
- Verify: `hooks/pre-tools/modules/__tests__/push-review.bats` (copied in Task 5) still passes after refactor.

- [ ] **Step 1: Read script**

Run: `cat hooks/pre-tools/modules/push-review.sh`

- [ ] **Step 2: Apply refactor**

- Source `lib/detect.sh`.
- Replace any hardcoded base-branch with `base=$(detect_base_branch)`.
- Guard `gh` / `git` calls.

- [ ] **Step 3: Run bats**

Run: `bats hooks/pre-tools/modules/__tests__/push-review.bats`
Expected: PASS (test was copied from yamless and may need light adjustment to match the new detect-based base branch — update the test if needed).

- [ ] **Step 4: Shellcheck**

Run: `shellcheck hooks/pre-tools/modules/push-review.sh`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add hooks/pre-tools/modules/push-review.sh hooks/pre-tools/modules/__tests__/push-review.bats
git commit -m "refactor(hooks): push-review uses detect_base_branch"
```

### Task 50: Refactor `hooks/post-tools/modules/rust-quality.sh`

**Files:**
- Modify: `hooks/post-tools/modules/rust-quality.sh`
- Create: `hooks/post-tools/modules/__tests__/rust-quality.bats`

- [ ] **Step 1: Read script**

Run: `cat hooks/post-tools/modules/rust-quality.sh`

- [ ] **Step 2: Apply refactor**

- Source `lib/detect.sh` (path: `../../lib/detect.sh`).
- Top: `[ "$(detect_rust)" = "rust" ] || exit 0`.
- Guard: `command -v cargo >/dev/null 2>&1 || exit 0`.

- [ ] **Step 3: Write bats test**

```bash
cat > hooks/post-tools/modules/__tests__/rust-quality.bats <<'BATS'
#!/usr/bin/env bats
setup() { TMP=$(mktemp -d); cd "$TMP"; git init -q; git commit --allow-empty -m init -q; }
teardown() { rm -rf "$TMP"; }

@test "rust-quality no-ops outside a Rust project" {
  run "${BATS_TEST_DIRNAME}/../rust-quality.sh"
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 4: Run bats**

Run: `bats hooks/post-tools/modules/__tests__/rust-quality.bats`
Expected: 1 PASS.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck hooks/post-tools/modules/rust-quality.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hooks/post-tools/modules/rust-quality.sh hooks/post-tools/modules/__tests__/rust-quality.bats
git commit -m "refactor(hooks): rust-quality no-ops outside Rust projects"
```

---

## Phase 5 — Settings fragments

### Task 51: Build `settings/hooks.fragment.json`

**Files:**
- Create: `settings/hooks.fragment.json`

- [ ] **Step 1: Read source hook wiring**

Run: `jq '.hooks' settings/_raw/routo-settings.json` and `jq '.hooks' settings/_raw/yamless-settings.json`.

- [ ] **Step 2: Write the fragment**

```bash
cat > settings/hooks.fragment.json <<'EOF'
{
  "hooks": {
    "SessionStart":      [{"matcher": "startup", "hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/session-start.sh"}]}],
    "SessionEnd":        [{"hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/session-end.sh"}]}],
    "PreCompact":        [{"hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/pre-compact.sh"}]}],
    "UserPromptSubmit":  [{"hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/user-prompt-submit.sh"}]}],
    "PreToolUse":        [{"hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/pre-tools/mod.sh"}]}],
    "PostToolUse":       [{"hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/post-tools/mod.sh"}]}]
  }
}
EOF
```

(Engineer note: align matcher/command shape with what the source `settings.json` actually used. If routo/yamless had per-tool matchers, copy them.)

- [ ] **Step 3: Validate JSON**

Run: `jq . settings/hooks.fragment.json >/dev/null && echo ok`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add settings/hooks.fragment.json
git commit -m "feat(settings): add hooks.fragment.json"
```

### Task 52: Build `settings/permissions.fragment.json` (union of allowlists)

**Files:**
- Create: `settings/permissions.fragment.json`

- [ ] **Step 1: Extract allowlists**

```bash
jq '.permissions.allow // []' settings/_raw/routo-settings.json   > /tmp/r-allow.json
jq '.permissions.allow // []' settings/_raw/yamless-settings.json > /tmp/y-allow.json
jq '.permissions.deny  // []' settings/_raw/routo-settings.json   > /tmp/r-deny.json
jq '.permissions.deny  // []' settings/_raw/yamless-settings.json > /tmp/y-deny.json
```

- [ ] **Step 2: Union and dedup**

```bash
jq -n \
  --slurpfile ra /tmp/r-allow.json --slurpfile ya /tmp/y-allow.json \
  --slurpfile rd /tmp/r-deny.json  --slurpfile yd /tmp/y-deny.json \
  '{
    permissions: {
      allow: ($ra[0] + $ya[0] | unique),
      deny:  ($rd[0] + $yd[0] | unique)
    }
  }' > settings/permissions.fragment.json
```

- [ ] **Step 3: Validate**

Run: `jq . settings/permissions.fragment.json >/dev/null && echo ok`
Expected: `ok`.

- [ ] **Step 4: Eyeball for stragglers**

Run: `jq '.permissions.allow[], .permissions.deny[]' settings/permissions.fragment.json | grep -iE 'routo|yamless|/Volumes/Projects' || echo "clean"`
Expected: `clean`. If anything matches, remove with `jq` filter and re-validate.

- [ ] **Step 5: Commit**

```bash
git add settings/permissions.fragment.json
git commit -m "feat(settings): add permissions.fragment.json (union of source repos)"
```

### Task 53: Remove `settings/_raw/` stash

**Files:**
- Delete: `settings/_raw/`

- [ ] **Step 1: Remove**

```bash
git rm -r settings/_raw
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore(settings): remove _raw stash after fragment extraction"
```

---

## Phase 6 — Documentation

### Task 54: Write `tooling/README.md`

**Files:**
- Create: `tooling/README.md`

- [ ] **Step 1: Write doc**

```bash
cat > tooling/README.md <<'EOF'
# tooling/

Helper scripts that hooks and skills call into.

## Required environment variables

| Variable             | Purpose                                  |
|----------------------|------------------------------------------|
| `CONTEXT7_API_KEY`   | Authenticates `context7/search.sh`       |
| `EXA_API_KEY`        | Authenticates `exa-search/search.sh`     |

Export in your shell rc (`~/.config/fish/config.fish` or `~/.zshrc`) or load
from a secret manager (`pass`, `1password-cli`, `keyring`). Do **not** commit
a `.env` file — scripts read from `$ENV` directly.

## Tests

Run all tooling tests:

```bash
bats tooling/__tests__
```
EOF
```

- [ ] **Step 2: Commit**

```bash
git add tooling/README.md
git commit -m "docs(tooling): document required env vars and test command"
```

### Task 55: Write `settings/README.md`

**Files:**
- Create: `settings/README.md`

- [ ] **Step 1: Write doc**

```bash
cat > settings/README.md <<'EOF'
# settings/

Reusable Claude Code settings fragments plus data files consumed by hooks.

## Fragments

- `hooks.fragment.json` — `PreToolUse` / `PostToolUse` / `SessionStart` / `SessionEnd` / `UserPromptSubmit` / `PreCompact` wiring.
- `permissions.fragment.json` — union of permission allowlists/denylists from the source repos.

### Merge into your settings

```bash
jq -s '.[0] * .[1]' ~/.claude/settings.json settings/hooks.fragment.json \
  > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json

jq -s '.[0] * .[1]' ~/.claude/settings.json settings/permissions.fragment.json \
  > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

> Never add a path that contains secrets (e.g. `.env`) to `additionalDirectories`.

## Data files (read by hooks)

| File                     | Read by                              |
|--------------------------|--------------------------------------|
| `bash-allowlist.txt`     | `hooks/pre-tools/modules/bash-commands.sh` |
| `bash-denylist.txt`      | `hooks/pre-tools/modules/bash-commands.sh` |
| `code-edit-rules.json`   | `hooks/pre-tools/modules/code-edit-rules.sh` |
| `commit-prefixes.txt`    | `hooks/pre-tools/modules/commit-gate.sh`    |
| `protected-files.txt`    | `hooks/pre-tools/modules/protected-files.sh`|
| `mcp-blocklist.txt`      | `hooks/pre-tools/modules/mcp-blocker.sh`    |

Each file is plain text (one entry per line, `#` for comments) except
`code-edit-rules.json` which is JSON.

Per-project overrides: drop a file of the same name into the project's
`.claude/settings/` directory. The hook prefers `$MY_CLAUDE_SETTINGS_DIR`
(if set) before falling back to the global location.

## Env vars

| Variable                      | Effect                                  |
|-------------------------------|-----------------------------------------|
| `MY_CLAUDE_SETTINGS_DIR`      | Directory the hooks read data files from |
| `MY_CLAUDE_QUALITY`           | `off` to disable `quality-gate.sh`       |
EOF
```

- [ ] **Step 2: Commit**

```bash
git add settings/README.md
git commit -m "docs(settings): document fragments and data files"
```

### Task 56: Update `README.md` install section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add hooks/tooling/settings symlinks to the install instructions**

Use the Edit tool to replace the existing install code block with:

```bash
## Install

### Per-user (global)
```bash
ln -s "$PWD/skills"   ~/.claude/skills
ln -s "$PWD/agents"   ~/.claude/agents
ln -s "$PWD/commands" ~/.claude/commands
ln -s "$PWD/hooks"    ~/.claude/hooks
```

Merge settings fragments (see `settings/README.md`).

### Per-project
```bash
ln -s /Volumes/Projects/my-claude/skills   .claude/skills
ln -s /Volumes/Projects/my-claude/agents   .claude/agents
ln -s /Volumes/Projects/my-claude/commands .claude/commands
ln -s /Volumes/Projects/my-claude/hooks    .claude/hooks
ln -s /Volumes/Projects/my-claude/tooling  .tooling
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): expand install instructions for hooks/tooling/settings"
```

---

## Phase 7 — Verification

### Task 57: Verify full bats suite passes

**Files:** (none — verification only)

- [ ] **Step 1: Run every bats file**

```bash
bats hooks/lib/detect.bats \
     hooks/session-start.bats \
     hooks/user-prompt-submit.bats \
     hooks/pre-tools/modules/__tests__ \
     hooks/post-tools/modules/__tests__ \
     tooling/__tests__
```

Expected: every test PASS.

- [ ] **Step 2: Fix any failures**

If any test fails, return to the relevant refactor task and adjust. No new commit until green.

### Task 58: Verify shellcheck clean on every script

**Files:** (none — verification only)

- [ ] **Step 1: Run shellcheck on every .sh file**

```bash
find hooks/ tooling/ skills/ -name '*.sh' -print0 | xargs -0 shellcheck
```

Expected: no output.

- [ ] **Step 2: Fix any warnings**

If shellcheck flags an issue, fix and commit per the offending file's pattern from Phase 4.

### Task 59: Final agnosticism re-grep

**Files:** (none — verification only)

- [ ] **Step 1: Run the audit grep again**

```bash
grep -rEn 'routo|yamless|/Volumes/Projects/(routo|yamless)|console-app' \
  hooks/ tooling/ skills/ settings/ 2>/dev/null
```

Expected: no output (empty result).

- [ ] **Step 2: If any hit remains**

Treat as a bug. Open the file, remove or generalize, re-run shellcheck and bats, commit.

### Task 60: Scratch-repo install test

**Files:** (none — verification only)

- [ ] **Step 1: Create scratch repo**

```bash
SCRATCH=$(mktemp -d)
cd "$SCRATCH"
git init -q
git commit --allow-empty -m init -q
mkdir -p .claude
ln -s /Volumes/Projects/my-claude/skills   .claude/skills
ln -s /Volumes/Projects/my-claude/agents   .claude/agents
ln -s /Volumes/Projects/my-claude/commands .claude/commands
ln -s /Volumes/Projects/my-claude/hooks    .claude/hooks
ln -s /Volumes/Projects/my-claude/tooling  .tooling
```

- [ ] **Step 2: Dry-run every hook**

```bash
.claude/hooks/session-start.sh   && echo "session-start OK"
.claude/hooks/session-end.sh     && echo "session-end OK"
.claude/hooks/pre-compact.sh     && echo "pre-compact OK"
.claude/hooks/user-prompt-submit.sh && echo "user-prompt-submit OK"
.claude/hooks/pre-tools/mod.sh   && echo "pre-tools OK"
.claude/hooks/post-tools/mod.sh  && echo "post-tools OK"
```

Expected: every line prints `<name> OK` and no error mentions `routo`, `yamless`, or a missing tool.

- [ ] **Step 3: Cleanup scratch**

```bash
cd /Volumes/Projects/my-claude
rm -rf "$SCRATCH"
```

- [ ] **Step 4: Verification summary**

If steps 1–3 succeed, the consolidation is functionally complete. No commit. Move to Task 61.

### Task 61: Final summary commit

**Files:**
- Create: `docs/superpowers/plans/2026-06-07-consolidation-summary.md`

- [ ] **Step 1: Write summary**

```bash
cat > docs/superpowers/plans/2026-06-07-consolidation-summary.md <<'EOF'
# Consolidation summary — 2026-06-07

- Source repos: `/Volumes/Projects/routo.io`, `/Volumes/Projects/yamless.io`
- Target: `/Volumes/Projects/my-claude`
- Files migrated: 26 (resolved per `2026-06-07-consolidate-resolutions.log`) + 3 identical + 3 routo-only + 10 yamless-only.
- Files skipped: gitnexus skills, grepai skill, mobile-e2e command, lgpd skill, AGENTS.md, CLAUDE.md, skills-lock.json, `.env` files, `.agents/`.
- Audit + refactor: every script source `hooks/lib/detect.sh`, hardcoded lists moved to `settings/*.txt|.json`.
- Tests: bats suite under `hooks/**/__tests__/` and `tooling/__tests__/`.
- Final agnosticism re-grep: 0 hits.

Source repos still contain their `.claude/` and `.tooling/` directories. Cleanup of those is out of scope for this plan.
EOF
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-06-07-consolidation-summary.md
git commit -m "docs: consolidation summary"
```

---

## Self-review notes

- **Spec coverage:** every spec section has a task (skeleton → 1; identical/yamless-only/routo-only copies → 4–6; per-file diff loop → 8–33; agnosticism audit → 34; refactor pass → 35–50; secrets handling → covered by Tasks 44, 45, 54; settings strategy → 51–53; install → 56; verify → 57–60).
- **Out-of-scope items remain out of scope** (plugin manifest, CLAUDE.md extraction, source-repo cleanup).
- **Placeholders:** every step has a runnable command or an exact code block. The data files in Tasks 39, 40, 41, 42, 48 contain example values — engineer must copy the actual values from the source script during the task.
- **Type consistency:** detection function names (`detect_project_root`, `detect_node_pm`, `detect_base_branch`, etc.) are used consistently across Tasks 35–50.

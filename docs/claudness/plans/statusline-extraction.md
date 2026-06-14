# Plan — Extract the statusline into a standalone `statusline` plugin

## Context

The Claude Code statusline (`model | effort | ctx | gate | folder | branch | caveman`)
currently lives inside the omnibus `claudness` plugin, which auto-symlinks it into
`~/.claude/claudness/statusline.sh` on every SessionStart. Claude Code has a single
`statusLine` slot, so baking it into claudness forces it on every claudness user and
collides with caveman's own badge ambition. This change extracts it into a standalone,
optionally-installed plugin `statusline@falconiere` so the statusline is an independent
opt-in. The script is already fully self-contained (sources no claudness libs), so this
is a *move + re-home the wiring*, not a rewrite.

## Approach

- **Move, don't rewrite.** `git mv` the script and its tests so history is preserved.
  The only edits to `statusline.sh` are doc-comments (paths/title); functional code is
  byte-untouched.
- **Fresh stable path, no backward compat.** statusline owns its own namespace dir:
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline/statusline.sh`. Wiring command becomes
  `bash ~/.claude/statusline/statusline.sh`. The old `claudness/` path is abandoned.
- **Zero dependencies.** statusline declares no `dependencies` in marketplace.json /
  plugin.json. The gate segment (reads `.claude/tmp/quality-gate-status.json`) and caveman
  segment (reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active`) both degrade
  gracefully — absent file → segment vanishes — so claudness/caveman are soft, not required.
- **Single symlinked file, no `.d/` registry.** statusline is not a hook event, so unlike
  `lang-quality/hooks/register.sh` (which mirrors `*.d/*.sh` under `<spec>__name`), statusline
  ships a SessionStart hook that symlinks one file. Reuse the proven guard from
  `claudness/hooks/session-start.sh:31-37`: own the path only when it is already our symlink
  (`-L`) or absent — never clobber a user's real file. Inline the reg_root
  (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline`) so there is no claudness lib dependency.
- **claudness relinquishes ownership.** Delete the symlink block (`session-start.sh:19-38`)
  and add a guarded transitional cleanup that `rm`s the orphaned old
  `~/.claude/claudness/statusline.sh` *only if it is a symlink* (so a user's real file is safe).

## Steps

Each step lands clean (bash only; gate stays green). Ordered so the repo never has a
half-moved file referenced by a stale path.

1. **Skeleton.** Create `plugins/statusline/.claude-plugin/plugin.json` mirroring
   `lang-quality/.claude-plugin/plugin.json` shape: `name: statusline`, `version: 0.1.0`,
   description, author/homepage/repository/license as the others, `keywords`
   (`["claude-code","statusline","quality-gate","caveman"]`), and **no `dependencies` key**.

2. **Move the script** (`git mv plugins/claudness/statusline.sh plugins/statusline/statusline.sh`),
   then comment-only edits inside it:
   - line 2 title `Claudness statusline.` → `Statusline statusline.`
   - header wiring example (lines 8–11): old `~/.claude/claudness/statusline.sh` →
     `~/.claude/statusline/statusline.sh`.
   - line 85 `# --- Caveman mode (claudness ships the caveman dependency) ---` →
     `# --- Caveman mode (lights up when the caveman plugin is installed) ---`.
   Functional code (jq pass, gate/branch/caveman logic, assembly) untouched.

3. **Move the tests** (`git mv plugins/claudness/__tests__/statusline.bats
   plugins/statusline/__tests__/statusline.bats`). The suite resolves
   `SL="${BATS_TEST_DIRNAME}/../statusline.sh"`, so co-located under `statusline/__tests__/`
   it still points at `statusline/statusline.sh`. No test-body edits. CI auto-discovers it
   (`find plugins -name "*.bats"`) and the colocation check passes (it lives in `__tests__/`).

3a. **Relocate the symlink test (BLOCKER from plan-review).** `plugins/claudness/hooks/__tests__/session-start.bats`
   has a test `"session-start: symlinks the statusline to the registry root"` (lines ~37–47) that
   asserts `$CFG/claudness/statusline.sh` is a symlink to a real file — exactly the behavior step 6
   deletes. **Delete that single test case** from `session-start.bats` (the other ~10 cases stay).
   The behavior moves to statusline, so add its replacement in step 4b. `dep-warning.bats` is
   unaffected (it exercises the dependency-WARN block, not the symlink).

4. **statusline hook wiring** — two new files:
   - `plugins/statusline/hooks/hooks.json`: copy lang-quality's shape, SessionStart matcher
     `startup|resume|clear|compact`, command `${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh`.
   - `plugins/statusline/hooks/session-start.sh`: consume stdin (`cat >/dev/null`), resolve
     `statusline_src` via `$(cd "$(dirname "$0")/.." && pwd)/statusline.sh`, set
     `reg_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline"`, `mkdir -p`, then the
     `-L`-or-absent guarded `ln -sf` to `$reg_root/statusline.sh`. `exit 0`. Concise doc
     header. Mark executable (`chmod +x`).

4b. **statusline session-start test (replaces the relocated case from 3a).** New
   `plugins/statusline/hooks/__tests__/session-start.bats`, real-data/no-mocks, mirroring the
   deleted claudness case but for the fresh path: run the hook with `CLAUDE_CONFIG_DIR="$TMP/cfg"`
   and `</dev/null`, assert (i) `$TMP/cfg/statusline/statusline.sh` is a symlink (`-L`), (ii)
   `readlink` ends in `/statusline.sh` and the target is a real file (`-f`), (iii) a pre-existing
   *real* file at that path is NOT clobbered (the `-L`-or-absent guard). Lives in `__tests__/` →
   passes the colocation check, auto-discovered by CI.

5. **statusline README** — `plugins/statusline/README.md`: what the line shows, the wiring
   snippet (`bash ~/.claude/statusline/statusline.sh`, plus the `$CLAUDE_CONFIG_DIR` variant),
   the soft-dependency note (gate segment needs lang-quality/claudness writing the gate file;
   caveman segment needs caveman), and the **migration note** for existing users (install
   `statusline@falconiere`, re-point settings.json from the old `claudness/` path).

6. **claudness relinquishes the statusline** — edit `plugins/claudness/hooks/session-start.sh`:
   remove the symlink block (current lines 19–38) and replace with a short transitional cleanup
   that removes `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudness/statusline.sh` only when it is a
   symlink (`[ -L "$old" ] && rm -f "$old"`), with a comment explaining it's a one-time orphan
   sweep now that statusline owns the statusline. Also remove the now-dead
   `. "$HOOK_DIR/lib/registry.sh"` source (lines ~16–17): `claudness_registry_root` was its only
   consumer in this file and it lived inside the deleted block (verified — nothing in lines 40-end
   touches registry.sh; `claudness_enabled` is config.sh, `detect_plugin_installed` is detect.sh).

7. **Register the plugin** — add a `statusline` entry to `.claude-plugin/marketplace.json`
   `plugins[]` (after `lang-quality`): `name`, `source: ./plugins/statusline`, description,
   author, `category: productivity`, `keywords`, `license: MIT`, and **no `dependencies`**.

8. **Docs in claudness point outward:**
   - `plugins/claudness/settings/README.md` (lines 82–110): replace the Statusline section body
     with a short pointer — "the statusline moved to the `statusline` plugin; install
     `statusline@falconiere` and wire `bash ~/.claude/statusline/statusline.sh`" — or remove
     it, deferring detail to statusline/README.md.
   - `README.md`: line 62 plugin table — drop "and a gate-aware statusline" from the claudness
     row, add a `statusline` row (`0.1.0`, gate-aware statusline). Line 122 "More that comes
     with it" — reword the Gate-aware statusline bullet to note it ships in `statusline`. Lines
     160–165 file-tree — remove the `statusline.sh` line under `claudness/` and add a brief
     `statusline/` entry.

## Critical files

Create:
- `plugins/statusline/.claude-plugin/plugin.json`
- `plugins/statusline/hooks/hooks.json`
- `plugins/statusline/hooks/session-start.sh`
- `plugins/statusline/hooks/__tests__/session-start.bats` (step 4b)
- `plugins/statusline/README.md`

Move (git mv):
- `plugins/claudness/statusline.sh` → `plugins/statusline/statusline.sh`
- `plugins/claudness/__tests__/statusline.bats` → `plugins/statusline/__tests__/statusline.bats`

Edit:
- `plugins/statusline/statusline.sh` (comment-only, post-move)
- `plugins/claudness/hooks/session-start.sh` (remove block 19–38 + dead registry.sh source 16–17, add orphan cleanup)
- `plugins/claudness/hooks/__tests__/session-start.bats` (delete the relocated symlink test case — step 3a)
- `.claude-plugin/marketplace.json` (add entry)
- `plugins/claudness/settings/README.md` (statusline section → pointer)
- `README.md` (3 statusline mentions)

## Verification

- **Tests (real-data, no mocks — already the case):**
  `bats plugins/statusline/__tests__/statusline.bats` → all 8 pass (model/ctx, effort
  present/absent, gate failing/passing/absent, branch+folder, gate-via-git-root-from-subdir).
  These exercise the real script over real git repos + real gate JSON files in tmp.
- **Full suite green:** `bats $(find plugins -name "*.bats")` — confirms the claudness
  session-start edit and the move broke nothing, and the colocation invariant holds.
- **Lint:** `shellcheck plugins/statusline/hooks/session-start.sh plugins/statusline/statusline.sh
  plugins/claudness/hooks/session-start.sh` clean (repo has `.shellcheckrc`).
- **Symlink smoke test:** run `plugins/statusline/hooks/session-start.sh </dev/null` with a
  temp `CLAUDE_CONFIG_DIR`; assert `$CLAUDE_CONFIG_DIR/statusline/statusline.sh` exists, is a
  symlink, points at the plugin's `statusline.sh`, and that a pre-existing *real* file at that
  path is NOT clobbered.
- **Render smoke test:** `printf '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":45000,"used_percentage":22}}' | bash ~/.claude/statusline/statusline.sh`
  → prints `Opus … ctx:45k/200k (22%)`.
- **Orphan cleanup:** create a symlink at `$CLAUDE_CONFIG_DIR/claudness/statusline.sh`, run the
  edited claudness session-start, assert it's gone; create a *real file* there, run again, assert
  it survives.
- **JSON validity:** `jq . .claude-plugin/marketplace.json plugins/statusline/.claude-plugin/plugin.json plugins/statusline/hooks/hooks.json`.

## Open risk (document, don't fix)

Existing users who currently get the statusline auto-wired via claudness will lose it on
upgrade until they `/plugin install statusline@falconiere` and re-point `settings.json` to
`bash ~/.claude/statusline/statusline.sh`. The orphan-cleanup in step 6 removes the dangling
old symlink so it fails loudly (missing file) rather than silently pointing into a cleaned
cache. This breaking change is surfaced in `statusline/README.md` and the claudness README/
settings docs. Accepted in brainstorm (backward compat explicitly waived).

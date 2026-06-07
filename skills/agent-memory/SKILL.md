---
name: agent-memory
description: "ALWAYS ACTIVE — Persistent memory protocol. You MUST save decisions, conventions, bugs, and discoveries to engram proactively. Do NOT wait for the user to ask."
---
# Agent Memory-First Protocol
You have Engram persistent memory (SQLite + FTS5) accessed through the **scoped wrapper** at `.claude/skills/code-intel/scripts/mod.sh engram …`.
This protocol is **MANDATORY and ALWAYS ACTIVE**.

## Hard Constraints (Always)
- Memory is required for recall and save.
- **EVERY save/recall MUST be scoped to a project.** The wrapper auto-detects the current project via `detect_project_name` (git toplevel basename). Raw `engram` calls without `--project` are blocked by the `engram-scope` pre-tool hook.
- Before ANY save or recall, the agent MUST state which project it is scoping (e.g. `Scope: claudness`). Wrong scope = wrong memories = wasted tokens or contaminated context.
- Global quality gate is blocking — do not switch tasks while any errors/warnings/tests fail (even unrelated).
- Test policy — NO mock-data tests. Use real-world data/integration paths.
- Keep memory entries compact, structured, and searchable.

## Project Scope — How to Decide

| Situation | Scope |
|---|---|
| Working in CWD that is a git repo | basename of `git rev-parse --show-toplevel` (the wrapper handles this) |
| Override needed (cross-repo work) | `MY_CLAUDE_ENGRAM_PROJECT=<name>` env var before the call |
| Not in a git repo | Wrapper falls back to `unknown` — set `MY_CLAUDE_ENGRAM_PROJECT` explicitly |

Announce the scope in user-facing text before performing the operation. Example:
> Scoping engram to **claudness** for recall on "error handling rules".

## CLI Reference — Use the Wrapper

The wrapper at `.claude/skills/code-intel/scripts/mod.sh engram <subcmd>` auto-injects `--project <current-project>` and strict cross-project filtering. **Never use MCP tools for engram.** Raw `engram` invocations are denied by the `engram-scope` hook unless they include `--project`.

### Save a memory
```bash
.claude/skills/code-intel/scripts/mod.sh engram save "<title>" "<content>" --type TYPE --topic TOPIC_KEY --scope SCOPE
```
- `<title>`: Short, searchable title (required)
- `<content>`: Structured content (required)
- `--type`: `bugfix` | `decision` | `architecture` | `discovery` | `pattern` | `config` | `learning` | `session_summary` | `prompt`
- `--topic`: Topic key for upserts — same key updates existing observation
- `--scope`: `project` (default) or `personal`
- `--project` is auto-injected by the wrapper.

### Search memories
```bash
.claude/skills/code-intel/scripts/mod.sh engram search "<query>" --type TYPE --limit N --scope SCOPE
```
Returns compact results with observation IDs. Default limit: 10, max: 20. Results are strict-filtered to the current project.

### Timeline (context around an observation)
```bash
.claude/skills/code-intel/scripts/mod.sh engram timeline <observation_id> --before N --after N
```
Observation IDs already belong to a single project — no extra scope flag needed.

### Recent context
```bash
.claude/skills/code-intel/scripts/mod.sh engram context
```
Loads recent sessions and observations for the current project. Use at session start.

### Statistics (global by design)
```bash
engram stats
```
Stats are project-less by design; the wrapper still works (`mod.sh engram stats`) but raw `engram stats` is also allowed.

## 1. Memory Before Files — Layered Recall

Before exploring the codebase to *understand* something, search **engram first**, then fall back to **ast-grep** for structural patterns and **Grep** for exact literals. Never jump straight to Read/Grep/Glob for *understanding* (as opposed to known-file reads).

State the project scope before searching. All commands below use the auto-scoping wrapper.

```
Need to understand something?
│
├─ Architecture/structure question
│   ├─ mod.sh engram search "architecture <module>" → past decisions
│   ├─ Hit  → use it
│   └─ Miss → ast-grep on relevant declarations, then Grep on keywords.
│              Save findings back via `mod.sh engram save` (--topic architecture/<module>).
│
├─ Where is the code for X?
│   ├─ mod.sh engram search "file-map <area>" → cached path
│   ├─ Hit  → go directly to likely files, verify
│   └─ Miss → ast-grep for the call/def shape, or Grep for a literal name.
│              Save mapping via `mod.sh engram save` (--topic file-map/<area>).
│
├─ How does pattern X work?
│   ├─ mod.sh engram search "pattern <name>"
│   ├─ Hit  → use/validate
│   └─ Miss → ast-grep for the pattern shape, Read the hits, then save
│              (--topic pattern/<name>).
│
├─ What calls / what does Y call?
│   └─ ast-grep for the call shape (e.g. `$_.Y($$$)`) or Grep for the symbol.
│
└─ What was decided about X?
    ├─ mod.sh engram search "decision <topic>"
    ├─ Hit  → reference and verify in docs/git if needed
    └─ Miss → check docs/git, then save
```

**Skip memory + structural search** (go straight to files) when:
- User explicitly says "read this file" or asks to edit a specific file
- Running tests, builds, or git commands (execution, not knowledge)
- Checking current state (git status/diff, file contents you need to modify)
- Exact text/import search → use Grep
- Path/filename pattern → use Glob

**Self-check**: *"Am I about to read files just to understand something I might already know from a previous session, or that ast-grep / Grep could surface in one shot?"*

See also: `skills/ast-grep/SKILL.md` for structural search and rewrite.

## 2. Save What You Learn
After any exploration that yields **reusable knowledge**, save (announce the scope first):
```bash
.claude/skills/code-intel/scripts/mod.sh engram save "<title>" "<content>" --type TYPE --topic "category/key"
```
### When to save (mandatory)
- Architecture or design decision made
- File purpose/location discovered during exploration
- Pattern documented or identified
- Bug fixed (include root cause)
- Convention established or clarified
- Gotcha, edge case, or unexpected behavior found
- User preference or constraint learned
- Configuration change or environment setup
- Quality gate/e2e failure discovered (save failing command + symptom)
- Quality gate/e2e fix validated (save what changed and why it worked)
### Self-check after EVERY task
> "Did I just make a decision, fix a bug, learn something non-obvious, or establish a convention? If yes → save NOW."
> "Did I just hit/fix a quality or e2e gate? If yes → save NOW."
> "Did I name the project scope before calling engram?"
### Topic key convention
| Category | Key format | Example |
|---|---|---|
| Architecture | `architecture/<module>` | `architecture/api-routing` |
| File map | `file-map/<area>` | `file-map/pipeline-queries` |
| Pattern | `pattern/<name>` | `pattern/query-hooks` |
| Decision | `decision/<topic>` | `decision/state-management` |
| Bug fix | `bugfix/<description>` | `bugfix/canvas-drag-offset` |
| Convention | `convention/<name>` | `convention/import-aliases` |
| Gotcha | `gotcha/<description>` | `gotcha/orpc-client-types` |
Same `--topic` key = upsert (updates existing). New topic = new observation.
### Content format
```
**What**: One sentence — what was done/learned
**Why**: What motivated it
**Where**: Files or paths affected
**Learned**: Gotchas, edge cases (omit if none)
```
### Example save (with explicit scope announcement)
> Scoping engram to **claudness** for save: decision/auth-middleware.
```bash
.claude/skills/code-intel/scripts/mod.sh engram save "JWT auth middleware" "**What**: Added JWT validation middleware\n**Why**: API routes needed authentication\n**Where**: src/middleware/auth.ts\n**Learned**: Must set httpOnly flag on cookies" --type decision --topic "decision/auth-middleware"
```

## 3. Search Protocol (Progressive Disclosure)
Don't dump everything. Drill in layer by layer:
```
1. mod.sh engram search "keywords"                       → keyword candidates (auto-scoped)
2. mod.sh engram timeline <id> --before 5 --after 5      → surrounding context
```
Start at layer 1. Only go deeper if the compact result isn't enough.
**When to search:**
- User asks to recall anything ("remember", "what did we do", "acordate", "que hicimos")
- Starting work on something that might overlap past sessions
- User mentions a topic you have no context on
- Before exploring files to understand architecture/patterns

## 4. Session Lifecycle
### Session start (recommended)
At the start of a session, announce the project scope, then load context:
```bash
.claude/skills/code-intel/scripts/mod.sh engram context
```
### Realtime saves (mandatory)
Save learnings immediately as they happen — after every decision, bugfix, discovery, or pattern. Do NOT defer to session end. Announce scope before each save.
### Post-compaction recovery
If you see a compaction message or "FIRST ACTION REQUIRED":
1. Announce the project scope.
2. Call `.claude/skills/code-intel/scripts/mod.sh engram context` to recover previous session context.
3. Only THEN continue working.

## 5. Raw CLI Fallback (rare)
Only use raw `engram` directly when the wrapper is unavailable AND you can pass `--project` explicitly. The `engram-scope` pre-tool hook denies raw calls missing `--project`. Format:
```bash
engram <subcmd> … --project <project-name>
```
or
```bash
ENGRAM_PROJECT=<project-name> engram <subcmd> …
```
Prefer the wrapper.

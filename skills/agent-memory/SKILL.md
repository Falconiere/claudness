---
name: agent-memory
description: "ALWAYS ACTIVE — Persistent memory protocol. You MUST save decisions, conventions, bugs, and discoveries to engram proactively. Do NOT wait for the user to ask."
---
# Agent Memory-First Protocol
You have Engram persistent memory (SQLite + FTS5) via the `engram` CLI.
This protocol is **MANDATORY and ALWAYS ACTIVE**.
## Hard Constraints (Always)
- Memory is required for recall and save (`engram`).
- Global quality gate is blocking:
  - Do not switch tasks while any errors/warnings/tests fail (even unrelated).
- Test policy:
  - NO mock-data tests. Use real-world data/integration paths.
- Keep memory entries compact, structured, and searchable.
## CLI Reference
All memory operations use the `engram` CLI via Bash. **Never use MCP tools for engram.**
### Save a memory
```bash
engram save "<title>" "<content>" --type TYPE --project PROJECT --topic TOPIC_KEY --scope SCOPE
```
- `<title>`: Short, searchable title (required)
- `<content>`: Structured content (required)
- `--type`: `bugfix` | `decision` | `architecture` | `discovery` | `pattern` | `config` | `learning` | `session_summary` | `prompt`
- `--project`: Project name (use current project name)
- `--topic`: Topic key for upserts — same key updates existing observation
- `--scope`: `project` (default) or `personal`
### Search memories
```bash
engram search "<query>" --type TYPE --project PROJECT --limit N --scope SCOPE
```
Returns compact results with observation IDs. Default limit: 10, max: 20.
### Timeline (context around an observation)
```bash
engram timeline <observation_id> --before N --after N
```
Shows chronological context surrounding a specific observation.
### Recent context
```bash
engram context [project]
```
Shows recent sessions and observations. Use at session start.
### Statistics
```bash
engram stats
```
## 1. Memory Before Files — Layered Recall

Before exploring the codebase to *understand* something, search **engram first**, then fall back to **ast-grep** for structural patterns and **Grep** for exact literals. Never jump straight to Read/Grep/Glob for *understanding* (as opposed to known-file reads).

```
Need to understand something?
│
├─ Architecture/structure question
│   ├─ engram search "architecture <module>" → past decisions
│   ├─ Hit  → use it
│   └─ Miss → ast-grep on relevant declarations, then Grep on keywords.
│              Save findings back to engram (--topic architecture/<module>).
│
├─ Where is the code for X?
│   ├─ engram search "file-map <area>" → cached path
│   ├─ Hit  → go directly to likely files, verify
│   └─ Miss → ast-grep for the call/def shape, or Grep for a literal name.
│              Save mapping to engram (--topic file-map/<area>).
│
├─ How does pattern X work?
│   ├─ engram search "pattern <name>"
│   ├─ Hit  → use/validate
│   └─ Miss → ast-grep for the pattern shape, Read the hits, then save
│              (--topic pattern/<name>).
│
├─ What calls / what does Y call?
│   └─ ast-grep for the call shape (e.g. `$_.Y($$$)`) or Grep for the symbol.
│
└─ What was decided about X?
    ├─ engram search "decision <topic>"
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
After any exploration that yields **reusable knowledge**, save:
```bash
engram save "<title>" "<content>" --type TYPE --project <your-project> --topic "category/key"
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
### Example save
```bash
engram save "JWT auth middleware" "**What**: Added JWT validation middleware\n**Why**: API routes needed authentication\n**Where**: src/middleware/auth.ts\n**Learned**: Must set httpOnly flag on cookies" --type decision --project <your-project> --topic "decision/auth-middleware"
```
## 3. Search Protocol (Progressive Disclosure)
Don't dump everything. Drill in layer by layer:
```
1. engram search "keywords"                              → keyword candidates
2. engram timeline <id> --before 5 --after 5             → surrounding context
```
Start at layer 1. Only go deeper if the compact result isn't enough.
**When to search:**
- User asks to recall anything ("remember", "what did we do", "acordate", "que hicimos")
- Starting work on something that might overlap past sessions
- User mentions a topic you have no context on
- Before exploring files to understand architecture/patterns
## 4. Session Lifecycle
### Session start (recommended)
At the start of a session, load context:
```bash
engram context <your-project>
```
### Realtime saves (mandatory)
Save learnings immediately as they happen — after every decision, bugfix, discovery, or pattern. Do NOT defer to session end.
### Post-compaction recovery
If you see a compaction message or "FIRST ACTION REQUIRED":
1. Call `engram context <your-project>` to recover previous session context
2. Only THEN continue working

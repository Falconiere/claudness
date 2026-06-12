---
name: code-intel
description: >
  Code intelligence — structural search and persistent memory.
  Use this skill for ANY code search, exploration, or memory recall.
  Trigger when: finding where something is defined or used, searching for code
  patterns (function signatures, impl blocks, trait impls), recalling or saving
  discoveries, or simple "where is X" and "find this function" queries.
---

# Code Intelligence

All code search and memory goes through the wrapper bundled with this skill (`scripts/mod.sh` inside the skill directory):
```
${CLAUDE_PLUGIN_ROOT}/skills/code-intel/scripts/mod.sh <tool> <subcommand> [args...]
```

## Pick the Right Tool

| You want to... | Tool | Command |
|---|---|---|
| Find structural patterns (fn, impl, trait) | ast-grep | `mod.sh ast-grep search 'fn $NAME($$$)' --lang rust` |
| Recall past discoveries | comemory | `mod.sh comemory search "topic"` |
| Save a discovery | comemory | `mod.sh comemory save "title" "content" --kind <kind>` |
| Browse stored memories | comemory | `mod.sh comemory list` |
| Exact literal string | Grep | After ast-grep returned nothing, or non-code files |
| Find files by path/glob | Glob | File finding only |

### Why this order matters

**ast-grep** understands syntax — finds structural patterns like "all async functions returning Result" that regex cannot express reliably. First choice on code files (`.rs`, `.ts`, `.tsx`, `.js`).

**Grep** matches bytes — fast but blind to structure. Valid for exact literals after ast-grep, or directly on non-code files (`*.toml`, `*.md`, `*.yaml`).

**Glob** finds files by path pattern — irreplaceable for "where is file X".

## Memory (comemory)

The wrapper auto-injects `--repo <current-repo>` (git toplevel basename). Recall is query-driven — there is no argless context dump.

| When | Command |
|---|---|
| Session start / after compaction | `mod.sh comemory search "<current task>"` |
| Before working on a topic | `mod.sh comemory search "topic"` |
| After bugfix/decision/discovery | `mod.sh comemory save "title" "content" --kind <kind>` |
| Browse stored memories | `mod.sh comemory list [--kind <kind>]` |
| Save a session summary | `mod.sh comemory summary "<recap>"` |
| Data-dir / index health | `mod.sh comemory stats` |

`--kind` enum: `decision` | `bug` | `convention` | `discovery` | `pattern` | `note` (default `note`). Add `--tags "a,b"` to categorize. comemory auto-warns on near-duplicates; pass `--supersedes <id>` to replace an outdated memory.

### Save template

```bash
mod.sh comemory save "verb what in file-or-module" \
  "## What\n<changed>\n## Why\n<rationale>\n## Where\n<file:function>\n## Watch Out\n<gotchas>" \
  --kind bug --tags "area,subtopic"
```

## Token Discipline

| Tool | Default flags (baked in) | Cost if ignored |
|---|---|---|
| `ast-grep` | `--color never`, text output | 10-99x with `--json` |

## Advanced Usage

- **Complex ast-grep rules** (inline YAML, scan): read `references/ast-grep-advanced.md`

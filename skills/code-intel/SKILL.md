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

All code search and memory goes through:
```
.claude/skills/code-intel/scripts/mod.sh <tool> <subcommand> [args...]
```

## Pick the Right Tool

| You want to... | Tool | Command |
|---|---|---|
| Find structural patterns (fn, impl, trait) | ast-grep | `mod.sh ast-grep search 'fn $NAME($$$)' --lang rust` |
| Recall past discoveries | engram | `mod.sh engram search "topic"` |
| Save a discovery | engram | `mod.sh engram save "title" "content" --type <type>` |
| Restore session context | engram | `mod.sh engram context` |
| Exact literal string | Grep | After ast-grep returned nothing, or non-code files |
| Find files by path/glob | Glob | File finding only |

### Why this order matters

**ast-grep** understands syntax — finds structural patterns like "all async functions returning Result" that regex cannot express reliably. First choice on code files (`.rs`, `.ts`, `.tsx`, `.js`).

**Grep** matches bytes — fast but blind to structure. Valid for exact literals after ast-grep, or directly on non-code files (`*.toml`, `*.md`, `*.yaml`).

**Glob** finds files by path pattern — irreplaceable for "where is file X".

## Memory (engram)

| When | Command |
|---|---|
| Session start / after compaction | `mod.sh engram context` |
| Before working on a topic | `mod.sh engram search "topic"` |
| After bugfix/decision/discovery | `mod.sh engram save "title" "content" --type <type>` |
| Context around an observation | `mod.sh engram timeline <id>` |
| Full content of observation | `mod.sh engram get <id>` |

### Save template

```bash
mod.sh engram save "verb what in file-or-module" \
  "## What\n<changed>\n## Why\n<rationale>\n## Where\n<file:function>\n## Watch Out\n<gotchas>" \
  --type bugfix --topic "area/subtopic"
```

## Token Discipline

| Tool | Default flags (baked in) | Cost if ignored |
|---|---|---|
| `ast-grep` | `--color never`, text output | 10-99x with `--json` |

## Advanced Usage

- **Complex ast-grep rules** (inline YAML, scan): read `references/ast-grep-advanced.md`

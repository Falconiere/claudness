# Stats plugin test fixtures

These fixtures drive the bats tests for the **stats** plugin. They are real
Claude Code transcripts that have been **projected down** to only the fields
stats reads — all conversation text is stripped (privacy: this is a public
repo). The token **numbers are byte-identical to the real data**; nothing is
fabricated.

## How they were produced

`dup.jsonl`, `straddle.jsonl`, `sub-session.jsonl`, and
`sub-session/subagents/agent-*.jsonl` are copied verbatim from the proven
`plugins/statusline/__tests__/fixtures/` set (already projected/stripped — see
that README for their source transcripts and recorded token totals).

The stats-specific fixtures (`multimodel.jsonl`, `nocwd.jsonl`,
`malformed.jsonl`) keep only `type=="assistant"` lines, projected to exactly the
fields stats reads (NDJSON, one object per line). The projection keeps the full
`usage` block, `model`, `id`, `timestamp`, `cwd`, `attributionSkill`,
`gitBranch`, and tool-call **names only** (`tool_use` blocks reduced to
`{type, name}`, no `.input`). Every other content block (`thinking`, `text`, …)
is dropped, so no conversation text and no `.input` payload survives:

```sh
jq -c 'select(.type=="assistant")
       | {type, timestamp, sessionId, isSidechain, cwd, attributionSkill, gitBranch,
          message: {id: .message.id, model: .message.model, usage: .message.usage,
                    content: ((.message.content // [])
                              | if type=="array"
                                then (map(select(.type=="tool_use") | {type, name}))
                                else [] end)}}' \
   SOURCE.jsonl > FIXTURE.jsonl
```

## Fixtures

- **`dup.jsonl`** — streaming-duplicate **dedup**: 50 assistant lines, 25
  distinct `message.id` (each id twice). Naive vs deduped sums differ, proving
  stats must dedupe by `message.id`.
- **`straddle.jsonl`** — Monday-midnight **day/week boundary**: spans
  `2026-W23 → 2026-W24` (crosses `2026-06-08 00:00 UTC`); under `TZ=UTC` stats
  must split into two periods.
- **`sub-session.jsonl`** (+ `sub-session/subagents/agent-*.jsonl`) — **subagent
  rollup**: main transcript (`isSidechain=false`, model `claude-opus-4-8`) plus
  three sidechain `agent-*.jsonl` (`isSidechain=true`, model
  `claude-haiku-4-5-20251001`). Exercises folding subagent tokens into the
  parent **and** two distinct models in one session.
- **`multimodel.jsonl`** — **cwd + tools + ≥2 models**: 8 assistant lines, every
  line carries `.cwd` (`/Volumes/Projects/toolu.sh`), `attributionSkill`, and
  `gitBranch`; two distinct models (`claude-opus-4-8`,
  `claude-haiku-4-5-20251001`) and at least one `tool_use` block (`Bash`). The 4
  opus lines come from a real
  `~/.claude/projects/-Volumes-Projects-toolu-sh/` transcript; the 4 haiku lines
  are real subagent lines projected the same way with `cwd` set to the shared
  path so they belong to this session.
- **`nocwd.jsonl`** — **slug fallback**: `multimodel.jsonl` with the `.cwd` field
  deleted from every line (`jq -c 'del(.cwd)'`). Exercises stats' fallback to the
  project slug when no `cwd` is present.
- **`malformed.jsonl`** — **bad-line skip**: 4 lines = 3 valid projected
  assistant lines plus one truncated/garbage line (line 3, not valid JSON).
  Exercises stats skipping unparseable lines without aborting the scan.

## Validation

```sh
# multimodel contracts
jq -rs '[.[].message.model]|unique' multimodel.jsonl              # >= 2 models
jq -rs '[.[]|select(.cwd==null)]|length' multimodel.jsonl        # == 0
jq -rs '[.[].message.content[]?|select(.type=="tool_use").name]|length' multimodel.jsonl  # >= 1
grep -c '"text"'  multimodel.jsonl                               # == 0 (no text)
grep -c '"input"' multimodel.jsonl                               # == 0 (no tool input)

# nocwd: no line retains .cwd
jq -rs '[.[]|select(has("cwd"))]|length' nocwd.jsonl             # == 0

# malformed: exactly one line fails to parse
n=0; while IFS= read -r l; do echo "$l" | jq -e . >/dev/null 2>&1 || n=$((n+1)); done < malformed.jsonl; echo "$n"  # == 1
```

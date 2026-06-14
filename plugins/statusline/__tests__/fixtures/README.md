# Statusline token-ledger test fixtures

These fixtures drive the bats tests for the statusline **weekly token ledger**.
They are real Claude Code transcripts that have been **projected down** to only
the fields the ledger reads — all conversation text is stripped (privacy: this
is a public repo). The token **numbers are byte-identical to the real data**;
nothing is fabricated.

## How they were produced

Every fixture keeps only `type=="assistant"` lines, projected to exactly the
fields the hook sums (NDJSON, one object per line):

```sh
jq -c 'select(.type=="assistant")
       | {type, timestamp, sessionId, isSidechain,
          message: {id: .message.id, model: .message.model, usage: .message.usage}}' \
   SOURCE.jsonl > FIXTURE.jsonl
```

This preserves `message.id`, `timestamp`, and the **full `usage` block**
(`input_tokens` / `output_tokens` / `cache_creation_input_tokens` /
`cache_read_input_tokens`, plus the nested `cache_creation`, `iterations`, …)
— everything the ledger touches — while dropping every text field. No
`content` / `text` key survives the projection.

## The ledger's week/token computation

The recorded numbers below come from running the hook's grouping jq over each
fixture. It dedupes streaming duplicates by `message.id`, buckets by ISO week of
the local time, and sums `input + output + cache_creation`:

```sh
jq -s '[ .[] | select(.type=="assistant")
              | select(.message.id != null and .timestamp != null)
       | { id:.message.id,
           week:(.timestamp | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601
                            | strflocaltime("%G-W%V")),
           t:((.message.usage.input_tokens//0)
             +(.message.usage.output_tokens//0)
             +(.message.usage.cache_creation_input_tokens//0)) } ]
     | group_by(.id) | map(.[0]) | group_by(.week)
     | map({week:.[0].week, tokens:(map(.t)|add)})
     | .[] | "\(.week)\t\(.tokens)"' FIXTURE.jsonl
```

> **Timezone:** the ledger uses `strflocaltime`, so the week boundary is
> evaluated in the machine's local TZ. The recorded values below — and the bats
> tests — pin **`TZ=UTC`** so the Monday-00:00 week boundary is deterministic.
> Under a different TZ the straddle fixture collapses into a single week.

## Fixtures

### `straddle.jsonl` — Monday-midnight week straddle
- **Source:** `~/.claude/projects/-Volumes-Projects-toolu/57723639-b7eb-4965-a312-a354bf8b8b34.jsonl`
- **Span:** `2026-06-07T22:42:23Z` (Sun, W23) → `2026-06-08T01:46:07Z` (Mon, W24).
  June 8 2026 is a Monday, so the messages cross the `2026-06-08 00:00 UTC` ISO-week
  boundary. The ledger jq must emit **exactly two** week lines.
- **Lines:** 414 assistant lines, 254 distinct `message.id`.

  | week (TZ=UTC) | tokens  |
  |---------------|---------|
  | `2026-W23`    | 397944  |
  | `2026-W24`    | 389786  |

### `dup.jsonl` — streaming-duplicate dedup
- **Source:** head-50 slice of
  `~/.claude/projects/-Volumes-Projects-workflows/24329ca0-51fd-4633-8379-f96f95daf916.jsonl`
- **Why:** Claude Code writes one assistant line per streamed token batch, so the
  same `message.id` appears multiple times. The ledger must dedupe by
  `message.id` (`group_by(.id) | map(.[0])`) or it double-counts.
- **Counts:** 50 assistant lines, **25 distinct** `message.id` (each id appears
  exactly twice — clean streaming duplicates).
- **All in week `2026-W24`** (timestamps `2026-06-08T16:41Z`…`16:48Z`).

  | sum            | tokens  |
  |----------------|---------|
  | naive (no dedup, all 50 lines) | 358012 |
  | **deduped** (ledger jq)        | 148517 |

  The naive and deduped sums **differ** (358012 ≠ 148517) — this is the assertion
  that proves dedup matters.

### `sub-session.jsonl` (+ `sub-session/subagents/agent-*.jsonl`) — subagent rollup
- **Source:** `~/.claude/projects/-Volumes-Projects-comemory/f71d25e9-2335-497f-89a5-da70be8a8bef.jsonl`
  plus its three `subagents/agent-*.jsonl` files.
- **Layout:** matches the hook's derivation
  `${transcript_path%.jsonl}/subagents/agent-*.jsonl` — i.e. when the main
  transcript is `…/fixtures/sub-session.jsonl`, the sidechain transcripts live in
  `…/fixtures/sub-session/subagents/`.
  - `sub-session.jsonl` — main transcript: 10 assistant lines, 3 distinct ids,
    `isSidechain=false`.
  - `sub-session/subagents/agent-a36c2dc0b9d8e2dd8.jsonl` — 66 lines, 27 ids
  - `sub-session/subagents/agent-a3a3a7a7bf5a904ad.jsonl` — 68 lines, 35 ids
  - `sub-session/subagents/agent-ae63b21461c9caeed.jsonl` — 65 lines, 37 ids
  - Subagent lines are `isSidechain=true`; their 99 distinct ids have **zero
    overlap** with the main's 3, so they genuinely add tokens (no dedup absorption).
- **All in week `2026-W24`** (timestamps `2026-06-14T00:14Z`…`00:19Z`).

  | input                       | week `2026-W24` tokens |
  |-----------------------------|------------------------|
  | main only                   | 56030                  |
  | **main + 3 subagents**      | 268219                 |
  | delta (subagent tokens)     | +212189                |

  Folding in the subagent transcripts **increases** the weekly total — the
  assertion that proves the subagent rollup works.

## Validation

All `.jsonl` parse as NDJSON (prints nothing on success):

```sh
for f in *.jsonl sub-session/subagents/*.jsonl; do
  jq -e . "$f" >/dev/null || echo "BAD: $f"
done
```

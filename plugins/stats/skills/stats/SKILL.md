---
name: stats
description: "Visual terminal dashboard of measured Claude Code usage — tokens, cost, cache-hit rate, and toolu activity — read straight from your session transcripts (measured, not estimated), with an optional self-contained HTML report (--html). Use when asked 'what did this week cost', 'which project/model burns the most tokens', 'my cache-hit rate', 'usage stats', or '/stats'."
---

# stats

`/stats` reports what your Claude Code work actually consumed — tokens, $ cost, and cache-hit rate — read straight from the on-disk session transcripts (`${CLAUDE_CONFIG_DIR:-~/.claude}/projects/**/*.jsonl`). It is the measured, first-party counterpart to the statusline's `wk:` sliver: where the statusline shows the current week at a glance, `stats` gives the full breakdown on demand.

The default view is a glyph dashboard — a boxed header with a cache-hit gauge, a 14-day sparkline trend, and bar charts per project/model — that renders identically wherever it is shown (no ANSI). `--html` exports the same report as a self-contained, themeable HTML file and opens it in your browser.

## What it reports

- **Economics** — tokens, estimated $ cost (per-model rates), cache-hit %.
- **Time windows** — today, this week, all-time.
- **Per project** — which repo burns the most (grouped on the exact working dir, not a label).
- **Per model** — Opus / Sonnet / Haiku split (the model-routing lever).
- **Per session** — top sessions by tokens/cost.
- **toolu activity** — tool-mix, workflow-phase counts, current quality-gate status, comemory count.

## How it works

Transcripts are the source of truth. Each session is rolled up once and memoized at `${CLAUDE_CONFIG_DIR:-~/.claude}/stats/sessions/<id>.json`, keyed on the transcript mtime plus a schema/pricing fingerprint — so a re-run is cheap, and a pricing change recomputes rather than serving stale cost. An actively-written session busts its own cache automatically (its mtime advances), and `--this-session` always recomputes fresh. Deleting a session's transcript drops it from the totals.

## Usage

```sh
/stats                       # full digest: economics + all breakdowns
/stats --today               # just today
/stats --week                # current ISO week
/stats --project toolu.sh    # one project
/stats --model opus          # one model tier
/stats --this-session        # this session only (caveman-stats style)
/stats --html                # write a self-contained HTML report and open it
/stats --json                # machine-readable aggregate
/stats --rescan              # ignore the cache, recompute from transcripts
```

Cost is a sticker-price **estimate**, not an Anthropic bill. Requires `jq`; without it `/stats` prints a one-line notice and exits cleanly.

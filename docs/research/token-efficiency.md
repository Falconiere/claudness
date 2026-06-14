# Token Efficiency: Investigation Report

> Branch: `investigate-token-efficiency` · Date: 2026-06-14 · Scope: audit of toolu's own token-efficiency claims, a survey of external state-of-the-art, and concrete improvements for toolu.

## TL;DR

toolu markets its **weakest** token lever the hardest (caveman output compression, advertised at "~75%") and barely markets its **strongest** ones (prompt-cache discipline, targeted/structural reads, subagent context isolation).

In a long agentic coding session **input dominates cost** (≈25:1 input:output by volume), and within input, **cache reads dominate everything**. The levers that move real money, in order:

1. **Cache discipline** — 45–80% measured cost reduction. *Not audited in toolu.*
2. **Targeted/structural reads** (ast-grep, comemory) — ~10x token reduction on code access (peer-reviewed). *Enforced but unmeasured in-repo.*
3. **Subagent context isolation** (cavecrew/Explore) — accounts for ~80% of multi-agent performance variance. *Used, but carries a fabricated "60%" number.*
4. **Model routing** (Haiku/Sonnet/Opus tiers) — 75–85% cost cut at ~95% quality. *Used ad hoc, not formalized.*
5. **Output compression** (caveman) — real but secondary (~11–33% of cost depending on cache-hit rate); the academic-weakest compression family. *Marketed hardest; metric and README are wrong.*

**Net actions: fix the metric, audit caching, formalize routing.** Keep caveman — as an honest secondary lever, not the headline.

---

## 1. The cost model

Per-turn bill (Anthropic, model-agnostic multipliers):

```
cost = uncached_input·1x + cache_read·0.1x + cache_write_5m·1.25x + cache_write_1h·2x + output·5x
```

2026 sticker prices ($/M tokens):

| Model | Input | Output | Output ÷ Input |
|---|---|---|---|
| Opus 4.8 | $5.00 | $25.00 | 5x |
| Sonnet 4.6 | $3.00 | $15.00 | 5x |
| Haiku 4.5 | $1.00 | $5.00 | 5x |

Sources: [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing), [Finout 2026 guide](https://www.finout.io/blog/anthropic-api-pricing), [CloudZero Opus 4.8](https://www.cloudzero.com/blog/claude-opus-4-8-pricing/).

### Why "% of output tokens" is the wrong unit

A representative 50-turn agentic coding session is ≈ **1,000,000 input : 40,000 output tokens (~25:1)**; input is ~85% of cost when uncached, and context balloons every turn because the system prompt, tool schemas, retrieved files, and full transcript are re-sent ([Vantage](https://www.vantage.sh/blog/agentic-coding-costs)). Roughly **~99% of coding-agent tokens are input** accumulated in trajectories ([arXiv 2509.23586](https://arxiv.org/html/2509.23586v1)).

So output compression attacks the *small* bucket — but the *expensive-per-token* one. Its cost share depends entirely on cache state. Worked example at Opus prices:

| Scenario | Output = % of cost | caveman cuts 65% of output ⇒ % of **total** |
|---|---|---|
| No caching | ~17% | ~11% |
| 90% cache-hit | **~51%** | **~33%** |

The counterintuitive result: **caching makes input cheap, which raises output's share, which makes output compression matter more.** caveman and caching are **complementary, not competing**. But caching is the larger *absolute* lever, and it must come first.

Real-world confirmation that cache reads dominate: a documented session where **cache-read tokens were 97.7% of billed cost** ($1.47 true compute vs $64.98 billed); an 80%-cache-hit session is ≈5x cheaper than 0% ([AgentsRoom](https://agentsroom.dev/features/claude-code-token-usage)).

---

## 2. Audit of toolu's own claims

caveman is an external dependency (`JuliusBrussee/caveman`); the installed copy ships real `benchmarks/` and `evals/` directories.

| # | Claim | Number | Mechanism (file:line) | Verdict | Problem |
|---|---|---|---|---|---|
| 1 | caveman output cut | ~75% | `README.md:27`; `benchmarks/run.py` | **ESTIMATED, inflated** | Baseline was `"You are a helpful assistant."` The authors' own `evals/README.md:14-16` state that baseline "conflated the skill with the generic terseness ask… is why its numbers were inflated." The honest comparison (skill vs `"Answer concisely."`) is implemented in `evals/` but **never published**. `benchmarks/results/` is empty. |
| 2 | cavecrew subagent | ~60% smaller | `cavecrew/SKILL.md:9,32` (prose only) | **UNSUBSTANTIATED** | No benchmark, no hook, no measurement anywhere. Pure marketing copy — yet the underlying mechanism is the most economically sound (see §3). |
| 3 | `/caveman-stats` savings | session % | `caveman-stats.js:19` `COMPRESSION={'full':0.65}` (hardcoded); `:143` back-computes `estNormal = output/(1-0.65)` | **ESTIMATED** | Reads *real* output + cache_read tokens from session JSONL, but applies the 0.65 ratio to **output only** and presents the result as total savings → overstates cost%. The constant cites `benchmarks/results/*.json`, which is empty. |
| 4 | comemory skip-re-reads | unquantified | `agent-memory/SKILL.md`; scope-enforcement hook is real | **UNSUBSTANTIATED, mechanism real** | No "tokens avoided" meter; depends on the model obeying the SKILL instruction. |
| 5 | ast-grep vs whole-file read | unquantified | `ast-grep/skills/.../SKILL.md` search-stack | **UNSUBSTANTIATED, mechanism real** | Returns hits, not files — real saving, never measured in-repo. |
| 6 | statusline token ledger | weekly total | `statusline/hooks/token-ledger.sh:49-65` sums real JSONL, dedup by `message.id` | **MEASURED (honest)** | The most honest instrumentation. Excludes `cache_read` by design (`:9`, billed ~0.1x), so the `wk:` number understates total volume; reports usage, not savings. |

**Most honest pieces:** the statusline ledger and the `evals/` harness (control arm, disclosed `tiktoken o200k_base ≈ Claude BPE` caveat). **Weakest:** the cavecrew "60%" (zero evidence) and the README "75%" (authors already know it's inflated; README never updated).

---

## 3. External state of the art

Ranked by **real cost impact** for an agent harness like Claude Code, not by headline ratio.

### 3.1 Prompt caching — the #1 lever (HIGH ROI)

Anthropic universal multipliers: cache write 5-min **1.25x**, write 1-hour **2x**, read **0.1x** (90% discount). Cache prefix order is strict — **tools → system → messages** — and a change at any layer invalidates that layer and everything after it. Put all static content first, variable content (user message, timestamps) last, and the breakpoint on the last static block. ([Anthropic prompt caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching))

Measured in real agentic sessions:

- **ProjectDiscovery** (Opus agent swarm): **59% → 66–70%** total cost reduction; cache hit rate 7% → 74% → **91.8%**; 9.8B tokens served from cache. Biggest single win was the *relocation trick* — moving dynamic content out of the cacheable prefix. ([projectdiscovery.io](https://projectdiscovery.io/blog/how-we-cut-llm-cost-with-prompt-caching))
- **"Don't Break the Cache"** (500+ agent sessions, 10K-token system prompts): **45–80%** cost savings (≈78–79% Sonnet 4.5; ≈79–81% GPT-5.2); time-to-first-token 13–31% better. Key finding: **strategic cache-boundary control beats naive full-context caching** — naive caching can *increase* latency. ([arXiv 2601.06007](https://arxiv.org/html/2601.06007v1))
- OpenAI automatic caching: 50% (2024) → up to **90%** on current models, zero code changes. ([OpenAI caching guide](https://developers.openai.com/api/docs/guides/prompt-caching))

### 3.2 Structural / targeted code access (HIGH ROI)

Substantiates toolu's ast-grep-first + comemory-first protocol with external, peer-reviewed evidence:

- **~10x token reduction** vs whole-file reading is the peer-reviewed floor (Codebase-Memory, tree-sitter knowledge graph, 31 repos), up to 40–120x self-reported on *pure structural queries*. ([arXiv 2603.27277](https://arxiv.org/html/2603.27277v1))
- **LocAgent**: ~86% cost reduction ($0.66 → $0.09/example) via a heterogeneous code graph; 92.7% file-level localization. ([ACL 2025, arXiv 2503.09089](https://arxiv.org/abs/2503.09089))
- **Agentless**: hierarchical localization beats free-exploration agents on both accuracy *and* cost — 32% solve / $0.70 per instance on SWE-bench Lite. ([arXiv 2407.01489](https://arxiv.org/abs/2407.01489))
- **"Is Grep All You Need?"**: inline grep beat inline vector retrieval on *every* model/harness pair tested. RAG/embeddings are increasingly the wrong default for code because semantic chunking fragments functions. ([arXiv 2605.15184](https://arxiv.org/html/2605.15184v1))
- Claude Code itself ships **no persistent embedding index** by design — `Glob`/`Grep` → `Read`, where `grep -n -C` shows hits plus surrounding context so the model often avoids opening the file. ([Claude Code tools reference](https://code.claude.com/docs/en/tools-reference))

Caveat: the 120x figure is structural-queries-only and self-reported; **treat ~10x as the defensible general claim.**

### 3.3 Subagent context isolation (HIGH ROI)

A subagent burns tens of thousands of tokens but returns a **1,000–2,000-token distilled summary**; the detailed context stays isolated and never pollutes — or gets re-cached into — the main thread. Anthropic's multi-agent researcher found **token usage alone explains ~80% of performance variance**, and the architecture outperformed single-agent by 90.2% — at **~15x** the token cost, so it pays off only when task value is high. ([Anthropic: effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Anthropic: multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system))

**Cost guardrail:** unmanaged fan-out is dangerous — reported real cases of **$8K–15K for a single session** and **$47K over 3 days** with subagents running unattended. ([morphllm](https://www.morphllm.com/ai-coding-costs))

### 3.4 Model routing & reasoning budgets (MEDIUM–HIGH ROI)

- **Routing cheap→frontier**: ~**75–85% cost reduction at ~95% quality**, routing only 14–26% of calls to the frontier model. ([RouteLLM, lm-sys](https://github.com/lm-sys/routellm))
- **Reasoning budgets plateau early** (~8–16K thinking tokens; Claude 3.7 on AIME: 20% → 50% at 16K, flat after). Thinking tokens bill as **output** (5x), so cap `effort`/budget at the knee. ([Anthropic extended thinking](https://platform.claude.com/docs/en/build-with-claude/extended-thinking), [W&B eval](https://wandb.ai/byyoung3/Generative-AI/reports/Evaluating-Claude-3-7-Sonnet-Performance-reasoning-and-cost-optimization--VmlldzoxMTYzNDEzNQ))
- **Batch API**: flat **50%** off input *and* output, but 24h async — useless for the live loop, ideal for offline subtasks (evals, bulk processing). ([Anthropic batches](https://www.finout.io/blog/anthropic-api-pricing))
- **Speculative decoding**: 2–3x latency, mathematically lossless — but self-host / specialized-provider only; not a knob on the Claude/OpenAI APIs. ([BentoML](https://www.bentoml.com/blog/3x-faster-llm-inference-with-speculative-decoding))

### 3.5 Output & format compression (MEDIUM–LOW ROI)

- Terse output / structured formats: JSON ≈ 2x tokens of TSV; XML is worst (+114% vs TOON); plain JSON has the best accuracy. Matters for subagent return payloads. ([TOON benchmark](https://arxiv.org/html/2603.03306v1), [MS Data Science](https://medium.com/data-science-at-microsoft/token-efficiency-with-structured-output-from-language-models-be2e51d3d9d5))

### 3.6 Prompt-compression literature — context for where caveman sits (LOW actionability for toolu)

The survey ([arXiv 2410.12388](https://arxiv.org/abs/2410.12388), NAACL 2025) splits methods into:

- **Hard-prompt compression** (output stays natural language; model-agnostic, no training; 2–20x; lossy). *Filtering* (LLMLingua family) and *paraphrasing*. **caveman is hard-prompt paraphrasing — the lowest-ratio, most lossy sub-family.**
- **Soft-prompt compression** (context → embeddings/memory slots; up to 175–480x + FLOP savings; model-specific, needs training). xRAG, GIST, ICAE, AutoCompressor, LLoCO.
- **KV-cache compression** (decode-time; H2O, SnapKV, PyramidKV; near-lossless at 10–20% retention).

Reference numbers: LLMLingua up to 20x with ~1.5pt loss ([2310.05736](https://arxiv.org/abs/2310.05736)); LongLLMLingua +21.4% at ~4x ([2310.06839](https://arxiv.org/abs/2310.06839)); LLMLingua-2 2–5x, task-agnostic ([2403.12968](https://arxiv.org/abs/2403.12968)); xRAG 175:1 ([2405.13792](https://arxiv.org/abs/2405.13792)).

**The critical reality check** ([arXiv 2407.08892](https://arxiv.org/abs/2407.08892)): under a fair fixed-budget eval, **extractive compression achieves ~10x with minimal loss and often outperforms everything else; token-pruning methods (LLMLingua family) often lag extractive.** Practitioners realize **2–6x on real prompts** — 20x+ applies only to highly redundant content. CompAct can even *beat* full context by removing distractors ([2407.09014](https://arxiv.org/abs/2407.09014)).

**Why this is mostly not actionable for toolu:** every one of these compressors needs a *compressor model in the loop*, which the Claude Code harness does not provide. The transferable conclusion is only the ranking: paraphrasing/pruning is the weak end; caching + extractive/targeted retrieval is the strong end — which matches the cost model.

---

## 4. Recommendations for toolu

Prioritized by real dollar impact.

### P0 — Audit caching (biggest, unaddressed)
Cache discipline is empirically a 45–80% cost lever — an order of magnitude above caveman's output compression. This session injects the caveman prompt, the session protocol, and deferred-tool lists at session start. **Any per-turn-varying or high-in-prefix injected content busts the cache** (0.1x → 1x on everything after it). Audit all `SessionStart`/hook output for prefix stability and ordering; keep static blocks first and stable.

### P0 — Fix the metric (correctness + credibility)
1. `/caveman-stats`: stop applying `0.65` to output-only and labeling it total savings. Report **dollars saved**, split by bucket × price (output 5x, cache-read 0.1x). Show "output tokens saved (≈X% of *output*, ≈Y% of *cost*)" — honest, and still flattering where deserved.
2. README: drop "~75%" or relabel it explicitly as **output-token** reduction vs a verbose baseline; publish the real skill-vs-terse delta from `evals/`; commit `benchmarks/results/` so the `0.65` constant has provenance.

### P0 — Lean into the real levers
3. Make **cavecrew / Explore the default for exploration**. Its mechanism (distilled return, isolated context) is the highest-value internal lever — and it is *measurable*: log the size of the tool-result injected into main vs the raw bytes the subagent read. Replace the fabricated "60%" with that measured main-context byte delta.
4. **Formalize model routing**: Haiku for routing/trivial edits/formatting, Sonnet for exploration/standard edits, Opus for hard reasoning/planning only. 75–85% cost cut at ~95% quality.

### P1 — Instrument what's claimed
5. comemory + ast-grep: add lightweight "bytes returned vs bytes a full read would have cost" logging → moves UNSUBSTANTIATED → MEASURED, matching the peer-reviewed ~10x prior. Cheap; closes the credibility gap.
6. Subagent return payloads: prefer compact tables/TSV over prose/JSON (~2x). cavecrew already uses tables — codify it.
7. Add a **subagent fan-out budget cap + visibility** (Workflow/cavecrew) to avoid runaway-cost incidents.

### P2 — Selective compression & offline savings
8. Don't compress reasoning/planning turns (caveman off for chain-of-thought) — terse output can degrade reasoning. Compress only final/status prose.
9. Run `evals/` and `benchmarks/` via the **batch API** (flat 50% off) — they are offline workloads.
10. Cap reasoning `effort`/budget at the ~8–16K-token knee.

---

## 5. Levers ranked (summary)

| Lever | Real impact | Evidence quality | toolu status |
|---|---|---|---|
| Cache discipline | 45–80% cost | peer-reviewed + case studies | **not audited — do first** |
| Structural/targeted reads (ast-grep, comemory) | ~10x on access | peer-reviewed | enforced, unmeasured in-repo |
| Subagent isolation | ~80% of perf variance | Anthropic | used; fabricated "60%" |
| Model routing (Haiku/Sonnet/Opus) | 75–85% @ ~95% quality | RouteLLM | ad hoc, not formalized |
| Output compression (caveman) | ~11–33% (rises with cache) | self-benchmarked, inflated | marketed hardest; metric wrong |
| Reasoning-budget cap / batch | knee ~8–16K / flat 50% | peer-reviewed / vendor | unused |

---

## Sources

**Pricing & caching:** [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) · [Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) · [OpenAI caching](https://developers.openai.com/api/docs/guides/prompt-caching) · [ProjectDiscovery case study](https://projectdiscovery.io/blog/how-we-cut-llm-cost-with-prompt-caching) · [Don't Break the Cache (arXiv 2601.06007)](https://arxiv.org/html/2601.06007v1) · [AgentsRoom token usage](https://agentsroom.dev/features/claude-code-token-usage) · [Vantage agentic coding costs](https://www.vantage.sh/blog/agentic-coding-costs)

**Context engineering & agents:** [Anthropic: effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) · [Anthropic: multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) · [trajectory token study (arXiv 2509.23586)](https://arxiv.org/html/2509.23586v1)

**Structural code access:** [Codebase-Memory (arXiv 2603.27277)](https://arxiv.org/html/2603.27277v1) · [LocAgent (arXiv 2503.09089)](https://arxiv.org/abs/2503.09089) · [Agentless (arXiv 2407.01489)](https://arxiv.org/abs/2407.01489) · [Is Grep All You Need? (arXiv 2605.15184)](https://arxiv.org/html/2605.15184v1) · [Claude Code tools reference](https://code.claude.com/docs/en/tools-reference)

**Model-level:** [RouteLLM](https://github.com/lm-sys/routellm) · [Anthropic extended thinking](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) · [W&B reasoning/cost eval](https://wandb.ai/byyoung3/Generative-AI/reports/Evaluating-Claude-3-7-Sonnet-Performance-reasoning-and-cost-optimization--VmlldzoxMTYzNDEzNQ) · [speculative decoding (BentoML)](https://www.bentoml.com/blog/3x-faster-llm-inference-with-speculative-decoding) · [AI coding costs (morphllm)](https://www.morphllm.com/ai-coding-costs)

**Prompt/format compression:** [Prompt Compression Survey (arXiv 2410.12388)](https://arxiv.org/abs/2410.12388) · [LLMLingua (2310.05736)](https://arxiv.org/abs/2310.05736) · [LongLLMLingua (2310.06839)](https://arxiv.org/abs/2310.06839) · [LLMLingua-2 (2403.12968)](https://arxiv.org/abs/2403.12968) · [xRAG (2405.13792)](https://arxiv.org/abs/2405.13792) · [CompAct (2407.09014)](https://arxiv.org/abs/2407.09014) · [Characterizing Prompt Compression (arXiv 2407.08892)](https://arxiv.org/abs/2407.08892) · [TOON vs JSON benchmark](https://arxiv.org/html/2603.03306v1) · [Microsoft LLMLingua](https://github.com/microsoft/LLMLingua)

> Reliability notes: several sources carry 2026 datestamps (environment clock is June 2026) and sit just past a Jan 2026 knowledge cutoff — flagged where load-bearing. Self-reported figures (40–120x structural, 480x soft-compression) are best-case; peer-reviewed floors (~10x structural, 2–6x real-world prompt compression) are the defensible claims. Two future-dated arXiv IDs surfaced during search could not be verified and were excluded.

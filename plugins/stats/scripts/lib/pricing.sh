#!/usr/bin/env bash
# Per-model token pricing for the stats report.
#
# Sticker prices (2026), in $/Mtok. Cost is an ESTIMATE, not an Anthropic bill.
# Rates: Opus $5/$25, Haiku $1/$5, else Sonnet $3/$15 (also covers unknown
# models). cache_read is billed 0.1x the input rate; cache writes 1.25x (5-min
# TTL) / 2x (1-hour TTL), split via usage.cache_creation.ephemeral_{5m,1h}_input_tokens,
# falling back to cache_creation_input_tokens at 1.25x when the split is absent.
#
# STATS_PRICING_ID is the cache fingerprint: bump it on ANY rate change so cached
# rollups recompute instead of serving stale cost (see scan.sh invalidation).
# Exported because it is consumed by the modules that source this file.
export STATS_PRICING_ID="2026-06"

# Emit a jq prelude defining rates(model) and msgcost(usage; rates). usage.sh
# sources this file and injects the prelude into its jq program; pricing.bats
# exercises it directly. Single source of truth for the cost math.
stats_pricing_jq() {
  cat <<'JQ'
def rates(m):
  if   (m | test("opus"))  then {i: 5, o: 25}
  elif (m | test("haiku")) then {i: 1, o: 5}
  else {i: 3, o: 15} end;
def msgcost($u; $r):
  ($u.input_tokens // 0)                               as $inp
  | ($u.output_tokens // 0)                            as $outp
  | ($u.cache_read_input_tokens // 0)                  as $crd
  | ($u.cache_creation_input_tokens // 0)              as $cwr
  | ($u.cache_creation.ephemeral_5m_input_tokens // 0) as $w5
  | ($u.cache_creation.ephemeral_1h_input_tokens // 0) as $w1
  | ( $inp * $r.i + $outp * $r.o + $crd * $r.i * 0.1
    + (if ($w5 + $w1) > 0 then $w5 * 1.25 * $r.i + $w1 * 2 * $r.i
                          else $cwr * 1.25 * $r.i end)
    ) / 1000000;
JQ
}

#!/usr/bin/env bash
# common.sh — shared bootstrap for the benchmarks harness.
#
# Locates the repo root, sources the stats pricing/usage libs (the single source
# of truth for token math — we never reimplement it here), and resolves the
# results dir. Sourced by run.sh and every cases/*/run.sh; not executed directly.
set -u

_bench_die() { echo "benchmarks: $1" >&2; }

# bench_repo_root -> absolute repo root on stdout. Prefers `git rev-parse`
# (worktree-safe), then walks up looking for a .git entry.
bench_repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  git -C "$here" rev-parse --show-toplevel 2>/dev/null && return 0
  while [ "$here" != "/" ]; do
    [ -e "$here/.git" ] && { printf '%s\n' "$here"; return 0; }
    here="$(dirname "$here")"
  done
  return 1
}

BENCH_ROOT="$(bench_repo_root)" || { _bench_die "cannot locate repo root"; return 1; }
BENCH_STATS_LIB="$BENCH_ROOT/plugins/stats/scripts/lib"
BENCH_RESULTS_DIR="${BENCH_RESULTS_DIR:-$BENCH_ROOT/benchmarks/results}"
export BENCH_ROOT BENCH_STATS_LIB BENCH_RESULTS_DIR

[ -f "$BENCH_STATS_LIB/pricing.sh" ] || { _bench_die "stats pricing.sh missing at $BENCH_STATS_LIB"; return 1; }
# shellcheck source=/dev/null
source "$BENCH_STATS_LIB/pricing.sh" || { _bench_die "cannot source pricing.sh"; return 1; }
# shellcheck source=/dev/null
source "$BENCH_STATS_LIB/usage.sh" || { _bench_die "cannot source usage.sh"; return 1; }

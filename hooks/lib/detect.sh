#!/usr/bin/env bash
# Shared detection helpers for project-agnostic hooks.
# Source via:   . "${BASH_SOURCE%/*}/../lib/detect.sh"

# Print the absolute project root (git toplevel) or "" if not in a git repo.
detect_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || true
}

# Print the project name (basename of the git toplevel) or "" if not in a git repo.
detect_project_name() {
  local root
  root=$(detect_project_root) || return 0
  [ -n "$root" ] && basename "$root"
}

# Print the package manager: bun | pnpm | npm | yarn | "" (none detected).
detect_node_pm() {
  local root
  root=$(detect_project_root)
  [ -z "$root" ] && return 0
  [ -f "$root/bun.lock" ]          && echo bun && return
  [ -f "$root/bun.lockb" ]         && echo bun && return
  [ -f "$root/pnpm-lock.yaml" ]    && echo pnpm && return
  [ -f "$root/yarn.lock" ]         && echo yarn && return
  [ -f "$root/package-lock.json" ] && echo npm && return
}

# Echo "rust" if a Cargo.toml exists at the project root.
detect_rust() {
  local root
  root=$(detect_project_root)
  [ -z "$root" ] && return 0
  [ -f "$root/Cargo.toml" ] && echo rust
}

# Echo "ts" if a tsconfig*.json exists anywhere in the project.
detect_ts() {
  local root
  root=$(detect_project_root)
  [ -z "$root" ] && return 0
  git -C "$root" ls-files '**/tsconfig*.json' 'tsconfig*.json' 2>/dev/null \
    | grep -q . && echo ts
}

# Return the base branch from origin/HEAD, or "main" if remote is missing.
detect_base_branch() {
  local root ref
  root=$(detect_project_root)
  [ -z "$root" ] && { echo main; return; }
  ref=$(git -C "$root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    echo "${ref#refs/remotes/origin/}"
  else
    echo main
  fi
}

# Print the data dir for settings/ lookups. Override with $MY_CLAUDE_SETTINGS_DIR.
detect_settings_dir() {
  if [ -n "${MY_CLAUDE_SETTINGS_DIR:-}" ]; then
    echo "$MY_CLAUDE_SETTINGS_DIR"
  elif [ -d "${HOME}/.claude/settings" ]; then
    echo "${HOME}/.claude/settings"
  else
    local self
    self=$(cd "${BASH_SOURCE%/*}/.." && pwd)
    echo "$self/../settings"
  fi
}

# Echo a repo-relative path for the given (potentially absolute) file_path.
# Falls back to the input unchanged if it cannot determine the project root
# or if the path is not under that root.
#
# Claude's Edit/Write tools send absolute paths; settings globs are written
# repo-relative. Without this helper, [[ /abs/path == hooks/lib/** ]] is
# always false, silently no-op'ing trusted-script protection.
to_relative_path() {
  local p="${1:-}"
  [ -z "$p" ] && { echo ""; return 0; }
  local root
  root=$(detect_project_root)
  if [ -n "$root" ]; then
    case "$p" in
      "$root"/*) echo "${p#"$root"/}" ;;
      *)         echo "$p" ;;
    esac
  else
    echo "$p"
  fi
}

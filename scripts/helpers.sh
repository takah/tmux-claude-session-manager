#!/usr/bin/env bash
# Shared helpers for tmux-claude-session-manager.

# get_tmux_option <option-name> <default>
# Echoes the global tmux option value, or the default when unset/empty.
get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

# session_name <path>
# Derives a session name from a path's basename. tmux treats '.' and ':' as
# special in session names, so they are replaced with '-'.
session_name() {
  local base
  base="$(basename "$1")"
  printf '%s' "${base//[.:]/-}"
}

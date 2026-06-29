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

# detect_state <session>  ->  working | waiting | idle
# Derives a session's live state from what Claude is actually showing in its
# pane, rather than trusting the last hook event (which goes stale). The footer
# line is the reliable signal, checked working-first so a working pane is never
# misread as a prompt scrolled above it. capture-pane reads the server-side
# screen even for detached sessions and costs ~2ms. Falls back to the
# hook-recorded state when the pane can't be read.
detect_state() {
  local pane
  pane="$(tmux capture-pane -p -t "$1" 2>/dev/null)"
  if [ -z "$pane" ]; then
    tmux show-options -qv -t "$1" @claude_state 2>/dev/null
    return
  fi
  case "$pane" in
  *"esc to interrupt"*) echo working ;;
  *"Do you want to proceed?"* | *"Esc to cancel"*) echo waiting ;;
  *) echo idle ;;
  esac
}

# customer_group <parent-dir-name>  ->  ERE alternation of the dirs in its group
# Sessions live at .../<parent>/<project>; the parent dir is the "customer". To
# treat several parent dirs as one customer (e.g. linkbal + linkbal-x), list them
# in @claude_customer_groups: comma-separated groups, space-separated members.
# A dir not in any group is its own singleton. Used to scope the picker.
#   @claude_customer_groups = 'linkbal linkbal-x'
#     customer_group linkbal -> 'linkbal|linkbal-x'   customer_group takah -> 'takah'
customer_group() {
  local target="$1" spec line members
  spec="$(get_tmux_option @claude_customer_groups '')"
  while IFS= read -r line; do
    members="$(printf '%s' "$line" | xargs)"
    [ -n "$members" ] || continue
    case " $members " in
    *" $target "*)
      printf '%s' "$members" | tr ' ' '|'
      return
      ;;
    esac
  done <<EOF
$(printf '%s' "$spec" | tr ',' '\n')
EOF
  printf '%s' "$target"
}

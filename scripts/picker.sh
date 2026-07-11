#!/usr/bin/env bash
# Interactive picker for running Claude sessions.
#
#   picker.sh [scope]          fzf picker; on enter, switches the parent client to
#                              the chosen session's origin window and resumes it.
#   picker.sh --list [scope]   print the rows only (used by fzf's ctrl-x reload).
#
# scope is an optional ERE of parent-dir names (e.g. 'linkbal|linkbal-x'). When
# set, only sessions whose parent dir matches are listed AND previewed — a hard
# filter so other dir groups never show on your screen (e.g. during a screen-share).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'c-')"

# detect_state (live status from the pane) lives in helpers.sh, shared with the
# status-bar counter.

# human_age <seconds> -> compact relative age that switches units as it grows:
#   45m   (under an hour)   5h   (under a day)   3d15h / 8d   (a day or more)
human_age() {
  local s="$1" d h
  if [ "$s" -lt 3600 ]; then
    printf '%dm' "$((s / 60))"
  elif [ "$s" -lt 86400 ]; then
    printf '%dh' "$((s / 3600))"
  else
    d=$((s / 86400)) h=$(((s % 86400) / 3600))
    if [ "$h" -gt 0 ]; then printf '%dd%dh' "$d" "$h"; else printf '%dd' "$d"; fi
  fi
}

emit_rows() {
  local scope="${1:-}"
  local now s state at path name parent label icon rank ago secs
  now=$(date +%s)
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" | while IFS= read -r s; do
    path=$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)
    name="${path##*/}"
    parent="${path%/*}"
    parent="${parent##*/}"
    # Scoped picker: drop sessions outside the requested dir group entirely.
    [ -n "$scope" ] && ! [[ "$parent" =~ ^($scope)$ ]] && continue
    state=$(detect_state "$s")
    at=$(tmux show-options -qv -t "$s" @claude_state_at 2>/dev/null)
    # Paths share a common prefix, so show the dir name plus its parent's name to
    # tell sessions apart: e.g. "api  myproject".
    label="$name  $parent"
    case "$state" in
    waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
    idle) icon=$'\033[32m●\033[0m idle   ' rank=1 ;;    # green  - done, your turn
    working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
    *) icon=$'\033[90m●\033[0m   ?    ' rank=2 ;;       # grey   - unknown (no hook yet)
    esac
    if [ -n "$at" ]; then secs=$((now - at)) ago="$(human_age "$secs")"; else secs=0 ago='-'; fi
    # rank \t session \t secs \t icon \t age \t label
    # rank/session/secs are hidden via --with-nth; secs is the real (seconds) age
    # used for sorting, since the displayed age mixes units (m/h/d) and can't be
    # compared numerically.
    printf '%s\t%s\t%s\t%s\t%5s\t%s\n' "$rank" "$s" "$secs" "$icon" "$ago" "$label"
    # rank asc (attention-needed floats up), then age asc (by secs) so the session
    # that finished just now sits at the top of its group.
  done | sort -t$'\t' -k1,1n -k3,3n
}

[ "${1:-}" = '--list' ] && {
  emit_rows "${2:-}"
  exit 0
}

scope="${1:-}"

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-claude-session-manager: fzf is required for the picker"
  exit 0
fi

self="${BASH_SOURCE[0]}"
header='Claude sessions · enter: jump · ctrl-x: kill'
[ -n "$scope" ] && header="Claude · dir: ${scope//|/, } · enter: jump · ctrl-x: kill"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows "$scope" | fzf --ansi --delimiter='\t' --with-nth=4,5,6 \
  --reverse --cycle --header="$header" \
  --preview="tmux capture-pane -ept {2}" --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list '$scope')")

# Consume the one-shot hints list.sh may have left for the direct-attach case, so
# they never leak into a later invocation.
parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
restore=$(tmux show-options -gqv @claude_restore_to 2>/dev/null)
landing=$(tmux show-options -gqv @claude_landing_session 2>/dev/null)
tmux set-option -gu @claude_restore_to 2>/dev/null
tmux set-option -gu @claude_landing_session 2>/dev/null

# Kill the throwaway session list.sh created solely to host this picker, once no
# client is left on it. No-op unless we created one — it never touches a
# pre-existing session.
drop_landing() {
  [ -n "$landing" ] || return 0
  tmux list-clients -F '#{session_name}' 2>/dev/null | grep -qxF "$landing" && return 0
  tmux kill-session -t "$landing" 2>/dev/null
}

if [ -z "$sel" ]; then
  # Cancelled. In the direct-attach case we parked the client on a normal session
  # to open this picker; send it back where it came from before dropping the temp.
  [ -n "$restore" ] && tmux switch-client -c "$parent" -t "$restore" 2>/dev/null
  drop_landing
  exit 0
fi
target=$(printf '%s' "$sel" | cut -f2)

# Move the underlying parent client to the session's origin window (best-effort),
# then resume the session in THIS popup over it. Falls back to resuming over the
# current window when origin/parent are unknown.
origin=$(tmux show-options -qv -t "$target" @claude_origin 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

drop_landing
tmux attach-session -t "$target"

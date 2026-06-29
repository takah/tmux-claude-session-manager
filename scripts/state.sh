#!/usr/bin/env bash
# Record a Claude Code session's state on its tmux session, and ring the bell
# when it starts waiting for you. Wire this into Claude Code hooks (see README):
#   state.sh <working|waiting|idle>
#
# Claude Code hooks inherit the Claude process environment, so $TMUX_PANE is set
# whenever Claude runs inside tmux. Outside tmux this is a no-op.
[ -z "$TMUX_PANE" ] && exit 0

session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
[ -z "$session" ] && exit 0

state="${1:-idle}"
tmux set-option -t "$session" @claude_state "$state"
tmux set-option -t "$session" @claude_state_at "$(date +%s)"

# When a session starts waiting for you, ring the bell on every attached client's
# tty. That tty is the SSH pty, so the BEL travels back over the connection and
# rings your *local* terminal — wherever you're attached from — even when this
# session is backgrounded. Writing to the tty directly bypasses tmux's own bell
# handling, which is otherwise gated by monitor-bell / bell-action. Disable with:
#   set -g @claude_bell 'off'
if [ "$state" = waiting ] && [ "$(tmux show-option -gqv @claude_bell 2>/dev/null)" != off ]; then
  tmux list-clients -F '#{client_tty}' 2>/dev/null | sort -u | while IFS= read -r tty; do
    [ -w "$tty" ] && printf '\a' >"$tty"
  done
fi
exit 0

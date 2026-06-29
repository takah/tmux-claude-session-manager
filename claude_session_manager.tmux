#!/usr/bin/env bash
# tmux-claude-session-manager
#
# List, monitor status, and jump across nested Claude Code sessions from a
# single popup. tpm runs this file as an executable on tmux startup; it reads
# user options (with sensible defaults) and installs the key bindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

launch_key="$(get_tmux_option @claude_launch_key 'y')"
list_key="$(get_tmux_option @claude_list_key 'u')"
scoped_list_key="$(get_tmux_option @claude_scoped_list_key 'C-u')"

# Launch (or re-attach to) a Claude session for the current pane's directory.
# #{pane_current_path} / #{window_id} are expanded by run-shell before the args
# reach the script.
tmux bind-key "$launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh '#{pane_current_path}' '#{window_id}'"

# Open the session picker. When pressed from inside a session popup, list.sh
# closes that popup first so the picker opens full-size on the outer client.
tmux bind-key "$list_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}'"

# Open the picker scoped to the current pane's customer group (its parent dir,
# grouped per @claude_customer_groups). Passing #{pane_current_path} tells
# list.sh which customer to limit the list to — so you can show one customer
# their sessions without others appearing on screen.
tmux bind-key "$scoped_list_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}' '#{pane_current_path}'"

# Show a badge in the status bar counting sessions that are waiting for input.
# We append it to status-right ourselves so it works out of the box — no config
# needed. The append is idempotent (skipped if already present), so re-sourcing
# or reinstalling won't duplicate it. Opt out with:  set -g @claude_status 'off'
if [ "$(get_tmux_option @claude_status 'on')" != 'off' ]; then
  status_cmd="#($CURRENT_DIR/scripts/status.sh)"
  current="$(tmux show-option -gqv status-right)"
  case "$current" in
  *"$status_cmd"*) ;; # already wired (re-sourced) — leave it
  *)
    tmux set-option -g status-right "${current:+$current }$status_cmd"
    # Keep the badge from being truncated by a tight status-right-length.
    len="$(tmux show-option -gqv status-right-length)"
    [ "${len:-0}" -lt 60 ] 2>/dev/null && tmux set-option -g status-right-length 60
    ;;
  esac
fi

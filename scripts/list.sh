#!/usr/bin/env bash
# Open the session picker in a popup, on the client that invoked the binding.
#   list.sh <client> [scope-path]
# When scope-path (a directory) is given, the picker is hard-scoped to the dir
# group that path's parent dir belongs to — used by the scoped binding so you
# only show one group's sessions while sharing your screen.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'c-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# Derive the scope (a dir group) from the invoking pane's directory, if requested.
scope_path="${2:-}"
scope=""
if [ -n "$scope_path" ]; then
  scope="$(dir_group "$(basename "$(dirname "$scope_path")")")"
fi

# The client that pressed the key, passed as #{client_name} by the binding. We
# host the popup on THIS client so it always appears on the terminal you pressed
# the key from — even when several clients are attached to the same server.
invoker="${1:-}"
client_session() { # client_session <client-name> -> its attached session name
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v c="$1" '$1 == c { print $2; exit }'
}

# parent_is_live <client> — true if <client> is a currently-attached client that
# sits on a NORMAL (non-prefix) session. This is how we confirm a recorded
# @claude_popup_parent still refers to a real outer terminal, and reject a stale
# value whose client name has since been reused by another (e.g. c-) client.
parent_is_live() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v c="$1" -v p="$prefix" '$1 == c && index($2, p) != 1 { ok = 1 } END { exit !ok }'
}

# One-shot hints handed to picker.sh for the direct-attach case (see below).
host=""
restore_to=""   # session to send the client back to if the picker is cancelled
landing_session=""  # throwaway session we created only to host the picker

if [ -n "$invoker" ] && [[ "$(client_session "$invoker")" != "$prefix"* ]]; then
  # Pressed from a normal (non-popup) pane: host on that very client.
  host="$invoker"
else
  # Attached to a c- session. Two situations look identical here, so tell them
  # apart deterministically via @claude_popup_parent (launch.sh records it when it
  # opens a popup; a direct `tmux a` never runs launch.sh so it is absent/stale).
  orig="$(client_session "$invoker")"
  parent="$(tmux show-option -qv -t "$orig" @claude_popup_parent 2>/dev/null)"
  if [ -n "$parent" ] && [ "$parent" != "$invoker" ] && parent_is_live "$parent"; then
    # Inside a session popup: the recorded parent is still your real terminal.
    # Close this popup and reopen the picker full-size over it. Resolve the host
    # *before* detaching so we don't lose the reference.
    host="$parent"
    tmux detach-client -t "$invoker" 2>/dev/null
    for _ in $(seq 1 100); do
      tmux list-clients -F '#{client_name}' 2>/dev/null | grep -qxF "$invoker" || break
      sleep 0.05
    done
  elif [ -n "$invoker" ]; then
    # Attached directly (e.g. `tmux a` landed on a c- session): there is no outer
    # terminal, so detaching would drop you out of tmux entirely. Instead park
    # THIS client on a normal (non-c-) session — creating one, seeded with the c-
    # session's cwd, if none exist — and open the picker there just like a normal
    # pane. picker.sh sends the client back to `orig` if you cancel.
    normal="$(tmux list-sessions -F '#{session_name}' 2>/dev/null |
      awk -v p="$prefix" 'index($0, p) != 1 { print; exit }')"
    if [ -z "$normal" ]; then
      cwd="$(tmux display-message -p -t "$invoker" '#{pane_current_path}' 2>/dev/null)"
      if [ -n "$cwd" ]; then
        normal="$(tmux new-session -d -P -F '#{session_name}' -c "$cwd")"
      else
        normal="$(tmux new-session -d -P -F '#{session_name}')"
      fi
      landing_session="$normal"
    fi
    tmux switch-client -c "$invoker" -t "$normal" 2>/dev/null
    host="$invoker"
    restore_to="$orig"
  fi
fi

tmux set-option -g @claude_parent "$host"
# Fresh each run: set the direct-attach hints, or clear any left by a prior run so
# a normal/popup invocation never inherits a stale restore target.
if [ -n "$restore_to" ]; then
  tmux set-option -g @claude_restore_to "$restore_to"
else
  tmux set-option -gu @claude_restore_to 2>/dev/null
fi
if [ -n "$landing_session" ]; then
  tmux set-option -g @claude_landing_session "$landing_session"
else
  tmux set-option -gu @claude_landing_session 2>/dev/null
fi

# -c is honored because the host client has no popup open now; fall back to the
# default client if none was resolved. The scope is single-quoted so its '|' is
# passed through to picker.sh intact.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh '$scope'"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh '$scope'"
fi

# Never let our own exit status surface as a tmux "returned N" view: the popup's
# result (e.g. fzf cancelled) is not an error worth reporting to the user.
exit 0

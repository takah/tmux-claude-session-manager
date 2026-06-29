#!/usr/bin/env bash
# Open the session picker in a popup, on the client that invoked the binding.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'c-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# The client that pressed the key, passed as #{client_name} by the binding. We
# host the popup on THIS client so it always appears on the terminal you pressed
# the key from — even when several clients are attached to the same server.
invoker="${1:-}"
client_session() { # client_session <client-name> -> its attached session name
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v c="$1" '$1 == c { print $2; exit }'
}

# A client NOT attached to a prefixed session — fallback host used only when the
# key was pressed from inside a popup (so the invoker itself is going away).
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) != 1 { print $1; exit }'
}

if [ -n "$invoker" ] && [[ "$(client_session "$invoker")" != "$prefix"* ]]; then
  # Pressed from a normal (non-popup) pane: host on that very client.
  host="$invoker"
else
  # Pressed from inside a session popup: close that popup so the picker can open
  # full-size on the outer client. tmux doesn't record which outer client spawned
  # the popup, so fall back to the first non-popup client (best effort).
  [ -n "$invoker" ] && tmux detach-client -t "$invoker" 2>/dev/null
  for _ in $(seq 1 100); do
    tmux list-clients -F '#{client_name}' 2>/dev/null | grep -qxF "$invoker" || break
    sleep 0.05
  done
  host="$(host_client)"
fi

tmux set-option -g @claude_parent "$host"

# -c is honored because the host client has no popup open now; fall back to the
# default client if none was resolved.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi

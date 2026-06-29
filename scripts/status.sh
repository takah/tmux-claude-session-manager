#!/usr/bin/env bash
# Print how many Claude sessions are currently waiting for you, for the tmux
# status bar. Prints nothing when none are waiting. Add it to your status line:
#   set -ag status-right '#(~/.tmux/plugins/tmux-claude-session-manager/scripts/status.sh)'
# It refreshes on tmux's status-interval. The count is derived live from each
# session's pane (same logic as the picker), so it can't go stale.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'c-')"
icon="$(get_tmux_option @claude_waiting_icon '⏳')"
# A tmux style applied to the count so it stands out. Add `,blink` if your
# terminal supports it; set to 'none' for no styling.
style="$(get_tmux_option @claude_waiting_style 'fg=colour231,bg=red,bold')"

n=0
while IFS= read -r s; do
  [ -n "$s" ] || continue
  [ "$(detect_state "$s")" = waiting ] && n=$((n + 1))
done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}")

[ "$n" -gt 0 ] || exit 0
if [ "$style" = none ]; then
  printf '%s%s' "$icon" "$n"
else
  printf '#[%s]%s%s#[default]' "$style" "$icon" "$n"
fi

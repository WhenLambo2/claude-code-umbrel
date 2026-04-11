#!/bin/bash
# attach-session-main.sh
# Called by ttyd on port 7681 / Tailscale HTTPS 8443.
# Attaches to the primary tmux session "claude-main" or creates it.

TMUX_SESSION="claude-main"

if su -s /bin/bash -c "tmux has-session -t $TMUX_SESSION" node 2>/dev/null; then
  exec su -s /bin/bash -c "tmux attach-session -t $TMUX_SESSION" node
else
  exec su -s /bin/bash -c "tmux new-session -s $TMUX_SESSION 'claude --dangerously-skip-permissions; exec /bin/bash'" node
fi

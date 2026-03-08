#!/bin/bash
# attach-session.sh
# Called by ttyd for each browser connection.
# Attaches to an existing tmux session or creates one running Claude Code.

TMUX_SESSION="claude"

# Check if tmux session already exists
if su -s /bin/bash -c "tmux has-session -t $TMUX_SESSION" node 2>/dev/null; then
  # Session exists, attach to it
  exec su -s /bin/bash -c "tmux attach-session -t $TMUX_SESSION" node
else
  # No session yet, create one running Claude Code
  exec su -s /bin/bash -c "tmux new-session -s $TMUX_SESSION 'claude --dangerously-skip-permissions; exec /bin/bash'" node
fi

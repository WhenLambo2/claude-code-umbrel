#!/bin/bash
# attach-session-side.sh
# Called by ttyd on port 7682.
# Attaches to the parallel tmux session "claude-side" or creates it.
# Used for running a second, independent Claude Code conversation
# alongside the main one (e.g. for side explorations, mobile, etc.).

TMUX_SESSION="claude-side"

if su -s /bin/bash -c "tmux has-session -t $TMUX_SESSION" node 2>/dev/null; then
  exec su -s /bin/bash -c "tmux attach-session -t $TMUX_SESSION" node
else
  exec su -s /bin/bash -c "tmux new-session -s $TMUX_SESSION 'claude --dangerously-skip-permissions; exec /bin/bash'" node
fi

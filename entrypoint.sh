#!/bin/bash
set -e

# Initialize firewall if enabled
if [ "$ENABLE_FIREWALL" = "true" ]; then
  echo "Initializing firewall..."
  sudo /usr/local/bin/init-firewall.sh || echo "Firewall init failed (missing NET_ADMIN capability?)"
fi

# Launch ttyd serving zsh on port 7681
exec ttyd \
  --writable \
  --port 7681 \
  --ping-interval 30 \
  --max-clients 5 \
  --title "Claude Code" \
  /usr/bin/zsh
#!/bin/bash
# start-services.sh — orchestrates every long-running process inside the
# Claude Code container. Replaces the inline entrypoint in docker-compose.yml.
#
# Started services (in order):
#   1. Bot runner (run-bot.sh if present)
#   2. sshd on port 2222 (pubkey auth, node user, host keys persisted in /workspace)
#   3. ttyd on port 7682 → tmux session "claude-side"  (parallel session)
#   4. ttyd on port 7681 → tmux session "claude-main"  (primary, foreground)
#
# Any service that fails to start is logged to /tmp/start-services.log and the
# script continues — we never want one failed helper to take down Claude Code.

set -e
exec 1> >(tee -a /tmp/start-services.log) 2>&1
echo "[$(date -Iseconds)] start-services.sh launching"

# ── 1. Bot runner ─────────────────────────────────────────────────────────────
BOT_SCRIPT=/workspace/ai-cos/system/run-bot.sh
if [ -x "$BOT_SCRIPT" ]; then
  echo "→ starting run-bot.sh"
  "$BOT_SCRIPT" &
else
  echo "→ run-bot.sh not found or not executable — skipping"
fi

# ── 2. SSH host keys (persisted in bind mount) ────────────────────────────────
SSH_KEY_DIR=/workspace/ai-cos/system/state/ssh-host-keys
mkdir -p "$SSH_KEY_DIR"
chmod 700 "$SSH_KEY_DIR"

if [ ! -f "$SSH_KEY_DIR/ssh_host_ed25519_key" ]; then
  echo "→ generating new SSH host keys (first-time)"
  ssh-keygen -t ed25519 -f "$SSH_KEY_DIR/ssh_host_ed25519_key" -N "" -q
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_DIR/ssh_host_rsa_key" -N "" -q
fi
chmod 600 "$SSH_KEY_DIR"/*_key
chmod 644 "$SSH_KEY_DIR"/*_key.pub

# ── 3. authorized_keys → node user ────────────────────────────────────────────
AUTH_KEYS_SRC=/usr/local/share/ssh/authorized_keys
AUTH_KEYS_DST=/home/node/.ssh/authorized_keys
if [ -f "$AUTH_KEYS_SRC" ]; then
  mkdir -p /home/node/.ssh
  chown node:node /home/node/.ssh
  chmod 700 /home/node/.ssh
  cp "$AUTH_KEYS_SRC" "$AUTH_KEYS_DST"
  chown node:node "$AUTH_KEYS_DST"
  chmod 600 "$AUTH_KEYS_DST"
  keycount=$(grep -cE '^(ssh-|ecdsa-)' "$AUTH_KEYS_DST" || echo 0)
  echo "→ installed $keycount SSH public key(s) for node user"
else
  echo "→ WARNING: no authorized_keys file found at $AUTH_KEYS_SRC — SSH will refuse all logins"
fi

# ── 4. sshd ──────────────────────────────────────────────────────────────────
mkdir -p /run/sshd
/usr/sbin/sshd -f /etc/ssh/sshd_config -D &
SSHD_PID=$!
echo "→ sshd started on port 2222 (pid $SSHD_PID)"

# ── 5. ttyd side session (port 7682) ──────────────────────────────────────────
ttyd --writable --port 7682 --ping-interval 30 --max-clients 5 \
  --title "Claude Code (side)" \
  /usr/local/bin/attach-session-side.sh &
TTYD_SIDE_PID=$!
echo "→ ttyd side session started on port 7682 (pid $TTYD_SIDE_PID)"

# ── 6. ttyd main session (port 7681, foreground — this keeps the container alive) ──
echo "→ ttyd main session starting on port 7681 (foreground)"
exec ttyd --writable --port 7681 --ping-interval 30 --max-clients 5 \
  --title "Claude Code (main)" \
  /usr/local/bin/attach-session-main.sh

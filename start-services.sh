#!/bin/bash
# start-services.sh
# Orchestrates all long-running processes inside the Claude Code container.
#
# Services started (in order):
# 1. Bot runner (run-bot.sh, background)
# 2. SSH host keys (generated once, persisted in bind mount)
# 3. sshd on port 2222 (pubkey auth only)
# 4. ttyd on port 7682 -> tmux "claude-side" (background)
# 5. ttyd on port 7681 -> tmux "claude-main" (foreground, keeps container alive)

set -e
exec 1> >(tee -a /tmp/start-services.log) 2>&1

echo "[$(date -Iseconds)] start-services.sh launching"

# 1. Bot runner
BOT_SCRIPT=/workspace/ai-cos/system/run-bot.sh
if [ -x "$BOT_SCRIPT" ]; then
  echo "-> starting run-bot.sh"
  "$BOT_SCRIPT" &
else
  echo "-> run-bot.sh not found or not executable, skipping"
fi

# 2. SSH host keys (persisted across restarts via bind mount)
SSH_KEY_DIR=/workspace/ai-cos/system/state/ssh-host-keys
mkdir -p "$SSH_KEY_DIR"
chmod 700 "$SSH_KEY_DIR"

if [ ! -f "$SSH_KEY_DIR/ssh_host_ed25519_key" ]; then
  echo "-> generating new SSH host keys (first run)"
  ssh-keygen -t ed25519 -f "$SSH_KEY_DIR/ssh_host_ed25519_key" -N "" -q
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_DIR/ssh_host_rsa_key" -N "" -q
fi
chmod 600 "$SSH_KEY_DIR"/*_key 2>/dev/null || true
chmod 644 "$SSH_KEY_DIR"/*_key.pub 2>/dev/null || true

# 3. Authorized keys for node user
AUTH_KEYS_SRC=/workspace/ai-cos/system/state/ssh-host-keys/authorized_keys
AUTH_KEYS_DST=/home/node/.ssh/authorized_keys
if [ -f "$AUTH_KEYS_SRC" ]; then
  mkdir -p /home/node/.ssh
  chown node:node /home/node/.ssh
  chmod 700 /home/node/.ssh
  cp "$AUTH_KEYS_SRC" "$AUTH_KEYS_DST"
  chown node:node "$AUTH_KEYS_DST"
  chmod 600 "$AUTH_KEYS_DST"
  keycount=$(grep -cE '^(ssh-|ecdsa-)' "$AUTH_KEYS_DST" || echo 0)
  echo "-> installed $keycount SSH public key(s) for node user"
else
  echo "-> no authorized_keys found at $AUTH_KEYS_SRC, SSH logins disabled"
  echo "-> to enable: place your public keys in $AUTH_KEYS_SRC"
fi

# 4. sshd
mkdir -p /run/sshd
/usr/sbin/sshd -f /etc/ssh/sshd_config -D &
SSHD_PID=$!
echo "-> sshd started on port 2222 (pid $SSHD_PID)"

# 5. ttyd side session (port 7682, background)
# NOTE: no --title flag, it breaks in DinD environments
ttyd --writable --port 7682 --ping-interval 30 --max-clients 5 \
  /usr/local/bin/attach-session-side.sh &
TTYD_SIDE_PID=$!
echo "-> ttyd side session on port 7682 (pid $TTYD_SIDE_PID)"

# 6. ttyd main session (port 7681, foreground - keeps container alive)
echo "-> ttyd main session on port 7681 (foreground)"
exec ttyd --writable --port 7681 --ping-interval 30 --max-clients 5 \
  /usr/local/bin/attach-session-main.sh

FROM node:20

ARG TZ=Europe/Amsterdam
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools, iptables/ipset, and ttyd for web terminal
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  cmake \
  g++ \
  pkg-config \
  libwebsockets-dev \
  libjson-c-dev \
  libssl-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install ttyd from source for web terminal access
ARG TTYD_VERSION=1.7.7
RUN cd /tmp && \
  wget "https://github.com/nicm/tmux/releases/download/3.3a/tmux-3.3a.tar.gz" -O /dev/null 2>&1 || true && \
  wget "https://github.com/nicm/tmux/releases/download/3.4/tmux-3.4.tar.gz" -O /dev/null 2>&1 || true && \
  wget "https://github.com/nicm/tmux/releases/download/3.5/tmux-3.5.tar.gz" -O /dev/null 2>&1 || true && \
  ARCH=$(dpkg --print-architecture) && \
  if [ "$ARCH" = "amd64" ]; then TTYD_ARCH="x86_64"; else TTYD_ARCH="$ARCH"; fi && \
  wget "https://github.com/nicm/tmux/releases/download/3.5/tmux-3.5.tar.gz" -O /dev/null 2>&1 || true && \
  wget "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" -O /usr/local/bin/ttyd && \
  chmod +x /usr/local/bin/ttyd

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash/zsh history
RUN mkdir /commandhistory && \
  touch /commandhistory/.bash_history && \
  touch /commandhistory/.zsh_history && \
  chown -R $USERNAME /commandhistory

# Set environment variables
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

# Install git-delta for better diffs
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh
ENV SHELL=/bin/zsh

# Set editors
ENV EDITOR=nano
ENV VISUAL=nano

# Install oh-my-zsh with powerline theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export HISTFILE=/commandhistory/.zsh_history" \
  -x

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

USER node

EXPOSE 7681

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:7681/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

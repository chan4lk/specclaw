FROM node:22-bookworm-slim

ARG CLAUDE_CODE_VERSION
ARG CODEX_VERSION
ARG TARGETARCH
ARG PLAYWRIGHT_VERSION=1.65.0
ARG JSCPD_VERSION=5.4.2
ARG LIZARD_VERSION=1.25.1

RUN test -n "$CLAUDE_CODE_VERSION" && test -n "$CODEX_VERSION" \
 && apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates jq python3 python3-pip \
 && pip3 install --no-cache-dir --break-system-packages "lizard==${LIZARD_VERSION}" \
 && npm install -g "playwright@${PLAYWRIGHT_VERSION}" "jscpd@${JSCPD_VERSION}" \
 && PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install --with-deps chromium \
 && chmod -R a+rX /opt/ms-playwright \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /usr/local/bin/claude "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-$([ "$TARGETARCH" = arm64 ] && echo arm64 || echo x64)/claude" \
 && chmod +x /usr/local/bin/claude \
 && npm install -g "@openai/codex@${CODEX_VERSION}" \
 && git config --system user.name "specclaw-fleet" \
 && git config --system user.email "specclaw-fleet@noreply.local" \
 && mkdir -p /opt/fleet/home-seed /home/agent \
 && chown 1000:1000 /opt/fleet/home-seed /home/agent

COPY .claude-plugin /opt/specclaw/.claude-plugin
COPY .agents /opt/specclaw/.agents
COPY plugins /opt/specclaw/plugins
COPY plugins/specclaw-fleet/image/*.sh /opt/fleet/
COPY plugins/specclaw-fleet/image/bin/claude /opt/fleet/bin/claude

ENV HOME=/home/agent \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PATH="/opt/fleet/bin:/opt/specclaw/plugins/specclaw/bin:/opt/specclaw/plugins/specclaw-sync/bin:/opt/specclaw/plugins/specclaw-extras/bin:/opt/specclaw/plugins/specclaw-review/bin:${PATH}"

USER 1000

RUN mkdir -p /opt/fleet/home-seed/.codex \
 && HOME=/opt/fleet/home-seed claude plugin marketplace add /opt/specclaw \
 && HOME=/opt/fleet/home-seed claude plugin install specclaw@chan4lk \
 && HOME=/opt/fleet/home-seed claude plugin install specclaw-sync@chan4lk \
 && CODEX_HOME=/opt/fleet/home-seed/.codex codex plugin marketplace add /opt/specclaw

ENTRYPOINT ["/opt/fleet/entrypoint.sh"]

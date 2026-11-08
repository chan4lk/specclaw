FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS seed

ARG CLAUDE_CODE_VERSION=2.1.319

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git gnupg jq \
 && rm -rf /var/lib/apt/lists/*

COPY plugins/specclaw-fleet/image/claude-fetch.sh plugins/specclaw-fleet/image/claude-release.asc /opt/fleet/
RUN bash -c 'set -e; source /opt/fleet/claude-fetch.sh; HOME=/tmp/seedhome FLEET_CLAUDE_VERSION="$CLAUDE_CODE_VERSION" fetch_claude' \
 && cp /tmp/seedhome/.fleet/bin/claude /tmp/claude

COPY .claude-plugin /opt/specclaw/.claude-plugin
COPY .agents /opt/specclaw/.agents
COPY plugins /opt/specclaw/plugins

RUN mkdir -p /opt/fleet/home-seed \
 && HOME=/opt/fleet/home-seed /tmp/claude plugin marketplace add /opt/specclaw \
 && HOME=/opt/fleet/home-seed /tmp/claude plugin install specclaw@chan4lk \
 && HOME=/opt/fleet/home-seed /tmp/claude plugin install specclaw-sync@chan4lk \
 && HOME=/opt/fleet/home-seed /tmp/claude plugin install specclaw-review@chan4lk

FROM node:22-bookworm-slim@sha256:5ec23b7c622b00547753bc6ffd78085dd868a68aeb41c8e0a1418f033e13d96d

ARG CODEX_VERSION
ARG PLAYWRIGHT_VERSION=1.65.0
ARG JSCPD_VERSION=5.4.2
ARG LIZARD_VERSION=1.25.1

RUN test -n "$CODEX_VERSION" \
 && apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates jq python3 python3-pip gnupg \
 && pip3 install --no-cache-dir --break-system-packages "lizard==${LIZARD_VERSION}" \
 && npm install -g "@openai/codex@${CODEX_VERSION}" "playwright@${PLAYWRIGHT_VERSION}" "jscpd@${JSCPD_VERSION}" \
 && PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install --with-deps chromium \
 && chmod -R a+rX /opt/ms-playwright \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system user.name "specclaw-fleet" \
 && git config --system user.email "specclaw-fleet@noreply.local" \
 && mkdir -p /home/agent && chown 1000:1000 /home/agent

COPY .claude-plugin /opt/specclaw/.claude-plugin
COPY .agents /opt/specclaw/.agents
COPY plugins /opt/specclaw/plugins
COPY --from=seed --chown=1000:1000 /opt/fleet/home-seed /opt/fleet/home-seed
COPY plugins/specclaw-fleet/image/*.sh plugins/specclaw-fleet/image/claude-release.asc /opt/fleet/
COPY plugins/specclaw-fleet/image/bin/claude /opt/fleet/bin/claude

RUN G="$(mktemp -d)" && gpg --homedir "$G" --batch --quiet --import /opt/fleet/claude-release.asc \
 && gpg --homedir "$G" --batch --with-colons --fingerprint | grep -q '^fpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:$' \
 && rm -rf "$G"

ENV HOME=/home/agent \
    DISABLE_UPDATES=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PATH="/opt/fleet/bin:/opt/specclaw/plugins/specclaw/bin:/opt/specclaw/plugins/specclaw-sync/bin:/opt/specclaw/plugins/specclaw-extras/bin:/opt/specclaw/plugins/specclaw-review/bin:${PATH}"

USER 1000

RUN mkdir -p /opt/fleet/home-seed/.codex \
 && CODEX_HOME=/opt/fleet/home-seed/.codex codex plugin marketplace add /opt/specclaw

ENTRYPOINT ["/opt/fleet/entrypoint.sh"]

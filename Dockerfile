FROM alpine:3.22

# The rex version is pinned so builds are reproducible. .github/workflows/update-rex.yml
# bumps REX_VERSION daily to the newest build on REX_CHANNEL and commits it, which makes
# Render redeploy. The snapshot channel only keeps its last ~20 builds (a few days), so an
# old pin stops resolving; let the workflow keep it current.
ARG REX_CHANNEL=snapshot
ARG REX_VERSION=0.0.1794632741-r0
# Name of the key that signs the apk packages. apk only trusts a signature when the key is
# saved under exactly this name. The workflow checks it against APK_KEY_NAME in install.sh.
ARG REX_APK_KEY=hello@superlogical.com-33cd23a8.rsa.pub

# Install rex from the superlogical apk repo, plus tini to reap orphaned child processes
# (rex spawns shells) and a few basics for interactive use.
RUN wget -O "/etc/apk/keys/${REX_APK_KEY}" "https://pkgs.superlogical.com/rex/keys/${REX_APK_KEY}" \
 && mkdir -p /etc/apk/repositories.d \
 && echo "https://pkgs.superlogical.com/rex/apk/${REX_CHANNEL}" > /etc/apk/repositories.d/rex.list \
 && apk add --no-cache "rex=${REX_VERSION}" tini bash ca-certificates \
 && rex version

# Claude Code, via the native installer. On musl (Alpine) it needs libgcc, libstdc++ and a
# system ripgrep (USE_BUILTIN_RIPGREP=0). The installer puts the binary under /root/.local;
# the /usr/local/bin symlink keeps it on PATH for login shells, because Alpine's
# /etc/profile resets PATH. Config and login live on the disk (CLAUDE_CONFIG_DIR) so they
# survive redeploys; the profile.d file sets it for login shells that drop the image ENV.
ENV USE_BUILTIN_RIPGREP=0 \
    CLAUDE_CONFIG_DIR=/data/claude
RUN apk add --no-cache curl git libgcc libstdc++ ripgrep \
 && curl -fsSL https://claude.ai/install.sh | bash \
 && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
 && printf 'export USE_BUILTIN_RIPGREP=0\nexport CLAUDE_CONFIG_DIR=/data/claude\n' > /etc/profile.d/claude.sh \
 && claude --version

# Persistent state: saved sessions and the embedded Tailscale node identity.
# Mount a Render disk here so the node doesn't re-enroll on every deploy.
ENV REX_STATE_DIR=/data \
    REX_TAILSCALE_HOSTNAME=rex-render
VOLUME /data

# Remote access goes through rex's embedded Tailscale node, not a public port.
# Set TS_AUTHKEY to enroll automatically; without it, a login URL is logged.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "exec rex server run --tailscale --tailscale-hostname \"$REX_TAILSCALE_HOSTNAME\" --state-dir \"$REX_STATE_DIR\" --log-format json"]

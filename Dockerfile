FROM alpine:3.22

# Install rex from the superlogical apk repo, plus tini to reap orphaned
# child processes (rex spawns shells) and a few basics for interactive use.
RUN wget -O /etc/apk/keys/hello@superlogical.com-33cd23a8.rsa.pub \
      https://pkgs.superlogical.com/rex/keys/hello@superlogical.com-33cd23a8.rsa.pub \
 && echo "https://pkgs.superlogical.com/rex/apk/snapshot" >> /etc/apk/repositories \
 && apk add --no-cache rex tini bash ca-certificates

# Persistent state: saved sessions and the embedded Tailscale node identity.
# Mount a Render disk here so the node doesn't re-enroll on every deploy.
ENV REX_STATE_DIR=/data \
    REX_TAILSCALE_HOSTNAME=rex-render
VOLUME /data

# Remote access goes through rex's embedded Tailscale node, not a public port.
# Set TS_AUTHKEY to enroll automatically; without it, a login URL is logged.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "exec rex server run --tailscale --tailscale-hostname \"$REX_TAILSCALE_HOSTNAME\" --state-dir \"$REX_STATE_DIR\" --log-format json"]

# rex on Render

Run a [rex](https://www.superlogical.com/rex/docs/installation) server on [Render](https://render.com). You reach it over your [Tailscale](https://tailscale.com) tailnet, and it has no public port.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/amalgamated-tools/rex)

## How it works

- The image is Alpine Linux with rex installed from the superlogical apk repository. The rex version is pinned in the `Dockerfile` (`ARG REX_VERSION`).
- A GitHub workflow ([`update-rex.yml`](.github/workflows/update-rex.yml)) runs every day at 09:00 UTC. It finds the newest rex build on the channel, test-builds the image, and commits the new pin to `main`. Render then redeploys. See [Updates](#updates).
- It runs `rex server run --tailscale`, so rex starts its own embedded Tailscale node. No `tailscaled` sidecar is needed.
- On Render it is a **background worker**. Nothing listens on a public URL. Only devices on your tailnet can connect, and Tailscale tells rex who each caller is.
- A persistent disk at `/data` stores the saved sessions and the Tailscale node identity. Redeploys and restarts come back as the same node with the same sessions.

### Why Tailscale and not a public port?

rex is a terminal multiplexer, so a connection to it is a shell. Over plain HTTP, rex can't tell who is calling. It refuses to start that way unless you pass `--allow-anonymous`, which gives **every** caller full access. On a public `onrender.com` URL, that would be a root shell for anyone who finds it. Tailscale gives each caller an identity and keeps the server off the public internet.

## Deploy

1. **Create a Tailscale auth key** in the Tailscale admin console under Settings → Keys. Recommended settings:
   - **Not ephemeral.** An ephemeral node is deleted soon after it goes offline, and that happens on every deploy. The identity saved on the disk would then point at a deleted node.
   - **Tagged**, for example `tag:rex`. Tagged nodes have key expiry turned off, and tags let you limit who can reach rex with ACLs.
   - **Reusable**, so the server can enroll again if the disk is ever lost. Use a one-time key if you would rather not keep a reusable secret around.
   - **Pre-approved**, if your tailnet requires device approval.
2. **Turn on MagicDNS and HTTPS Certificates** in the Tailscale admin console under DNS. rex serves its API over HTTPS on the tailnet and needs a certificate.
3. **Click "Deploy to Render"** above and paste the key when Render asks for `TS_AUTHKEY`.

The Blueprint uses the `starter` plan, because persistent disks need a paid instance type.

If you leave `TS_AUTHKEY` empty, the service logs print a `https://login.tailscale.com/a/...` link. Open it to sign the node in yourself.

## Connect

When the node is up, the logs show:

```
tailnet https listener ready  url=https://rex-render.<your-tailnet>.ts.net
```

Connect with the **full** MagicDNS name. The certificate is issued for that name only, so the short name `rex-render` fails TLS verification.

```sh
rex -S rex-render.<your-tailnet>.ts.net ls
```

Save it as a host so you can use a short label:

```sh
rex hosts add render rex-render.<your-tailnet>.ts.net
rex -S render new
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `TS_AUTHKEY` | *(none)* | Tailscale auth key used to enroll the node the first time. |
| `REX_TAILSCALE_HOSTNAME` | `rex-render` | Device name on your tailnet. |
| `REX_STATE_DIR` | `/data` | Where rex keeps sessions and the Tailscale state. Keep this on the disk. |

The image includes [Claude Code](https://claude.com/claude-code). Run `claude` in a session and sign in once. Its config and login are kept in `/data/claude` (`CLAUDE_CONFIG_DIR`), so they survive redeploys.

To add tools to your sessions, such as git, an editor or language runtimes, add them to the `apk add` line in the `Dockerfile`.

## Updates

The `Dockerfile` pins these build arguments:

| Argument | Purpose |
| --- | --- |
| `REX_CHANNEL` | Release channel: `snapshot` (every change), `preview` or `stable`. |
| `REX_VERSION` | Exact apk version of rex, for example `0.0.1793899293-r0`. |
| `REX_APK_KEY` | File name of the key that signs the packages. |

The [`update-rex.yml`](.github/workflows/update-rex.yml) workflow keeps `REX_VERSION` current. It runs every day at 09:00 UTC, and you can also start it by hand from the Actions tab. Each run:

1. Reads `APK_KEY_NAME` from the official [`install.sh`](https://pkgs.superlogical.com/rex/install.sh). If it no longer matches `REX_APK_KEY`, the run stops so you can review the change.
2. Finds the newest `rex` in the channel's package index.
3. If that is newer than the pin, it updates the `Dockerfile`, builds the image, checks that the server starts, and commits to `main`.

Things to know:

- **The workflow commits straight to `main`.** The snapshot channel keeps only its last ~20 builds, which is a few days' worth. A pin that sits unmerged in a PR soon points at a version that no longer exists, and any redeploy of `main` would then fail.
- **Each update is a redeploy**, and a redeploy stops the programs running inside rex sessions. That's why the workflow runs once a day at a quiet hour. To change the time, edit its `cron` line.
- To roll back, revert the update commit. This only works while the older version is still in the channel's index.

## Notes and troubleshooting

- **`Authkey is set; but state is NoState. Ignoring authkey`** is normal after the first deploy. rex found the saved identity on the disk and reused it. Set `TSNET_FORCE_LOGIN=1` only when you want to enroll a new node on purpose.
- **`tailnet https certificate request failed ... status: invalid`** can happen on a brand-new node while its DNS name is still settling. Check that HTTPS Certificates is on, then restart the service once. Don't restart over and over: Let's Encrypt limits how many certificates one hostname can get per week.
- **The container runs as root**, so every shell you open in rex is a root shell inside the container.
- **A redeploy stops running programs.** Saved sessions come back after a restart, but the processes inside them don't survive one.

## Run locally

```sh
docker build -t rex-render .
docker run --rm -e TS_AUTHKEY=tskey-auth-... -v rex-data:/data rex-render
```

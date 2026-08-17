# Minimal Start Suite

The "three essentials" — the natural first deployment after hardening a VPS. A reverse proxy with automatic SSL, uptime monitoring, and performance monitoring. This is the foundation every other suite builds on.

## What's Included

| App | Purpose | Default Port | Profile |
|---|---|---|---|
| Caddy | Reverse proxy + automatic SSL | 80, 443 | Default |
| Uptime Kuma | Uptime monitoring | 3001 | Default |
| Beszel agent | Performance monitoring agent | 45876 | Default |

## Quick Start

```bash
# Deploy the three essentials
docker compose up -d

# View running services
docker compose ps

# Stop everything
docker compose down
```

This suite has no optional services — every app is in the default profile and starts together.

## Data Directories

```
/data/caddy/         — Caddy data (certificates) and config
/data/uptime-kuma/   — Uptime Kuma database and monitors
/data/beszel/        — Beszel agent state
```

## Caddy Setup

The `Caddyfile` is **auto-generated from `.env`** when you deploy through the `mb` CLI. It configures Caddy to serve `PRIMARY_DOMAIN` over HTTPS with automatic certificate provisioning via Let's Encrypt.

To add more sites (for this suite or any other suite's services), use:

```bash
mb net proxy add
# Set the domain, target container, and port
```

Caddy routes traffic to containers by name over the shared `mb-proxy` network. Any container that joins `mb-proxy` is reachable from Caddy — that's how suites like `home-media` or `personal-productivity` get HTTPS without running their own proxy.

## Monitoring Setup

### Uptime Kuma

Access Uptime Kuma at `http://<your-server>:3001` (or via your domain once Caddy proxies it). The first-run wizard lets you create an admin account. From there you can:

- Add HTTP/TCP/ping monitors for any service
- Set up notification channels (Discord, Telegram, email, etc.)
- Group monitors by status page

### Beszel Agent

The Beszel agent collects system metrics (CPU, memory, disk, network) and reports them to a **Beszel hub**. The hub is not included in this suite — it can run on another server, or you can deploy it separately.

To connect the agent to a hub:

1. Deploy a Beszel hub instance (see [beszel](https://github.com/henrygd/beszel)).
2. In the hub UI, add a new agent — you'll get a key and hub URL.
3. Set `BESZEL_HUB_KEY` and `BESZEL_HUB_URL` in your `.env`.
4. Restart the agent: `docker compose restart beszel-agent`.

The agent needs `SYS_ADMIN` capability and read-only `/proc` access to read host metrics.

## Why This Suite

This is the **recommended first deployment after [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap)**. Once a VPS is hardened (SSH keys, firewall, fail2ban, automatic updates), you need three things before anything else:

1. **A reverse proxy** — so every service you add later gets HTTPS automatically, without per-app certificate management.
2. **Uptime monitoring** — so you know when things go down, before your users do.
3. **Performance monitoring** — so you can see resource pressure building up before it becomes an outage.

Deploy this suite first, then layer on other suites ([home-media](https://github.com/0x10debug/compose-recipes/tree/main/suites/home-media), [personal-productivity](https://github.com/0x10debug/compose-recipes/tree/main/suites/personal-productivity), etc.). They all join the same `mb-proxy` network and get proxied by the Caddy instance running here.

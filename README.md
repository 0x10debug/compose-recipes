# Self-Hosted App Suites — Docker Compose Recipes for VPS

Production-ready Docker Compose recipes organized by real-world scenarios. Instead of choosing from 1000+ apps, pick a suite that matches your needs—home media, personal productivity, dev environment, privacy, or self-hosted cloud—and deploy with one command. Each suite comes with pre-configured networking, port allocation, and reverse proxy integration. Built for VPS and homelab servers running Docker.

> **New to self-hosting?** Start with the [minimal-start](suites/minimal-start/) suite — it deploys a reverse proxy, uptime monitor, and performance monitor in one command. Then add more suites as you need them.

## Why This Exists

When you want to self-host apps on your VPS, you face several problems:

1. **Too many choices** — awesome-selfhosted lists 1000+ apps. Which ones do you pick?
2. **Per-app configuration** — Each app has its own compose file, environment variables, ports, and volumes to figure out
3. **Multi-app conflicts** — Running multiple apps means managing port conflicts, network configuration, and reverse proxy integration
4. **No scenario guidance** — Existing compose collections give you "a list of apps" not "a solution for your use case"

This repo solves that by providing **scenario-based suites** — pre-orchestrated combinations of apps that work together for a specific use case, with all the plumbing already configured.

## What's a Suite?

A suite is a directory containing a `compose.yml` file with one or more apps pre-configured to work together:

- **Ports pre-allocated** — no conflicts between apps in the same suite or across suites
- **Network pre-configured** — all apps join the `mb-proxy` Docker network for reverse proxy integration
- **Data paths unified** — all data goes to `/data/<app-name>/`
- **.env template included** — fill in your domain and secrets, deploy
- **Profiles support** — optional apps can be enabled/disabled via `--profile`

## Available Suites

| Suite | Apps | Use Case |
|---|---|---|
| [home-media](suites/home-media/) | Jellyfin, Navidrome, Audiobookshelf, Immich | Replace Netflix, Spotify, Audible, Google Photos |
| [personal-productivity](suites/personal-productivity/) | Vaultwarden, Memos, Outline, Linkwarden | Password manager, notes, knowledge base, bookmarks |
| [dev-environment](suites/dev-environment/) | Gitea, Code Server, Woodpecker CI, Registry | Self-hosted Git, browser IDE, CI/CD, Docker registry |
| [privacy-suite](suites/privacy-suite/) | AdGuard Home, SearXNG, Vaultwarden, WireGuard | DNS ad blocking, private search, VPN |
| [self-hosted-cloud](suites/self-hosted-cloud/) | Nextcloud, OnlyOffice, Filebrowser, Radicale | Replace Google Drive, Office365, Dropbox |
| [minimal-start](suites/minimal-start/) | Caddy, Uptime Kuma, Beszel | The essentials: reverse proxy, monitoring |

## Quick Start

```bash
# 1. Harden your VPS and install Docker (if not done)
# → https://github.com/0x10debug/vps-bootstrap

# 2. Clone this repo
git clone https://github.com/0x10debug/compose-recipes.git
cd compose-recipes

# 3. List available suites
./mb recipes list

# 4. Deploy a suite (interactive .env setup)
./mb recipes deploy home-media

# 5. Deploy with optional apps
./mb recipes deploy home-media --profile transmission

# 6. Check status
./mb recipes status
```

## Usage

```bash
mb recipes list                        # List all available suites
mb recipes deploy <suite>              # Deploy a suite (interactive)
mb recipes deploy <suite> --env-file .env  # Deploy with existing .env
mb recipes status                      # Show deployed suites status
mb recipes update [<suite>]            # Update suite images (all or specific)
mb recipes stop [<suite>]              # Stop suite(s)
mb recipes remove <suite>              # Remove suite (keeps data)
mb recipes help                        # Show help
```

## FAQ

### How to deploy multiple self-hosted apps with Docker Compose?

Pick a suite from this repo, run `mb recipes deploy <suite>`, fill in the .env file, and all apps in the suite start together with pre-configured networking and no port conflicts. Each suite is designed for a specific scenario (home media, productivity, dev, privacy, cloud).

### How to set up a home media server on VPS?

Deploy the [home-media](suites/home-media/) suite — it includes Jellyfin (video), Navidrome (music), Audiobookshelf (audiobooks), and Immich (photos). All four start with one command: `mb recipes deploy home-media`. Optional: enable Transmission for BT downloads with `--profile transmission`.

### How to organize Docker Compose for multiple services?

Use the suite pattern: group related apps into a single `compose.yml` with profiles for optional components. All services share the `mb-proxy` network for reverse proxy integration, and data goes to `/data/<app-name>/` for consistent volume management. See [contributing-suites.md](docs/contributing-suites.md) to create your own.

### How to avoid port conflicts in self-hosted apps?

All suites in this repo follow a [global port allocation table](docs/port-allocation.md). Each app has a pre-assigned port that doesn't conflict with apps in other suites. If you need to run the same app from two different suites, override the port in your `.env` file.

### Best self-hosted app suites for homelab?

The suites in this repo cover the most common homelab scenarios: home media, personal productivity, development, privacy, and cloud storage. Start with [minimal-start](suites/minimal-start/) for the essentials, then add suites as needed. Each suite is independent — deploy only what you need.

## Documentation

- [Port Allocation](docs/port-allocation.md) — Global port planning across all suites
- [Reverse Proxy Setup](docs/reverse-proxy-setup.md) — How to expose your apps with HTTPS
- [Contributing Suites](docs/contributing-suites.md) — How to create and submit new suites

## Related

- [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) — One-command VPS initialization and security hardening
- [network-toolkit](https://github.com/0x10debug/network-toolkit) — Reverse proxy, SSL, and tunnel templates
- [monitor-stack](https://github.com/0x10debug/monitor-stack) — Lightweight monitoring stack
- [backup-kit](https://github.com/0x10debug/backup-kit) — Pre-configured backup strategies

## License

[MIT](./LICENSE)

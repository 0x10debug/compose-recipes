# Development Environment Suite

A self-hosted development toolchain running on your VPS: Git hosting, a browser-based IDE, CI/CD pipelines, and a private container registry. Replace GitHub, VS Code Remote, GitHub Actions, and Docker Hub with services you control.

## What's Included

| App | Purpose | Default Port | Profile |
|---|---|---|---|
| Gitea | Self-hosted Git hosting | 3000 (web), 2222 (SSH) | Default |
| Code Server | VS Code in the browser | 8443 | Default |
| Woodpecker CI | CI/CD pipelines | 8000 | `ci` |
| Registry | Private Docker registry | 5000 | `registry` |

## Quick Start

```bash
# Deploy Gitea + Code Server (default)
docker compose up -d

# Add Woodpecker CI (needs Gitea running first)
docker compose --profile all --profile ci up -d

# Add private container registry
docker compose --profile all --profile registry up -d

# Deploy everything
docker compose --profile all --profile ci --profile registry up -d
```

## Data Directories

```
/data/gitea/            — Gitea app data, config, and repositories
/data/gitea/postgres/   — Gitea PostgreSQL database
/data/code-server/      — Code Server config and workspace
/data/woodpecker/       — Woodpecker CI data
/data/woodpecker/postgres/ — Woodpecker PostgreSQL database
/data/registry/         — Container registry storage and auth
```

## Reverse Proxy

To expose this suite via HTTPS with a domain, use [network-toolkit](https://github.com/0x10debug/network-toolkit):

```bash
mb net deploy website
# Set WEBSITE_DOMAIN=git.example.com
# Set APP_HOST=gitea
# Set APP_PORT=3000
```

Repeat for each app you want to expose (Code Server, Woodpecker CI, Registry). Gitea SSH (port 2222) needs a separate TCP proxy entry.

## Setup Notes

- **Gitea**: On first launch, complete the web installer at `http://<host>:3000`. The database is preconfigured via environment variables; create your initial admin user on the setup page.
- **Woodpecker CI**: Requires an OAuth application registered in Gitea. In Gitea, go to *Settings → Applications → OAuth2*, create an app with redirect URL `https://<DEV_DOMAIN>/authorize`. Copy the client ID and secret into `WOODPECKER_GITEA_CLIENT` and `WOODPECKER_GITEA_SECRET` in `.env`, then start with `--profile ci`.
- **Code Server**: Set the login password via `CODE_SERVER_PASSWORD` in `.env`. Repository directories are mounted at `/config/workspace/repos` for direct editing.
- **Registry**: For push/push access control, add htpasswd auth at `/data/registry/auth/htpasswd` and enable `REGISTRY_AUTH` in the compose file.

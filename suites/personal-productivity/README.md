# Personal Productivity Suite

A self-hosted productivity stack that replaces 1Password, Evernote, Notion, Pocket, and Adobe Acrobat. Manage your passwords, notes, team knowledge base, bookmarks, and PDF tools from your own VPS.

## What's Included

| App | Purpose | Default Port | Profile |
|---|---|---|---|
| Vaultwarden | Password manager (Bitwarden-compatible) | 8222 | Default |
| Memos | Lightweight notes | 5230 | Default |
| Outline | Team knowledge base | 3000 | Default |
| Linkwarden | Bookmark management | 3001 | Default |
| Stirling-PDF | PDF tools | 8800 | `pdf` |

## Quick Start

```bash
# Deploy with default apps only
docker compose up -d

# Deploy with PDF tools enabled
docker compose --profile pdf up -d

# Deploy everything
docker compose --profile all --profile pdf up -d
```

## Data Directories

```
/data/vaultwarden/    — Vaultwarden vault data and attachments
/data/memos/          — Memos notes database
/data/outline/        — Outline data, uploads, postgres, and redis
/data/linkwarden/     — Linkwarden bookmarks and postgres
/data/stirling-pdf/   — Stirling-PDF config, logs, and custom files
```

## Reverse Proxy

To expose this suite via HTTPS with a domain, use [network-toolkit](https://github.com/0x10debug/network-toolkit):

```bash
mb net deploy website
# Set WEBSITE_DOMAIN=vault.example.com
# Set APP_HOST=vaultwarden
# Set APP_PORT=80
```

Repeat for each app you want to expose (Memos, Outline, Linkwarden, Stirling-PDF).

## Security Note

**Vaultwarden requires HTTPS before use.** Bitwarden clients refuse to sync over plain HTTP. Enable a reverse proxy with TLS (via [network-toolkit](https://github.com/0x10debug/network-toolkit)) before creating your vault or inviting users. Keep `VAULTWARDEN_SIGNUPS_ALLOWED=false` to prevent open registration, and set a strong `VAULTWARDEN_ADMIN_TOKEN` to protect the admin panel.

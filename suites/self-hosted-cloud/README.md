# Self-Hosted Cloud Suite

A self-hosted replacement for Google Drive, Dropbox, and Office365. Provides file sync, collaborative document editing, a file manager, and calendar/contacts (CalDAV/CardDAV).

## What's Included

| App | Purpose | Default Port | Profile |
|-----|---------|--------------|---------|
| Nextcloud | File sync + collaboration | 8080 | default |
| OnlyOffice | Document editor (Docs, Sheets, Slides) | 8443 | default |
| Filebrowser | Web-based file manager | 8081 | default |
| Radicale | Calendar / contacts (CalDAV / CardDAV) | 5232 | pim |

## Quick Start

1. Copy the example env file and fill in your values:

   ```bash
   cp .env.example .env
   # edit .env — set CLOUD_DOMAIN, passwords, and ONLYOFFICE_JWT_SECRET
   ```

2. Create the data directories (see [Data Directories](#data-directories)).

3. Start the default services (Nextcloud, OnlyOffice, Filebrowser):

   ```bash
   docker compose up -d
   ```

4. To also start the PIM stack (Radicale), use the `pim` profile:

   ```bash
   docker compose --profile pim up -d
   ```

5. To start everything at once:

   ```bash
   docker compose --profile all up -d
   ```

## Data Directories

All persistent data lives under `/data` on the host:

| Path | Service |
|------|---------|
| `/data/nextcloud` | Nextcloud user files |
| `/data/nextcloud-apps` | Nextcloud installed apps |
| `/data/nextcloud-config` | Nextcloud config |
| `/data/nextcloud-postgres` | Nextcloud PostgreSQL database |
| `/data/nextcloud-redis` | Nextcloud Redis cache |
| `/data/onlyoffice` | OnlyOffice document server data |
| `/data/filebrowser` | Filebrowser database + config |
| `/data/radicale` | Radicale calendar/contacts data |

Filebrowser additionally mounts `/data` (the whole host data root) at `/srv` inside the container, so it can browse any files you place under `/data`.

## Reverse Proxy

This suite is designed to sit behind a reverse proxy on the external `mb-proxy` Docker network. Set up TLS termination and route traffic to each service's container port.

For a ready-made reverse proxy / networking toolkit, see:
https://github.com/0x10debug/network-toolkit

## Nextcloud Setup

1. Open `https://<CLOUD_DOMAIN>` (or `http://localhost:8080` for local testing) in your browser.
2. Complete the initial setup wizard. The database is already pre-configured via environment variables (PostgreSQL + Redis), so the installer should pick those up automatically.
3. Verify **Trusted domains** — `NEXTCLOUD_TRUSTED_DOMAINS` is set from `CLOUD_DOMAIN` in `.env`. If you access Nextcloud via additional domains or IPs, add them in `config/config.php` under `trusted_domains`.
4. Set `overwrite.cli.url` and `overwriteprotocol` are configured for HTTPS behind a reverse proxy. Adjust if serving over HTTP.

## OnlyOffice Integration

1. OnlyOffice Document Server runs on port `8443` with JWT authentication enabled (`ONLYOFFICE_JWT_SECRET`).
2. In Nextcloud, install the **ONLYOffice** connector app:
   - Apps → Office & text → **ONLYOffice** → Enable.
3. Go to Administration settings → ONLYOffice:
   - **Document Editing Service address**: `https://<CLOUD_DOMAIN>` (or the OnlyOffice container URL if on the same network, e.g. `https://onlyoffice`).
   - **Secret key**: the value of `ONLYOFFICE_JWT_SECRET` from your `.env`.
4. Save. You should now be able to create and co-edit `.docx`, `.xlsx`, and `.pptx` files directly inside Nextcloud.

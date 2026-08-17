# Privacy Suite

A self-hosted privacy protection stack that blocks ads at the DNS level, gives you a private search engine, manages your passwords, and secures your traffic with a personal VPN. Take back control of your data from your own VPS.

## What's Included

| App | Purpose | Default Port | Profile |
|---|---|---|---|
| AdGuard Home | DNS filtering / ad blocking | 53 (DNS), 80 (web) | Default |
| SearXNG | Private meta search engine | 8080 | Default |
| Vaultwarden | Password manager (Bitwarden-compatible) | 8222 | Default |
| WireGuard Easy | WireGuard VPN with web UI | 51820/udp (VPN), 51821 (web) | `vpn` |

## Quick Start

```bash
# Deploy default apps (DNS blocking, private search, password manager)
docker compose up -d

# Deploy with VPN enabled
docker compose --profile vpn up -d

# Deploy everything
docker compose --profile all --profile vpn up -d
```

## Data Directories

```
/data/adguardhome/     — AdGuard Home config and filtering rules
/data/searxng/         — SearXNG settings
/data/searxng-redis/   — SearXNG cache (Redis)
/data/vaultwarden/     — Vaultwarden database and attachments (SQLite)
/data/wireguard/       — WireGuard config and client profiles
```

## Reverse Proxy

To expose this suite via HTTPS with a domain, use [network-toolkit](https://github.com/0x10debug/network-toolkit):

```bash
mb net deploy website
# Set WEBSITE_DOMAIN=privacy.example.com
# Set APP_HOST=searxng
# Set APP_PORT=8080
```

Repeat for each app you want to expose (AdGuard Home, Vaultwarden, WireGuard Easy).
Note: AdGuard Home's DNS service runs on port 53 directly — it does not go through the reverse proxy.

## DNS Setup

AdGuard Home provides network-wide ad blocking via DNS. To use it:

1. After deploying, open the AdGuard Home web UI at `http://<VPS-IP>:80` and complete the initial setup wizard (set your admin password).
2. Change your router's DNS server (or individual client DNS) to your VPS IP address.
3. All DNS queries from those devices will now be filtered — ads and trackers are blocked before they load.

For granular control, configure per-client DNS on individual devices instead of the router.

## VPN Setup

WireGuard Easy provides a personal VPN with a web UI for managing clients. To use it:

1. Deploy with the `vpn` profile: `docker compose --profile vpn up -d`
2. Open the WireGuard Easy web UI at `http://<VPS-IP>:51821` and log in with the `ADGUARD_PASSWORD` you set.
3. Add a client (e.g. your phone or laptop) and download the configuration / scan the QR code.
4. Connect your device using the WireGuard app — all traffic is now routed through your VPS, with DNS filtered by AdGuard Home.

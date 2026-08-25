# Port Allocation

All suites share a global port allocation table to avoid conflicts when multiple suites are deployed on the same VPS.

## Port Ranges

| Range | Purpose | Used By |
|---|---|---|
| 53 | DNS | privacy-suite (AdGuard Home) |
| 80, 443 | Reverse proxy (HTTP/HTTPS) | minimal-start (Caddy), network-toolkit |
| 2222 | Git SSH | dev-environment (Gitea) |
| 3000 | Web app | dev-environment (Gitea), self-hosted-cloud (Outline*) |
| 3001 | Web app | personal-productivity (Linkwarden), minimal-start (Uptime Kuma) |
| 4533 | Music | home-media (Navidrome) |
| 5000 | Docker registry | dev-environment (Registry) |
| 51820 | VPN (UDP) | privacy-suite (WireGuard) |
| 51821 | VPN web UI | privacy-suite (WireGuard Easy) |
| 5230 | Notes | personal-productivity (Memos) |
| 5232 | Calendar/Contacts | self-hosted-cloud (Radicale) |
| 6767 | Subtitles | home-media (Bazarr) |
| 5678 | AI workflow | ai-automation (n8n) |
| 6333 | Vector DB | ai-automation (Qdrant) |
| 8000 | CI/CD | dev-environment (Woodpecker) |
| 8080 | Web app | privacy-suite (SearXNG), self-hosted-cloud (Nextcloud) |
| 8081 | File manager | self-hosted-cloud (Filebrowser) |
| 8096 | Video streaming | home-media (Jellyfin) |
| 8222 | Password manager | privacy-suite, personal-productivity (Vaultwarden) |
| 8443 | Code Server / OnlyOffice | dev-environment (Code Server), self-hosted-cloud (OnlyOffice) |
| 8800 | PDF tools | personal-productivity (Stirling-PDF) |
| 8150 | AI flow builder | ai-automation (Flowise) |
| 9091 | BT download | home-media (Transmission) |
| 13378 | Audiobooks | home-media (Audiobookshelf) |
| 2283 | Photos | home-media (Immich) |
| 11434 | Local LLM | ai-automation (Ollama) |
| 45876 | Monitoring agent | minimal-start (Beszel) |

## Conflict Resolution

If two suites use the same port (e.g., Vaultwarden in both privacy-suite and personal-productivity), you should:

1. **Deploy only one suite** that includes the conflicting app, OR
2. **Override the port** in `.env` — each suite's `.env.example` includes commented-out port override variables

## Adding New Ports

When creating a new suite, check this table first. If you need a port not listed here:
- Use the 8100-8199 range for new web apps
- Use the 8200-8299 range for databases/internal services
- Document the port in your suite's README and update this table

# Port Allocation

All suites share a global port allocation table to avoid conflicts when multiple suites are deployed on the same VPS. Every host port a suite publishes is listed here, grouped by range, with the suite, service, bind address, and whether it needs a reverse proxy.

## How to read this table

- **Port** — the host port published by the container (left side of `ports:` mapping).
- **Suite** — which suite publishes this port by default.
- **Service** — the compose service name inside that suite.
- **Bind** — `0.0.0.0` means the port is open on all interfaces; `127.0.0.1` means it is loopback-only; `internal` means no host port is published at all (container-to-container only).
- **Reverse proxy** — whether this service is meant to be exposed to the internet through Caddy / network-toolkit. `yes` = put it behind the proxy; `no` = direct access (e.g. VPN, DNS, BT) or internal-only.
- Every port below can be overridden in the suite's `.env` file (the variable name is shown in parentheses).

## Port Ranges

### 80 / 443 — Reverse proxy (HTTP / HTTPS)

| Port | Suite | Service | Bind | Reverse proxy | Env var |
|---|---|---|---|---|---|
| 80 | minimal-start | caddy | 0.0.0.0 | — (is the proxy) | — |
| 80 | privacy-suite | adguard-home | 0.0.0.0 | no (DNS dashboard) | `ADGUARD_PORT` |
| 443 | minimal-start | caddy | 0.0.0.0 | — (is the proxy) | — |

> Port 80/443 conflict: `minimal-start` (Caddy) and `privacy-suite` (AdGuard Home) both default to 80. Deploy only one of them as the front door, or override `ADGUARD_PORT` in privacy-suite's `.env`. The recommended setup is Caddy on 80/443 as the reverse proxy and AdGuard Home moved to a non-conflicting port.

### 3000-3999 — Web UI

| Port | Suite | Service | Bind | Reverse proxy | Env var |
|---|---|---|---|---|---|
| 2222 | dev-environment | gitea (SSH) | 0.0.0.0 | no (raw SSH) | `GITEA_SSH_PORT` |
| 2283 | home-media | immich | 0.0.0.0 | yes | `IMMICH_PORT` |
| 3000 | dev-environment | gitea (web) | 0.0.0.0 | yes | `GITEA_WEB_PORT` |
| 3000 | personal-productivity | outline | 0.0.0.0 | yes | `OUTLINE_PORT` |
| 3001 | personal-productivity | linkwarden | 0.0.0.0 | yes | `LINKWARDEN_PORT` |
| 3001 | minimal-start | uptime-kuma | 0.0.0.0 | yes | `UPTIME_KUMA_PORT` |
| 4533 | home-media | navidrome | 0.0.0.0 | yes | `NAVIDROME_PORT` |
| 5230 | personal-productivity | memos | 0.0.0.0 | yes | `MEMOS_PORT` |
| 5232 | self-hosted-cloud | radicale | 0.0.0.0 | yes | `RADICALE_PORT` |
| 6767 | home-media | bazarr | 0.0.0.0 | yes | `BAZARR_PORT` |

### 5000-5999 — API / registries

| Port | Suite | Service | Bind | Reverse proxy | Env var |
|---|---|---|---|---|---|
| 5000 | dev-environment | registry | 0.0.0.0 | yes (or private) | `REGISTRY_PORT` |
| 5678 | ai-automation | n8n | 0.0.0.0 | yes | `N8N_PORT` |
| 6333 | ai-automation | qdrant | 0.0.0.0 | no (internal API) | `QDRANT_PORT` |

### 8000-8999 — Services

| Port | Suite | Service | Bind | Reverse proxy | Env var |
|---|---|---|---|---|---|
| 8000 | dev-environment | woodpecker | 0.0.0.0 | yes | `WOODPECKER_PORT` |
| 8080 | privacy-suite | searxng | 0.0.0.0 | yes | `SEARXNG_PORT` |
| 8080 | self-hosted-cloud | nextcloud | 0.0.0.0 | yes | `NEXTCLOUD_PORT` |
| 8081 | self-hosted-cloud | filebrowser | 0.0.0.0 | yes | `FILEBROWSER_PORT` |
| 8096 | home-media | jellyfin | 0.0.0.0 | yes | `JELLYFIN_PORT` |
| 8150 | ai-automation | flowise | 0.0.0.0 | yes | `FLOWISE_PORT` |
| 8222 | privacy-suite | vaultwarden | 0.0.0.0 | yes | `VAULTWARDEN_PORT` |
| 8222 | personal-productivity | vaultwarden | 0.0.0.0 | yes | `VAULTWARDEN_PORT` |
| 8443 | dev-environment | code-server | 0.0.0.0 | yes | `CODE_SERVER_PORT` |
| 8443 | self-hosted-cloud | onlyoffice | 0.0.0.0 | yes | `ONLYOFFICE_PORT` |
| 8800 | personal-productivity | stirling-pdf | 0.0.0.0 | yes | `STIRLING_PDF_PORT` |

### 9000-9999 — Monitoring + management

| Port | Suite | Service | Bind | Reverse proxy | Env var |
|---|---|---|---|---|---|
| 9091 | home-media | transmission | 0.0.0.0 | no (BT web UI) | `TRANSMISSION_PORT` |
| 13378 | home-media | audiobookshelf | 0.0.0.0 | yes | `AUDIOBOOKSHELF_PORT` |
| 11434 | ai-automation | ollama | 0.0.0.0 | no (local LLM API) | `OLLAMA_PORT` |
| 45876 | minimal-start | beszel-agent | 0.0.0.0 | no (agent) | `BESZEL_AGENT_PORT` |

### Special — DNS / VPN / BT (non-HTTP)

| Port | Suite | Service | Bind | Reverse proxy | Env var |
|---|---|---|---|---|---|
| 53/udp | privacy-suite | adguard-home | 0.0.0.0 | no (DNS) | — |
| 53/tcp | privacy-suite | adguard-home | 0.0.0.0 | no (DNS) | — |
| 51413 | home-media | transmission (BT) | 0.0.0.0 | no (BT) | `TRANSMISSION_PORT` |
| 51413/udp | home-media | transmission (BT) | 0.0.0.0 | no (BT) | `TRANSMISSION_PORT` |
| 51820/udp | privacy-suite | wireguard | 0.0.0.0 | no (VPN) | — |
| 51821 | privacy-suite | wireguard-easy | 0.0.0.0 | yes (admin UI) | `WIREGUARD_PORT` |

### Internal only (no host port)

| Service | Suite | Network | Notes |
|---|---|---|---|
| socket-proxy | socket-proxy | `mb-socket-proxy` (internal) | Docker API gateway, container-to-container only, no host port |

## Conflict detection

A conflict happens when two suites publish the **same host port** on the same interface. The known shared ports are:

| Port | Suites that use it by default | Resolution |
|---|---|---|
| 80 | minimal-start (Caddy), privacy-suite (AdGuard Home) | Keep Caddy as the proxy; set `ADGUARD_PORT=8082` (or any free port) in privacy-suite's `.env` |
| 3000 | dev-environment (Gitea), personal-productivity (Outline) | Deploy only one, or override `GITEA_WEB_PORT` / `OUTLINE_PORT` |
| 3001 | personal-productivity (Linkwarden), minimal-start (Uptime Kuma) | Deploy only one, or override `LINKWARDEN_PORT` / `UPTIME_KUMA_PORT` |
| 8080 | privacy-suite (SearXNG), self-hosted-cloud (Nextcloud) | Deploy only one, or override `SEARXNG_PORT` / `NEXTCLOUD_PORT` |
| 8222 | privacy-suite (Vaultwarden), personal-productivity (Vaultwarden) | Deploy Vaultwarden from only one suite |
| 8443 | dev-environment (Code Server), self-hosted-cloud (OnlyOffice) | Deploy only one, or override `CODE_SERVER_PORT` / `ONLYOFFICE_PORT` |

To check for live conflicts on a running VPS:

```bash
# Quick check — what is listening on a port
ss -tulpn | grep ':8080'

# Or use the CLI
mb recipes port-check            # scan all suites' default ports against the host
mb recipes port-check 8080       # check a single port
```

`mb recipes port-check` reads every suite's `compose.yml`, resolves the default port from the `${VAR:-default}` mapping, and reports whether that port is already in use on the host — so you catch conflicts **before** deploying.

## Adding new ports

When creating a new suite, check this table first. If you need a port not listed here:

- Use the **8100-8199** range for new web apps
- Use the **8200-8299** range for databases / internal services
- Use the **9000-9999** range for monitoring and management UIs
- Document the port in your suite's README and update this table
- Run `mb recipes port-check` to confirm the port is free on the target host

## Integration with network-toolkit reverse proxy

[network-toolkit](https://github.com/0x10debug/network-toolkit) provides the reverse proxy templates (Caddy) that sit in front of these suites. The integration works like this:

1. **Shared network** — every suite joins the `mb-proxy` Docker network. The Caddy container from network-toolkit (or the `minimal-start` suite) also joins `mb-proxy`.
2. **No host port needed for proxied apps** — once an app is on `mb-proxy`, Caddy can reach it by container name. You do not need to publish the app's port to the host at all if it is only accessed through the proxy. The ports in this table are published so you can reach apps directly during setup or for non-HTTP services.
3. **Add a route** — `mb net proxy add app.example.com app-container:8080` tells Caddy to route your domain to the container. The `:8080` is the **container's internal port** (the right side of the `ports:` mapping), not the host port.
4. **Automatic SSL** — Caddy obtains and renews Let's Encrypt certificates for every domain you add.

See [Reverse Proxy Setup](reverse-proxy-setup.md) for the full guide.

## Generating the registry

The port data above is also available as a machine-readable registry built from the actual `compose.yml` files:

```bash
mb recipes registry --format json     # full registry: suites, services, ports, env vars
mb recipes registry --format table    # human-readable
mb recipes registry --output registry.json
```

See [Template Registry](#) (generated by `scripts/build-registry.sh`) for automation and documentation generation use cases.

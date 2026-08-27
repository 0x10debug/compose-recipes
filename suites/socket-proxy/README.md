# Socket-Proxy Suite

A hardened Docker API gateway that lets your other containers talk to the Docker API **without** handing them the raw `/var/run/docker.sock` — which is equivalent to root on the host. The proxy re-exposes a filtered subset of the Docker API on `:2375` inside an internal network, with every endpoint denied by default.

## Why You Need This

> **The Docker socket is root access.** Any container that can read `/var/run/docker.sock` can start a privileged container, mount the host filesystem, read every secret, and pivot to full host compromise. Never bind-mount the raw socket into an untrusted or internet-facing container.

Many self-hosted apps want Docker visibility — monitoring agents that scrape container stats, reverse proxies that discover labeled containers, backup tools that query running services, CI runners that spin up build environments. The naive approach is to mount `/var/run/docker.sock` directly into those containers. That gives them **unrestricted** root-level access to your host.

A socket-proxy sits between those containers and the real socket. It terminates the Docker API on `:2375` and forwards only **allowlisted** endpoints to the real socket. Anything not explicitly enabled returns `403`. Combined with an **internal** Docker network (no published ports), only containers you explicitly attach to that network can reach the filtered API.

## What's Included

| Component | Purpose | Port | Profile |
|---|---|---|---|
| socket-proxy | Filtered Docker API gateway (tecnativa/docker-socket-proxy:0.1.5) | 2375 (internal only) | Default |
| docker-api-demo | One-shot client that verifies filtering works | — | `demo` |

No ports are published to the host. The proxy is reachable only from containers on the `mb-socket-proxy` internal network.

## Security Model

1. **Docker socket = root.** Mounting `/var/run/docker.sock` into a container gives it unrestricted control of the Docker daemon and, through it, the host.
2. **Proxy, not passthrough.** `docker-socket-proxy` terminates the Docker API on `:2375` and forwards only allowlisted endpoints to the real socket. Anything not explicitly enabled returns `403`.
3. **Default-deny.** Every endpoint switch defaults to `0` in `.env.example`. `CONTAINERS=1` allows listing/inspecting containers (read-only). `POST=0` blocks create/kill/exec/restart even when `CONTAINERS=1` is set — so a monitoring agent can observe without being able to mutate.
4. **Internal network.** The proxy publishes no ports to the host. It lives on an `internal: true` Docker network, so only containers attached to that same network can dial `http://socket-proxy:2375`. The public internet and other Docker networks cannot reach it.
5. **Read-only socket mount.** The host socket is mounted `:ro` so the proxy itself cannot be tricked into writing to it; filtering happens at the HTTP layer.

## Quick Start

```bash
# 1. Configure the allowlist — start with everything denied
cp .env.example .env
#   edit .env: enable only the endpoints your consumers need
#   for most read-only use cases: CONTAINERS=1, everything else 0

# 2. Launch the proxy
docker compose up -d

# 3. Verify filtering works (optional, one-shot demo client)
docker compose --profile demo up docker-api-demo
#   expect: GET /containers/json → 200 (if CONTAINERS=1)
#           POST /containers/create → 403 (if POST=0)
#           GET /info → 403 (if INFO=0)

# 4. Point other containers at the filtered API
#    set DOCKER_HOST=tcp://socket-proxy:2375
#    attach them to the mb-socket-proxy network
```

## Endpoint Reference

### Read-only endpoints (GET/HEAD)

| Switch | Endpoint group | Default | Risk level | Notes |
|---|---|---|---|---|
| `CONTAINERS` | `/containers/*` | `0` | Low (read) | List/inspect containers. Create/kill needs `POST=1` |
| `IMAGES` | `/images/*` | `0` | Low (read) | List/inspect images. Pull/build needs `POST=1` |
| `INFO` | `/info` | `0` | Low | Daemon info (version, storage driver, labels) |
| `NETWORKS` | `/networks/*` | `0` | Low (read) | List/inspect Docker networks |
| `VOLUMES` | `/volumes/*` | `0` | Low (read) | List/inspect volumes |
| `SYSTEM` | `/system/*` | `0` | Low (read) | `df`, `events`, `version` |
| `EVENTS` | `/events` | `0` | Low (read) | Stream daemon events (useful for monitoring) |
| `NODES` | `/nodes/*` | `0` | Medium | Swarm node info |
| `SERVICES` | `/services/*` | `0` | Medium | Swarm service info |
| `TASKS` | `/tasks/*` | `0` | Medium | Swarm task info |
| `PLUGINS` | `/plugins/*` | `0` | Medium | Plugin management |
| `SESSION` | `/session` | `0` | Medium | Interactive attach sessions |
| `SWARM` | `/swarm/*` | `0` | Medium | Swarm management |
| `DISTRIBUTION` | `/distribution/*` | `0` | Low | Image distribution info |

### Write endpoints (POST/PUT/DELETE) — dangerous

| Switch | Endpoint group | Default | Risk level | Notes |
|---|---|---|---|---|
| `POST` | write verbs | `0` | **High** | Master switch for POST/PUT/DELETE across all endpoints |
| `EXEC` | `/exec/*` | `0` | **Critical** | Run arbitrary commands inside containers — near-root |
| `BUILD` | `/build` | `0` | **High** | Build images (write) |
| `COMMIT` | `/commit` | `0` | **High** | Commit container state to image (write) |
| `CONFIGS` | `/configs/*` | `0` | **High** | Swarm configs (write) |
| `SECRETS` | `/secrets/*` | `0` | **Critical** | Swarm secrets (write) — can read/modify cluster secrets |

**Principle**: start with everything `0`, enable the minimum a consumer needs, and keep `POST=0` unless that consumer must change Docker state. `EXEC=1` + `POST=1` is equivalent to giving the consumer a root shell on every container — never enable it for untrusted or internet-facing services.

## Integration With Other Suites

The socket-proxy is designed to be shared across all your suites. Deploy it once, then attach consumers to the `mb-socket-proxy` network and point them at `http://socket-proxy:2375`.

### ai-automation — n8n managing Docker containers

n8n can orchestrate Docker containers (start/stop workflows, dynamic service scaling) through the filtered proxy instead of the raw socket. For read-only container management (list, inspect), enable `CONTAINERS=1`. For start/stop operations, also enable `POST=1`.

```yaml
# In suites/ai-automation/compose.yml, add to the n8n service:
services:
  n8n:
    environment:
      # Point n8n's Docker node at the filtered proxy
      - DOCKER_HOST=tcp://socket-proxy:2375
    networks:
      - mb-proxy
      - mb-socket-proxy

networks:
  mb-socket-proxy:
    external: true
```

Recommended `.env` for this integration: `CONTAINERS=1`, `POST=0` (read-only orchestration). Enable `POST=1` only if n8n must start/stop containers.

### monitor-stack — monitoring container status

A monitoring agent that scrapes container stats and health needs read-only Docker visibility. Enable `CONTAINERS=1` and `INFO=1` (or `SYSTEM=1` for `/system/df`).

```yaml
# In monitor-stack compose, add to the monitoring agent:
services:
  monitor-agent:
    environment:
      - DOCKER_HOST=tcp://socket-proxy:2375
    networks:
      - mb-proxy
      - mb-socket-proxy

networks:
  mb-socket-proxy:
    external: true
```

Recommended `.env` for this integration: `CONTAINERS=1`, `INFO=1`, `POST=0`. The agent can observe container states and daemon info but cannot mutate anything.

### backup-kit — querying container list during backups

A backup script that needs to know which containers are running (to coordinate pre/post backup hooks) can query the proxy instead of the raw socket. Enable `CONTAINERS=1` only.

```yaml
# In a backup-sidecar container:
services:
  backup-sidecar:
    environment:
      - DOCKER_HOST=tcp://socket-proxy:2375
    networks:
      - mb-proxy
      - mb-socket-proxy

networks:
  mb-socket-proxy:
    external: true
```

Recommended `.env` for this integration: `CONTAINERS=1`, `POST=0`. The backup tool can list containers and inspect their state but cannot create, kill, or exec into them.

See [`examples/docker-api-query.sh`](examples/docker-api-query.sh) for a ready-to-use script that queries the Docker API through the proxy, and [`examples/integrate-with-monitoring.yml`](examples/integrate-with-monitoring.yml) for a complete monitoring integration compose snippet.

## Security Best Practices

1. **Start with default-deny.** Copy `.env.example` (all `0`) and enable endpoints one at a time. Test that your consumer works, then stop — don't enable more "just in case."
2. **Keep `POST=0` for read-only consumers.** Monitoring agents, reverse proxies, and backup tools should never need to mutate Docker state. `POST=0` ensures that even if the consumer is compromised, it cannot create, kill, or exec into containers.
3. **Never enable `EXEC=1` + `POST=1` for internet-facing services.** This combination lets the consumer run arbitrary commands inside any container — equivalent to root on every container and, through volume mounts, the host.
4. **Don't publish ports.** The proxy has no `ports:` mapping by design. Adding one would expose the filtered API to the host network and potentially the internet. The proxy is reachable only from containers on `mb-socket-proxy`.
5. **Use separate networks for egress.** The `mb-socket-proxy` network is `internal: true` — containers on it cannot reach the internet. If a consumer needs both Docker API access and internet egress, attach it to `mb-socket-proxy` AND a second non-internal network (e.g. `mb-proxy`).
6. **Audit your allowlist.** Review `.env` periodically. Every endpoint you enable expands the attack surface. Remove endpoints that consumers no longer need.
7. **Pin the image version.** This suite uses `tecnativa/docker-socket-proxy:0.1.5` (pinned). Bump deliberately and re-audit the changelog — newer versions may add or rename endpoint switches.
8. **Combine with least-privilege container settings.** Even with the proxy, run consumers with `read_only: true`, minimal capabilities, and non-root users where possible. Defense in depth.

## Relationship With network-toolkit

This suite is the **user-facing deployment** counterpart to the [network-toolkit socket-proxy template](https://github.com/0x10debug/network-toolkit/tree/main/templates/socket-proxy):

| Aspect | network-toolkit template | this suite |
|---|---|---|
| Audience | Network layer operators | End users deploying app suites |
| Scope | Proxy + network config only | Full deployment with docs, examples, integration guides |
| Network | External (manual `docker network create --internal`) | Auto-created (`internal: true` in compose) |
| Demo client | None | `docker-api-demo` profile for verification |
| Integration docs | Traefik + monitoring examples | ai-automation, monitor-stack, backup-kit integration |
| Security docs | Endpoint reference | Endpoint reference + risk levels + best practices |

If you already deployed the network-toolkit template and created `mb-socket-proxy` manually, set `MB_SOCKET_PROXY_NETWORK` in `.env` to match and change the network in this suite's `compose.yml` to `external: true` to avoid creating a second network.

## Data Directories

This suite stores no persistent data — the proxy is stateless. No `/data/` paths are used.

## Reverse Proxy

This suite does **not** join the `mb-proxy` network and does not need a reverse proxy. The socket-proxy is an internal infrastructure service, not a user-facing web app. Do not expose it through Caddy or Traefik.

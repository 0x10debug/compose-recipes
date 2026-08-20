# Contributing Suites

Want to add a new scenario suite? This guide explains the structure and conventions.

## Suite Structure

Every suite is a self-contained directory under `suites/`:

```
suites/my-suite/
├── compose.yml       — Docker Compose file with profiles
├── .env.example      — Environment variable template
├── README.md         — English documentation
└── README.zh.md      — Chinese documentation
```

## Conventions

### 1. Docker Network

All services must join the `mb-proxy` external network:

```yaml
networks:
  mb-proxy:
    external: true
    name: ${MB_PROXY_NETWORK:-mb-proxy}
```

This allows the reverse proxy (from network-toolkit or minimal-start) to route traffic to your services.

### 2. Data Volumes

Use `/data/<service-name>/` for all persistent data:

```yaml
volumes:
  - /data/my-app/config:/config
  - /data/my-app/data:/data
```

Check [port-allocation.md](./port-allocation.md) for port assignments. If you need a new port, use the 8100-8199 range and update the table.

### 3. Profiles

Use Docker Compose profiles to separate core and optional apps:

```yaml
# Core app — starts by default
profiles: ["all", ""]

# Optional app — starts with --profile <name>
profiles: ["extras"]
```

Users deploy with:

```bash
docker compose up -d                          # core only
docker compose --profile extras up -d         # core + extras
```

### 4. Environment Variables

- All configurable values go in `.env.example`
- Secrets (passwords, tokens) have empty values — they're auto-generated during `mb recipes deploy`
- Domain variables end with `_DOMAIN`
- Port variables end with `_PORT` and have commented-out defaults
- Use `${VAR:-default}` syntax in compose.yml for optional values

### 5. Restart Policy

All services use `restart: unless-stopped`.

### 6. Pinned Image Tags

**Never use `:latest`.** Every `image:` must pin a specific version tag (e.g.
`caddy:2.8.4`, `postgres:16-alpine`). This is a supply-chain security requirement:
`:latest` tags are mutable and can pull unexpected/breaking changes or
compromised images. When upgrading, bump the tag deliberately and test.

### 7. Healthchecks

Every service must define a `healthcheck:` block so `depends_on: condition:
service_healthy` works and `mb recipes health <suite>` can report status.
Common patterns:

```yaml
# Web service (HTTP) — alpine-based images have busybox wget
healthcheck:
  test: ["CMD-SHELL", "wget -q --spider http://localhost:8080/ || exit 1"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 30s

# Web service (HTTPS, self-signed) — use curl -k
healthcheck:
  test: ["CMD-SHELL", "curl -skf https://localhost:8443/ || exit 1"]

# PostgreSQL
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U my-app -d my-app"]
  interval: 10s
  timeout: 5s
  retries: 5

# Redis
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 10s
  timeout: 5s
  retries: 5
```

Use `start_period` generously (30–60s) for apps that need init time. Reusable
host-side helpers live in `lib/healthcheck.sh` (`mb_health_wait`,
`mb_health_wait_suite`, `mb_health_tcp`, `mb_health_http`).

### 8. Database Sidecars

When a service needs PostgreSQL:

```yaml
my-app-postgres:
  image: postgres:16-alpine
  container_name: my-app-postgres
  restart: unless-stopped
  profiles: ["all", ""]
  networks: [mb-proxy]
  volumes:
    - /data/my-app/postgres:/var/lib/postgresql/data
  environment:
    - POSTGRES_USER=my-app
    - POSTGRES_PASSWORD=${MY_APP_DB_PASSWORD}
    - POSTGRES_DB=my-app
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U my-app"]
    interval: 10s
    timeout: 5s
    retries: 5
```

For Redis, use `redis:7-alpine`.

### 7. Bilingual README

Every suite must have both `README.md` (English) and `README.zh.md` (Chinese). Both must include:

- **What's Included** table (app, purpose, default port, profile)
- **Quick Start** section with `docker compose` commands
- **Data Directories** section listing all `/data/` paths
- **Reverse Proxy** section linking to network-toolkit

## Submission Checklist

- [ ] `compose.yml` validates with `docker compose config`
- [ ] All services join `mb-proxy` network
- [ ] No port conflicts with existing suites (check port-allocation.md)
- [ ] All images pinned to specific version tags (no `:latest`)
- [ ] Every service has a `healthcheck:` block
- [ ] `.env.example` includes all required variables
- [ ] `README.md` and `README.zh.md` both present and complete
- [ ] No hardcoded secrets — all secrets use `${}` env var references
- [ ] Tested with `docker compose up -d` on a clean VPS
- [ ] No references to internal project names or other private repos

## Template

Use `templates/suite-template/` as a starting point. Copy it to `suites/your-suite/` and customize.

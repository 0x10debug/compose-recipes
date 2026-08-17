# Suite Template

Use this template to create a new scenario-based suite — a collection of apps that work together for a specific use case.

## How to Use

1. Copy this directory:
```bash
cp -r templates/suite-template suites/my-suite
```

2. Edit `compose.yml` — replace all `{{APP_*}}` and `{{OPTIONAL_*}}` placeholders.

3. Edit `.env.example` — add required environment variables for your apps.

4. Write `README.md` and `README.zh.md` — describe the suite, what's included, and how to deploy.

5. Deploy:
```bash
cd suites/my-suite
cp .env.example .env
# Edit .env with your values
docker compose up -d                    # core apps only
docker compose --profile <optional> up -d  # with optional apps
```

## Structure

```
my-suite/
├── compose.yml       — Docker Compose with profiles
├── .env.example      — Environment variable template
├── README.md         — English documentation
└── README.zh.md      — Chinese documentation
```

## Conventions

- **Profiles**: Core apps use `profiles: ["all", ""]` (start by default). Optional apps use `profiles: ["<name>"]`.
- **Network**: All services join `mb-proxy` external network for reverse proxy integration.
- **Data**: All persistent data goes in `/data/<app-name>/`.
- **Restart**: All services use `restart: unless-stopped`.
- **Database sidecars**: Use `postgres:16-alpine` with healthcheck. Name them `<app>-postgres`.
- **Bilingual**: Every suite has both English and Chinese README files.

## Contributing

Submit your suite as a PR. See [contributing-suites.md](../../docs/contributing-suites.md) for guidelines.

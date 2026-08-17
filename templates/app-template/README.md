# Single App Template

Use this template to add a single application to your self-hosted setup.

## How to Use

1. Copy this directory:
```bash
cp -r templates/app-template suites/my-app
```

2. Edit `compose.yml` — replace all `{{APP_*}}` placeholders with your app's values.

3. Edit `.env.example` — set the default port and any required environment variables.

4. Deploy:
```bash
cd suites/my-app
cp .env.example .env
# Edit .env with your values
docker compose up -d
```

## Placeholders

| Placeholder | Meaning | Example |
|---|---|---|
| `{{APP_NAME}}` | Container/service name | `my-app` |
| `{{APP_IMAGE}}` | Docker image | `nginx:latest` |
| `{{APP_PORT}}` | Host port | `8080` |
| `{{APP_CONTAINER_PORT}}` | Container port | `80` |
| `{{APP_NAME_UPPER}}` | Name in uppercase for env vars | `MY_APP` |

## Conventions

- Data goes in `/data/<app-name>/`
- Join the `mb-proxy` network for reverse proxy integration
- Use `profiles: ["all", ""]` so the app starts by default
- Use `restart: unless-stopped`

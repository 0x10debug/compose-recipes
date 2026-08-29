# Backup Hooks

Database-aware backup hooks for compose suites. The hooks let a backup tool
(like [backup-kit](https://github.com/0x10debug/backup-kit)) dump a database
**before** a backup run and clean up the temp dump **afterwards**, so the
backup captures a consistent point-in-time snapshot instead of live files that
may be mid-write.

## How It Works

The backup flow is a four-step pipeline:

```
1. pre-backup   →  dump DB to /var/tmp/compose-backup-hooks/<service>-<ts>/
2. backup       →  Restic (or any tool) snapshots /data + the dump dir
3. post-backup  →  remove the temp dump
4. (optional)   →  verify dump integrity before removal
```

The hooks live in [`lib/backup-hooks.sh`](../lib/backup-hooks.sh) and are
exposed two ways:

- **`mb` CLI** — `mb recipes backup-hooks <action> [options]`
- **Standalone script** — `./scripts/backup-hook-exec.sh <action> [options]`

Both accept the same actions: `pre`, `post`, `discover`.

## Quick Start

```bash
# 1. See which services in a suite can be backed up
./scripts/backup-hook-exec.sh discover --config suites/ai-automation/compose.yml

# 2. Dump one service before a backup
./scripts/backup-hook-exec.sh pre --service postgres --config compose.yml
# → prints: /var/tmp/compose-backup-hooks/postgres-20260829T120000Z/postgres.sql

# 3. Run your backup (e.g. restic) — it picks up /data + the dump path

# 4. Clean up
./scripts/backup-hook-exec.sh post --service postgres

# Batch: dump every database in a suite, then clean up
./scripts/backup-hook-exec.sh pre  --all --config compose.yml
./scripts/backup-hook-exec.sh post --all --config compose.yml

# Preview without touching anything
./scripts/backup-hook-exec.sh pre --service redis --config compose.yml --dry-run
```

## Integration with backup-kit

[backup-kit](https://github.com/0x10debug/backup-kit) calls the hooks around its
Restic run. A typical wrapper script:

```bash
#!/usr/bin/env bash
set -euo pipefail
COMPOSE=/opt/mb-recipes/ai-automation/compose.yml
EXEC=/opt/mb-recipes/scripts/backup-hook-exec.sh

# 1. Pre-backup: dump every database
DUMPS=$("$EXEC" pre --all --config "$COMPOSE")

# 2. Run Restic over /data + the dump dir
restic backup /data /var/tmp/compose-backup-hooks

# 3. Post-backup: clean up
"$EXEC" post --all --config "$COMPOSE"
```

The dump directory (`/var/tmp/compose-backup-hooks` by default) is kept
**outside** `/data` so Restic doesn't snapshot the same bytes twice under two
paths. Override it with `--output DIR` or `MB_BACKUP_OUTPUT_DIR`.

## Supported Databases & Dump Strategies

| Engine | Detection | Dump command | Output |
|---|---|---|---|
| PostgreSQL | image/name `postgres` | `pg_dump -U <user> -d <db>` | `<service>.sql` |
| MySQL | image/name `mysql` | `mysqldump -u <user> [--password] <db\|--all-databases>` | `<service>.sql` |
| MariaDB | image/name `mariadb` | `mysqldump` (same as MySQL) | `<service>.sql` |
| Redis | image/name `redis` | `redis-cli BGSAVE` + wait, then `docker cp dump.rdb` | `<service>.rdb` |
| MongoDB | image/name `mongo` | `mongodump --archive` | `<service>-mongo.archive` |
| SQLite | image/name `sqlite` or label `backup.hook.path` | `docker cp` of the `.db` file | `<service>.db` |

Engine detection order (first match wins):

1. Docker label `backup.hook.type=<engine>` on the running container
2. Image name contains the engine keyword
3. Compose service name contains the engine keyword

## Docker Label Conventions

Tag a service in `compose.yml` to opt it into hooks and override detection:

```yaml
services:
  postgres:
    image: postgres:16
    labels:
      backup.hook: "pre-post"          # opt into pre + post hooks
      backup.hook.type: "postgres"     # engine (optional, overrides detection)
      backup.hook.db: "appdb"          # database name (postgres/mysql/mongo)
      backup.hook.user: "appuser"      # override DB user
      backup.hook.path: "/data/pg/app.db"  # sqlite file path / redis rdb path
```

| Label | Purpose | Applies to |
|---|---|---|
| `backup.hook` | `pre-post` to enable hooks | all |
| `backup.hook.type` | Force engine detection | all |
| `backup.hook.db` | Database name | postgres, mysql, mongo |
| `backup.hook.user` | DB user override | postgres, mysql |
| `backup.hook.path` | File path inside container | sqlite, redis |

## Cron Integration

Run a nightly backup with hooks via cron. Create
`/etc/cron.d/compose-backup`:

```cron
# Nightly 3am: dump → restic → cleanup, for the ai-automation suite
0 3 * * * root /opt/mb-recipes/scripts/backup-hook-exec.sh pre --all --config /opt/mb-recipes/ai-automation/compose.yml && \
    restic -r /backup/restic backup /data /var/tmp/compose-backup-hooks && \
    /opt/mb-recipes/scripts/backup-hook-exec.sh post --all --config /opt/mb-recipes/ai-automation/compose.yml >> /var/log/compose-backup-hooks/cron.log 2>&1
```

Or via `mb`:

```cron
0 3 * * * root /opt/mb-recipes/mb recipes backup-hooks pre --all --config /opt/mb-recipes/ai-automation/compose.yml && \
    restic -r /backup/restic backup /data /var/tmp/compose-backup-hooks && \
    /opt/mb-recipes/mb recipes backup-hooks post --all --config /opt/mb-recipes/ai-automation/compose.yml
```

Logs are written to `/var/log/compose-backup-hooks/backup-hooks.log`.

## Options & Environment

| Flag | Env var | Default | Purpose |
|---|---|---|---|
| `--config FILE` | `MB_BACKUP_COMPOSE_FILE` | `compose.yml` | compose file path |
| `--output DIR` | `MB_BACKUP_OUTPUT_DIR` | `/var/tmp/compose-backup-hooks` | dump output dir |
| `--dry-run` | `MB_BACKUP_DRY_RUN=1` | off | preview without executing |
| `--verify` | `MB_BACKUP_VERIFY=1` | off | verify dump before post cleanup |
| — | `MB_BACKUP_LOG_DIR` | `/var/log/compose-backup-hooks` | log directory |

## Troubleshooting

### `Unknown database engine for service: X`
The service's image and name don't match any known engine. Either rename the
service, use an image with a recognizable name, or add the `backup.hook.type`
label to the container.

### `pg_dump failed` / `mysqldump failed`
- The container may not be running — check with `docker ps`.
- The DB user/password may be wrong. The hooks read `POSTGRES_USER` /
  `POSTGRES_DB` / `MYSQL_USER` / `MYSQL_PASSWORD` from the environment, or the
  `backup.hook.user` / `backup.hook.db` labels.
- Run with `--dry-run` to see the exact command being executed.

### `redis docker cp failed`
The hook looks for `dump.rdb` at `/data/dump.rdb` by default. If your Redis
uses a different data dir, set the `backup.hook.path` label to the RDB path.

### Dump file is empty
- The database may be empty (legitimate).
- The dump command failed silently — check the hook log at
  `/var/log/compose-backup-hooks/backup-hooks.log`.
- Use `--verify` to fail post-backup cleanup when a dump looks invalid.

### `No dump found for X` on post-backup
The pre-backup either didn't run or used a different `--output` dir. The
post-backup looks up the last dump path from
`<output-dir>/<service>.last`. Make sure pre and post use the same
`--output` / `MB_BACKUP_OUTPUT_DIR`.

### Container name not resolved
The hooks try `container_name:` from compose first, then fall back to
`<project>-<service>-1`. If you use a custom project name or replica suffix,
set `container_name:` explicitly in your compose file.

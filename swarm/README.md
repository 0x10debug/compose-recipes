# Docker Swarm Stack Templates

Production-ready Docker Swarm stack templates for deploying compose-recipes suites across a multi-node Swarm cluster. These templates add Swarm-specific deploy configuration (replicas, update/rollback, placement constraints, resource limits) on top of the single-node compose pattern.

## What's in this directory

| File | Purpose |
|---|---|
| `stack-base.yml` | Base template — copy and adapt for your own stack. Shows all deploy knobs. |
| `stack-example.yml` | Complete example — Caddy (reverse proxy) + web app + PostgreSQL + Uptime Kuma. |
| `deploy-stack.sh` | Deployment wrapper around `docker stack deploy` with dry-run support. |

## Swarm vs single-node Compose — what changes

| Aspect | Single-node Compose | Docker Swarm |
|---|---|---|
| Orchestration | `docker compose up -d` | `docker stack deploy -c file.yml NAME` |
| Scaling | One container per service | `deploy.replicas: N` — Swarm spreads tasks across nodes |
| Networking | `mb-proxy` bridge network (local) | `mb-proxy-overlay` overlay network (spans all nodes) |
| Updates | `docker compose up -d` (recreates) | `deploy.update_config` — rolling updates with parallelism, delay, auto-rollback |
| Rollback | Manual `docker compose up -d` with old image | `deploy.rollback_config` — automatic on update failure |
| Placement | Runs where you run compose | `deploy.placement.constraints` — pin to nodes by role or label |
| Volumes | Local to the host | Local to the node where the task lands (pin stateful services!) |
| Restart policy | `restart: unless-stopped` | `deploy.restart_policy` — condition, max attempts, window |
| Resource limits | `deploy.resources` (v3 only) | `deploy.resources` — limits + reservations, enforced by Swarm |

## Prerequisites

1. **Docker installed** on every node (run [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) on each)
2. **Swarm initialized** on the manager:
   ```bash
   docker swarm init --advertise-addr <MANAGER_IP>
   ```
3. **Workers joined** (run on each worker node):
   ```bash
   docker swarm join --token <TOKEN> <MANAGER_IP>:2377
   ```
4. **Overlay network created**:
   ```bash
   docker network create -d overlay mb-proxy-overlay
   ```

## Deploying a stack

### Using the deploy script

```bash
# Dry-run — show what would be deployed
./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --dry-run

# Deploy
./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml

# With env file
./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --env-file .env
```

### Using docker directly

```bash
docker stack deploy -c swarm/stack-example.yml mystack
docker stack services mystack
docker stack ps mystack
```

## Node labels

Swarm placement constraints use node labels to control where tasks run. Common patterns:

```bash
# Label nodes by environment
docker node update --label-add env=prod node-1
docker node update --label-add env=staging node-2

# Label a node for databases
docker node update --label-add db=true node-1

# Label nodes by hardware
docker node update --label-add ssd=true node-1
docker node update --label-add gpu=true node-2
```

Then use them in your stack file:

```yaml
deploy:
  placement:
    constraints:
      - "node.labels.env==prod"
      - "node.labels.db==true"
```

## Network configuration

Swarm uses **overlay networks** that span all nodes. The reverse proxy (Caddy) and all application services must join the same overlay network so the proxy can route by container name.

```
Internet → Manager:443 → Caddy (on mb-proxy-overlay) → webapp (on worker node, same overlay)
```

- **Create the network once** before deploying: `docker network create -d overlay mb-proxy-overlay`
- **All services reference it** in their `networks:` section
- **The network is external** — set `external: true` in the stack file if you created it manually, or let Swarm create it from the stack file

## Migrating from single-node Compose to Swarm

1. **Initialize Swarm** on your VPS:
   ```bash
   docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
   ```

2. **Create the overlay network**:
   ```bash
   docker network create -d overlay mb-proxy-overlay
   ```

3. **Convert your compose file** to a stack file:
   - Change `networks: mb-proxy` to `networks: mb-proxy-overlay` with `driver: overlay`
   - Add `deploy:` sections to each service (replicas, update_config, placement)
   - Remove `container_name:` (Swarm assigns names as `<stack>_<service>`)
   - Remove `restart:` (use `deploy.restart_policy` instead)
   - Pin stateful services (databases) to a single node with placement constraints

4. **Deploy the stack**:
   ```bash
   ./swarm/deploy-stack.sh --stack-name myapps --config-file my-stack.yml
   ```

5. **Verify**:
   ```bash
   docker stack services myapps
   docker stack ps myapps
   ```

6. **Tear down the old single-node deployment** (after confirming the stack works):
   ```bash
   docker compose -f /opt/mb-recipes/home-media/compose.yml down
   ```

## Stateful services — important

Swarm volumes are **local to the node** where the task runs. If a database task moves to a different node, its data stays behind. To handle this:

- **Pin the service** with `placement.constraints` to a specific node
- **Use a shared storage driver** (NFS, GlusterFS, or a cloud volume plugin) for data that must follow the task
- **Set `replicas: 1`** for all databases — they cannot be scaled horizontally

## Updating a stack

```bash
# Update with the same file (rolling update per update_config)
./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml

# Force a rollback if an update went wrong
docker service rollback mystack_webapp

# Update a single service's image
docker service update --image myapp:v2 mystack_webapp
```

## Removing a stack

```bash
docker stack rm mystack
# The overlay network persists — remove it manually if no longer needed:
docker network rm mb-proxy-overlay
```

## Related

- [Port Allocation](../docs/port-allocation.md) — global port planning
- [Reverse Proxy Setup](../docs/reverse-proxy-setup.md) — Caddy configuration
- [network-toolkit](https://github.com/0x10debug/network-toolkit) — reverse proxy templates
- [Docker Swarm docs](https://docs.docker.com/engine/swarm/) — official reference

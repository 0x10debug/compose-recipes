# Socket-Proxy 套件

一个加固的 Docker API 网关，让你的其他容器**无需**直接挂载 `/var/run/docker.sock`（等同于主机 root 权限）就能与 Docker API 通信。代理在内部网络的 `:2375` 端口上重新暴露经过过滤的 Docker API 子集，所有端点默认拒绝。

## 为什么需要这个

> **Docker socket 就是 root 权限。** 任何能读取 `/var/run/docker.sock` 的容器都可以启动特权容器、挂载主机文件系统、读取所有密钥，并提权到完全控制主机。永远不要将原始 socket 挂载到不受信任或面向互联网的容器中。

很多自托管应用需要 Docker 可见性——监控代理抓取容器状态、反向代理发现带标签的容器、备份工具查询运行中的服务、CI 运行器启动构建环境。最简单的做法是把 `/var/run/docker.sock` 直接挂载到这些容器里。但这给了它们**不受限制的** root 级别主机访问权限。

socket-proxy 位于这些容器和真实 socket 之间。它在 `:2375` 上终止 Docker API，只转发**白名单**内的端点到真实 socket。未明确启用的端点一律返回 `403`。配合**内部** Docker 网络（不发布端口），只有你明确接入该网络的容器才能访问过滤后的 API。

## 包含什么

| 组件 | 用途 | 端口 | Profile |
|---|---|---|---|
| socket-proxy | 过滤的 Docker API 网关（tecnativa/docker-socket-proxy:0.1.5） | 2375（仅内部） | 默认 |
| docker-api-demo | 一次性客户端，验证过滤是否生效 | — | `demo` |

不向主机发布任何端口。代理只能从 `mb-socket-proxy` 内部网络上的容器访问。

## 安全模型

1. **Docker socket = root。** 将 `/var/run/docker.sock` 挂载到容器中，就给了它对 Docker 守护进程的不受限制控制权，进而控制主机。
2. **代理，不是直通。** `docker-socket-proxy` 在 `:2375` 上终止 Docker API，只将白名单端点转发到真实 socket。未明确启用的请求返回 `403`。
3. **默认拒绝。** `.env.example` 中每个端点开关默认为 `0`。`CONTAINERS=1` 允许列出/检查容器（只读）。`POST=0` 即使在 `CONTAINERS=1` 时也阻止创建/杀死/exec/重启——所以监控代理可以观察但不能修改。
4. **内部网络。** 代理不向主机发布端口。它运行在 `internal: true` 的 Docker 网络上，只有接入同一网络的容器才能访问 `http://socket-proxy:2375`。公共互联网和其他 Docker 网络无法访问。
5. **只读 socket 挂载。** 主机 socket 以 `:ro` 方式挂载，代理本身无法被诱导写入；过滤发生在 HTTP 层。

## 快速开始

```bash
# 1. 配置白名单——从全部拒绝开始
cp .env.example .env
#   编辑 .env：只启用你的消费者需要的端点
#   大多数只读场景：CONTAINERS=1，其余 0

# 2. 启动代理
docker compose up -d

# 3. 验证过滤生效（可选，一次性 demo 客户端）
docker compose --profile demo up docker-api-demo
#   预期：GET /containers/json → 200（当 CONTAINERS=1）
#         POST /containers/create → 403（当 POST=0）
#         GET /info → 403（当 INFO=0）

# 4. 将其他容器指向过滤后的 API
#    设置 DOCKER_HOST=tcp://socket-proxy:2375
#    将它们接入 mb-socket-proxy 网络
```

## 端点参考

### 只读端点（GET/HEAD）

| 开关 | 端点组 | 默认 | 风险等级 | 说明 |
|---|---|---|---|---|
| `CONTAINERS` | `/containers/*` | `0` | 低（读） | 列出/检查容器。创建/杀死需要 `POST=1` |
| `IMAGES` | `/images/*` | `0` | 低（读） | 列出/检查镜像。拉取/构建需要 `POST=1` |
| `INFO` | `/info` | `0` | 低 | 守护进程信息（版本、存储驱动、标签） |
| `NETWORKS` | `/networks/*` | `0` | 低（读） | 列出/检查 Docker 网络 |
| `VOLUMES` | `/volumes/*` | `0` | 低（读） | 列出/检查数据卷 |
| `SYSTEM` | `/system/*` | `0` | 低（读） | `df`、`events`、`version` |
| `EVENTS` | `/events` | `0` | 低（读） | 流式守护进程事件（监控有用） |
| `NODES` | `/nodes/*` | `0` | 中 | Swarm 节点信息 |
| `SERVICES` | `/services/*` | `0` | 中 | Swarm 服务信息 |
| `TASKS` | `/tasks/*` | `0` | 中 | Swarm 任务信息 |
| `PLUGINS` | `/plugins/*` | `0` | 中 | 插件管理 |
| `SESSION` | `/session` | `0` | 中 | 交互式 attach 会话 |
| `SWARM` | `/swarm/*` | `0` | 中 | Swarm 管理 |
| `DISTRIBUTION` | `/distribution/*` | `0` | 低 | 镜像分发信息 |

### 写入端点（POST/PUT/DELETE）——危险

| 开关 | 端点组 | 默认 | 风险等级 | 说明 |
|---|---|---|---|---|
| `POST` | 写操作 | `0` | **高** | 所有端点 POST/PUT/DELETE 的主开关 |
| `EXEC` | `/exec/*` | `0` | **极高** | 在容器内执行任意命令——接近 root |
| `BUILD` | `/build` | `0` | **高** | 构建镜像（写） |
| `COMMIT` | `/commit` | `0` | **高** | 将容器状态提交为镜像（写） |
| `CONFIGS` | `/configs/*` | `0` | **高** | Swarm 配置（写） |
| `SECRETS` | `/secrets/*` | `0` | **极高** | Swarm 密钥（写）——可读取/修改集群密钥 |

**原则**：从全部 `0` 开始，只启用消费者需要的最小端点，除非消费者必须修改 Docker 状态否则保持 `POST=0`。`EXEC=1` + `POST=1` 等同于给消费者每个容器的 root shell——永远不要为不受信任或面向互联网的服务启用。

## 与其他套件的集成

socket-proxy 设计为跨所有套件共享。部署一次，然后将消费者接入 `mb-socket-proxy` 网络并指向 `http://socket-proxy:2375`。

### ai-automation — n8n 管理 Docker 容器

n8n 可以通过过滤代理编排 Docker 容器（启动/停止工作流、动态服务扩缩），而不是使用原始 socket。对于只读容器管理（列出、检查），启用 `CONTAINERS=1`。对于启动/停止操作，还需启用 `POST=1`。

```yaml
# 在 suites/ai-automation/compose.yml 中，添加到 n8n 服务：
services:
  n8n:
    environment:
      # 将 n8n 的 Docker 节点指向过滤代理
      - DOCKER_HOST=tcp://socket-proxy:2375
    networks:
      - mb-proxy
      - mb-socket-proxy

networks:
  mb-socket-proxy:
    external: true
```

推荐 `.env` 配置：`CONTAINERS=1`、`POST=0`（只读编排）。仅在 n8n 必须启动/停止容器时启用 `POST=1`。

### monitor-stack — 监控容器状态

需要抓取容器状态和健康状态的监控代理需要只读 Docker 可见性。启用 `CONTAINERS=1` 和 `INFO=1`（或 `SYSTEM=1` 用于 `/system/df`）。

```yaml
# 在 monitor-stack compose 中，添加到监控代理：
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

推荐 `.env` 配置：`CONTAINERS=1`、`INFO=1`、`POST=0`。代理可以观察容器状态和守护进程信息，但不能修改任何东西。

### backup-kit — 备份时查询容器列表

需要知道哪些容器正在运行的备份脚本（用于协调备份前后钩子）可以查询代理而不是原始 socket。只需启用 `CONTAINERS=1`。

```yaml
# 在备份 sidecar 容器中：
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

推荐 `.env` 配置：`CONTAINERS=1`、`POST=0`。备份工具可以列出容器并检查状态，但不能创建、杀死或 exec 进入容器。

参见 [`examples/docker-api-query.sh`](examples/docker-api-query.sh) 查询 Docker API 的现成脚本，以及 [`examples/integrate-with-monitoring.yml`](examples/integrate-with-monitoring.yml) 完整的监控集成 compose 片段。

## 安全最佳实践

1. **从默认拒绝开始。** 复制 `.env.example`（全部 `0`），逐个启用端点。测试消费者能正常工作后就停止——不要"以防万一"多开。
2. **只读消费者保持 `POST=0`。** 监控代理、反向代理和备份工具永远不需要修改 Docker 状态。`POST=0` 确保即使消费者被攻破，也无法创建、杀死或 exec 进入容器。
3. **永远不要为面向互联网的服务启用 `EXEC=1` + `POST=1`。** 这个组合让消费者可以在任意容器内执行任意命令——等同于每个容器的 root，通过数据卷挂载进而控制主机。
4. **不要发布端口。** 代理设计上没有 `ports:` 映射。添加端口映射会将过滤后的 API 暴露到主机网络甚至互联网。代理只能从 `mb-socket-proxy` 网络上的容器访问。
5. **为出网流量使用独立网络。** `mb-socket-proxy` 网络是 `internal: true`——上面的容器无法访问互联网。如果消费者同时需要 Docker API 访问和互联网出网，将它接入 `mb-socket-proxy` 和第二个非内部网络（如 `mb-proxy`）。
6. **定期审计白名单。** 定期审查 `.env`。你启用的每个端点都扩大了攻击面。移除消费者不再需要的端点。
7. **固定镜像版本。** 此套件使用 `tecnativa/docker-socket-proxy:0.1.5`（固定版本）。升级时需审慎评估 changelog——新版本可能新增或重命名端点开关。
8. **结合最小权限容器设置。** 即使有代理，也尽量以 `read_only: true`、最小能力和非 root 用户运行消费者。纵深防御。

## 与 network-toolkit 的关系

此套件是 [network-toolkit socket-proxy 模板](https://github.com/0x10debug/network-toolkit/tree/main/templates/socket-proxy)的**面向用户部署**版本：

| 方面 | network-toolkit 模板 | 此套件 |
|---|---|---|
| 面向对象 | 网络层运维者 | 部署应用套件的终端用户 |
| 范围 | 仅代理 + 网络配置 | 完整部署，含文档、示例、集成指南 |
| 网络 | 外部（手动 `docker network create --internal`） | 自动创建（compose 中 `internal: true`） |
| Demo 客户端 | 无 | `docker-api-demo` profile 用于验证 |
| 集成文档 | Traefik + 监控示例 | ai-automation、monitor-stack、backup-kit 集成 |
| 安全文档 | 端点参考 | 端点参考 + 风险等级 + 最佳实践 |

如果你已经部署了 network-toolkit 模板并手动创建了 `mb-socket-proxy`，在 `.env` 中设置 `MB_SOCKET_PROXY_NETWORK` 匹配，并将此套件 `compose.yml` 中的网络改为 `external: true`，避免创建第二个网络。

## 数据目录

此套件不存储持久数据——代理是无状态的。不使用任何 `/data/` 路径。

## 反向代理

此套件**不**加入 `mb-proxy` 网络，也不需要反向代理。socket-proxy 是内部基础设施服务，不是面向用户的 Web 应用。不要通过 Caddy 或 Traefik 暴露它。

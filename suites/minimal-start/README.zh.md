# 最小起步套件

"三件套"——VPS 加固后的第一个自然部署。带自动 SSL 的反向代理、运行时间监控、性能监控。这是其他所有套件的基础。

## 包含应用

| 应用 | 用途 | 默认端口 | Profile |
|---|---|---|---|
| Caddy | 反向代理 + 自动 SSL | 80, 443 | 默认 |
| Uptime Kuma | 运行时间监控 | 3001 | 默认 |
| Beszel agent | 性能监控代理 | 45876 | 默认 |

## 快速开始

```bash
# 部署三件套
docker compose up -d

# 查看运行中的服务
docker compose ps

# 停止所有服务
docker compose down
```

本套件没有可选服务——所有应用都在默认 profile 中，一起启动。

## 数据目录

```
/data/caddy/         — Caddy 数据（证书）和配置
/data/uptime-kuma/   — Uptime Kuma 数据库和监控配置
/data/beszel/        — Beszel agent 状态
```

## Caddy 配置

`Caddyfile` 在通过 `mb` CLI 部署时**从 `.env` 自动生成**。它配置 Caddy 以 HTTPS 提供 `PRIMARY_DOMAIN`，并通过 Let's Encrypt 自动申请证书。

要添加更多站点（为本套件或其他套件的服务），使用：

```bash
mb net proxy add
# 设置域名、目标容器和端口
```

Caddy 通过共享的 `mb-proxy` 网络按容器名路由流量。任何加入 `mb-proxy` 的容器都能被 Caddy 访问——这就是 `home-media` 或 `personal-productivity` 等套件无需自带代理即可获得 HTTPS 的方式。

## 监控配置

### Uptime Kuma

在 `http://<你的服务器>:3001` 访问 Uptime Kuma（或通过 Caddy 代理后的域名访问）。首次运行向导会让你创建管理员账号。之后你可以：

- 为任何服务添加 HTTP/TCP/Ping 监控
- 设置通知渠道（Discord、Telegram、邮件等）
- 按状态页分组监控

### Beszel Agent

Beszel agent 收集系统指标（CPU、内存、磁盘、网络）并上报到 **Beszel hub**。本套件不包含 hub——它可以在另一台服务器上运行，或单独部署。

将 agent 连接到 hub 的步骤：

1. 部署一个 Beszel hub 实例（参见 [beszel](https://github.com/henrygd/beszel)）。
2. 在 hub 界面中添加新 agent——你会获得一个密钥和 hub URL。
3. 在 `.env` 中设置 `BESZEL_HUB_KEY` 和 `BESZEL_HUB_URL`。
4. 重启 agent：`docker compose restart beszel-agent`。

agent 需要 `SYS_ADMIN` 权限和只读的 `/proc` 访问来读取宿主机指标。

## 为什么选这个套件

这是 **[vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) 之后推荐的首个部署**。VPS 加固完成后（SSH 密钥、防火墙、fail2ban、自动更新），在做任何其他事之前你需要三样东西：

1. **反向代理**——让后续添加的每个服务自动获得 HTTPS，无需逐个管理证书。
2. **运行时间监控**——在用户察觉之前就知道服务何时宕机。
3. **性能监控**——在资源压力演变成故障之前就能看到趋势。

先部署本套件，再叠加其他套件（[home-media](https://github.com/0x10debug/compose-recipes/tree/main/suites/home-media)、[personal-productivity](https://github.com/0x10debug/compose-recipes/tree/main/suites/personal-productivity) 等）。它们都加入同一个 `mb-proxy` 网络，由这里运行的 Caddy 实例统一代理。

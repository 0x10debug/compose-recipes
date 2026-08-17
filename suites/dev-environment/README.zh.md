# 开发环境套件

在 VPS 上自托管的开发工具链：Git 托管、浏览器 IDE、CI/CD 流水线和私有容器镜像仓库。用你自己掌控的服务替代 GitHub、VS Code Remote、GitHub Actions 和 Docker Hub。

## 包含应用

| 应用 | 用途 | 默认端口 | Profile |
|---|---|---|---|
| Gitea | 自托管 Git 托管 | 3000（Web）、2222（SSH） | 默认 |
| Code Server | 浏览器中的 VS Code | 8443 | 默认 |
| Woodpecker CI | CI/CD 流水线 | 8000 | `ci` |
| Registry | 私有 Docker 镜像仓库 | 5000 | `registry` |

## 快速开始

```bash
# 部署 Gitea + Code Server（默认）
docker compose up -d

# 加上 Woodpecker CI（需先运行 Gitea）
docker compose --profile all --profile ci up -d

# 加上私有容器镜像仓库
docker compose --profile all --profile registry up -d

# 全部部署
docker compose --profile all --profile ci --profile registry up -d
```

## 数据目录

```
/data/gitea/            — Gitea 应用数据、配置和仓库
/data/gitea/postgres/   — Gitea PostgreSQL 数据库
/data/code-server/      — Code Server 配置和工作区
/data/woodpecker/       — Woodpecker CI 数据
/data/woodpecker/postgres/ — Woodpecker PostgreSQL 数据库
/data/registry/         — 容器镜像仓库存储和认证
```

## 反向代理

要通过 HTTPS 域名暴露此套件，使用 [network-toolkit](https://github.com/0x10debug/network-toolkit)：

```bash
mb net deploy website
# 设置 WEBSITE_DOMAIN=git.example.com
# 设置 APP_HOST=gitea
# 设置 APP_PORT=3000
```

为每个要暴露的应用重复此操作（Code Server、Woodpecker CI、Registry）。Gitea SSH（端口 2222）需要单独的 TCP 代理条目。

## 配置说明

- **Gitea**：首次启动时，在 `http://<host>:3000` 完成 Web 安装。数据库已通过环境变量预配置；在安装页面创建初始管理员用户。
- **Woodpecker CI**：需要在 Gitea 中注册 OAuth 应用。在 Gitea 中进入 *设置 → 应用 → OAuth2*，创建一个应用，回调地址填 `https://<DEV_DOMAIN>/authorize`。将客户端 ID 和密钥填入 `.env` 的 `WOODPECKER_GITEA_CLIENT` 和 `WOODPECKER_GITEA_SECRET`，然后用 `--profile ci` 启动。
- **Code Server**：通过 `.env` 中的 `CODE_SERVER_PASSWORD` 设置登录密码。仓库目录挂载到 `/config/workspace/repos`，可直接编辑。
- **Registry**：要控制 push/pull 访问权限，在 `/data/registry/auth/htpasswd` 添加 htpasswd 认证文件，并在 compose 文件中启用 `REGISTRY_AUTH`。

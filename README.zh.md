# 自托管应用套件 — VPS Docker Compose 食谱

按场景组织的生产级 Docker Compose 食谱。不用从 1000+ 应用里挑选，直接选一个匹配你需求的套件——家庭媒体、个人生产力、开发环境、隐私保护或自托管云——一条命令部署。每个套件预配置网络、端口分配和反向代理集成。专为 VPS 和 Homelab Docker 服务器设计。

> **第一次自托管？** 从 [minimal-start](suites/minimal-start/) 套件开始——一条命令部署反向代理、可用性监控和性能监控。然后按需添加更多套件。

## 为什么需要这个 repo

想在 VPS 上自托管应用时，你会面临几个问题：

1. **选择太多** — awesome-selfhosted 列了 1000+ 应用，选哪个？
2. **每个应用都要单独配置** — compose 文件、环境变量、端口、数据卷都要研究
3. **多应用冲突** — 多个应用一起跑要处理端口冲突、网络配置、反代集成
4. **没有场景指导** — 现有 compose 集合给你的是"应用列表"不是"使用场景方案"

这个 repo 通过提供**场景化套件**来解决——预先编排好的应用组合，针对特定使用场景，所有配置已就绪。

## 什么是套件？

套件是一个目录，包含一个 `compose.yml` 文件和一组预配置好协同工作的应用：

- **端口预分配** — 同一套件内和跨套件无冲突
- **网络预配置** — 所有应用加入 `mb-proxy` Docker 网络，支持反代集成
- **数据路径统一** — 所有数据存到 `/data/<app-name>/`
- **.env 模板** — 填域名和密码即可部署
- **Profile 支持** — 可选应用通过 `--profile` 启用/禁用

## 可用套件

| 套件 | 应用 | 场景 |
|---|---|---|
| [home-media](suites/home-media/) | Jellyfin, Navidrome, Audiobookshelf, Immich | 替代 Netflix、Spotify、Audible、Google Photos |
| [personal-productivity](suites/personal-productivity/) | Vaultwarden, Memos, Outline, Linkwarden | 密码管理、笔记、知识库、书签 |
| [dev-environment](suites/dev-environment/) | Gitea, Code Server, Woodpecker CI, Registry | 自托管 Git、浏览器 IDE、CI/CD、Docker 仓库 |
| [privacy-suite](suites/privacy-suite/) | AdGuard Home, SearXNG, Vaultwarden, WireGuard | DNS 广告拦截、隐私搜索、VPN |
| [self-hosted-cloud](suites/self-hosted-cloud/) | Nextcloud, OnlyOffice, Filebrowser, Radicale | 替代 Google Drive、Office365、Dropbox |
| [ai-automation](suites/ai-automation/) | n8n, Ollama, Qdrant, Flowise | 自托管 AI 工作流、本地 LLM、向量搜索、RAG |
| [minimal-start](suites/minimal-start/) | Caddy, Uptime Kuma, Beszel | 基础三件套：反代、监控 |

## 快速开始

```bash
# 1. 加固 VPS 并安装 Docker（如未完成）
# → https://github.com/0x10debug/vps-bootstrap

# 2. 克隆此 repo
git clone https://github.com/0x10debug/compose-recipes.git
cd compose-recipes

# 3. 列出可用套件
./mb recipes list

# 4. 部署套件（交互式 .env 设置）
./mb recipes deploy home-media

# 5. 启用可选应用
./mb recipes deploy home-media --profile transmission

# 6. 查看状态
./mb recipes status
```

## 用法

```bash
mb recipes list                        # 列出所有可用套件
mb recipes deploy <suite>              # 部署套件（交互式）
mb recipes deploy <suite> --env-file .env  # 用已有 .env 部署
mb recipes status                      # 查看已部署套件状态
mb recipes update [<suite>]            # 更新套件镜像（全部或指定）
mb recipes stop [<suite>]              # 停止套件
mb recipes remove <suite>              # 移除套件（保留数据）
mb recipes help                        # 显示帮助
```

## 常见问题

### 如何用 Docker Compose 部署多个自托管应用？

从这个 repo 选一个套件，运行 `mb recipes deploy <套件名>`，填写 .env 文件，套件内所有应用一起启动，网络预配置、端口无冲突。每个套件针对一个场景（家庭媒体、生产力、开发、隐私、云）。

### 如何在 VPS 上搭建家庭媒体服务器？

部署 [home-media](suites/home-media/) 套件——包含 Jellyfin（视频）、Navidrome（音乐）、Audiobookshelf（有声书）和 Immich（照片）。一条命令启动四个应用：`mb recipes deploy home-media`。可选：用 `--profile transmission` 启用 BT 下载。

### 如何组织多个服务的 Docker Compose？

使用套件模式：将相关应用分组到一个 `compose.yml` 中，用 profile 控制可选组件。所有服务共享 `mb-proxy` 网络支持反代集成，数据统一存到 `/data/<app-name>/`。参见 [contributing-suites.md](docs/contributing-suites.md) 创建自己的套件。

### 如何避免自托管应用的端口冲突？

此 repo 中所有套件遵循[全局端口分配表](docs/port-allocation.md)。每个应用有预分配端口，不与其他套件的应用冲突。如果要从两个不同套件运行同一个应用，在 `.env` 中覆盖端口。

### Homelab 最好的自托管应用套件？

此 repo 中的套件覆盖最常见的 homelab 场景：家庭媒体、个人生产力、开发、隐私和云存储。从 [minimal-start](suites/minimal-start/) 开始部署基础三件套，然后按需添加。每个套件独立——只部署你需要的。

## 文档

- [端口分配](docs/port-allocation.md) — 所有套件的全局端口规划
- [反向代理设置](docs/reverse-proxy-setup.md) — 如何用 HTTPS 暴露你的应用
- [贡献套件](docs/contributing-suites.md) — 如何创建和提交新套件

## 相关项目

- [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) — 一条命令 VPS 初始化和安全加固
- [network-toolkit](https://github.com/0x10debug/network-toolkit) — 反向代理、SSL、穿透模板
- [monitor-stack](https://github.com/0x10debug/monitor-stack) — 轻量监控栈
- [backup-kit](https://github.com/0x10debug/backup-kit) — 预配置备份策略

## 许可证

[MIT](./LICENSE)

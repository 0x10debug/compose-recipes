# 自托管云套件

自托管替代 Google Drive、Dropbox 和 Office365 的方案。提供文件同步、协作文档编辑、文件管理器以及日历/联系人（CalDAV/CardDAV）。

## 包含内容

| 应用 | 用途 | 默认端口 | 配置文件 |
|------|------|----------|----------|
| Nextcloud | 文件同步 + 协作 | 8080 | 默认 |
| OnlyOffice | 文档编辑器（文档、表格、幻灯片） | 8443 | 默认 |
| Filebrowser | 网页端文件管理器 | 8081 | 默认 |
| Radicale | 日历 / 联系人（CalDAV / CardDAV） | 5232 | pim |

## 快速开始

1. 复制示例环境变量文件并填写你的值：

   ```bash
   cp .env.example .env
   # 编辑 .env —— 设置 CLOUD_DOMAIN、各密码以及 ONLYOFFICE_JWT_SECRET
   ```

2. 创建数据目录（见[数据目录](#数据目录)）。

3. 启动默认服务（Nextcloud、OnlyOffice、Filebrowser）：

   ```bash
   docker compose up -d
   ```

4. 如需同时启动 PIM 组件（Radicale），使用 `pim` 配置文件：

   ```bash
   docker compose --profile pim up -d
   ```

5. 一次性启动全部服务：

   ```bash
   docker compose --profile all up -d
   ```

## 数据目录

所有持久化数据存放在宿主机的 `/data` 下：

| 路径 | 服务 |
|------|------|
| `/data/nextcloud` | Nextcloud 用户文件 |
| `/data/nextcloud-apps` | Nextcloud 已安装应用 |
| `/data/nextcloud-config` | Nextcloud 配置 |
| `/data/nextcloud-postgres` | Nextcloud PostgreSQL 数据库 |
| `/data/nextcloud-redis` | Nextcloud Redis 缓存 |
| `/data/onlyoffice` | OnlyOffice 文档服务数据 |
| `/data/filebrowser` | Filebrowser 数据库 + 配置 |
| `/data/radicale` | Radicale 日历/联系人数据 |

Filebrowser 还将 `/data`（宿主机整个数据根目录）挂载到容器内的 `/srv`，因此可以浏览 `/data` 下的任意文件。

## 反向代理

本套件设计为在外部 `mb-proxy` Docker 网络上的反向代理之后运行。配置 TLS 终结并将流量路由到各服务的容器端口。

现成的反向代理 / 网络工具包请见：
https://github.com/0x10debug/network-toolkit

## Nextcloud 设置

1. 在浏览器中打开 `https://<CLOUD_DOMAIN>`（本地测试可用 `http://localhost:8080`）。
2. 完成初始安装向导。数据库已通过环境变量预配置（PostgreSQL + Redis），安装程序会自动识别。
3. 检查**可信域名** —— `NEXTCLOUD_TRUSTED_DOMAINS` 由 `.env` 中的 `CLOUD_DOMAIN` 设置。如果需要通过其他域名或 IP 访问 Nextcloud，请在 `config/config.php` 的 `trusted_domains` 中添加。
4. `overwrite.cli.url` 和 `overwriteprotocol` 已配置为反向代理后的 HTTPS。如通过 HTTP 提供服务请相应调整。

## OnlyOffice 集成

1. OnlyOffice 文档服务运行在端口 `8443`，已启用 JWT 认证（`ONLYOFFICE_JWT_SECRET`）。
2. 在 Nextcloud 中安装 **ONLYOffice** 连接器应用：
   - 应用 → 办公与文本 → **ONLYOffice** → 启用。
3. 进入管理设置 → ONLYOffice：
   - **文档编辑服务地址**：`https://<CLOUD_DOMAIN>`（如在同一网络内，可使用 OnlyOffice 容器地址，如 `https://onlyoffice`）。
   - **密钥**：`.env` 中 `ONLYOFFICE_JWT_SECRET` 的值。
4. 保存。之后即可在 Nextcloud 中直接创建并协同编辑 `.docx`、`.xlsx` 和 `.pptx` 文件。

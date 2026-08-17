# 个人生产力套件

自托管生产力套件，替代 1Password、Evernote、Notion、Pocket 和 Adobe Acrobat。从你自己的 VPS 管理密码、笔记、团队知识库、书签和 PDF 工具。

## 包含应用

| 应用 | 用途 | 默认端口 | Profile |
|---|---|---|---|
| Vaultwarden | 密码管理器（兼容 Bitwarden） | 8222 | 默认 |
| Memos | 轻量笔记 | 5230 | 默认 |
| Outline | 团队知识库 | 3000 | 默认 |
| Linkwarden | 书签管理 | 3001 | 默认 |
| Stirling-PDF | PDF 工具 | 8800 | `pdf` |

## 快速开始

```bash
# 只部署默认应用
docker compose up -d

# 启用 PDF 工具
docker compose --profile pdf up -d

# 全部启用
docker compose --profile all --profile pdf up -d
```

## 数据目录

```
/data/vaultwarden/    — Vaultwarden 密码库数据和附件
/data/memos/          — Memos 笔记数据库
/data/outline/        — Outline 数据、上传、postgres 和 redis
/data/linkwarden/     — Linkwarden 书签和 postgres
/data/stirling-pdf/   — Stirling-PDF 配置、日志和自定义文件
```

## 反向代理

要通过 HTTPS 域名暴露此套件，使用 [network-toolkit](https://github.com/0x10debug/network-toolkit)：

```bash
mb net deploy website
# 设置 WEBSITE_DOMAIN=vault.example.com
# 设置 APP_HOST=vaultwarden
# 设置 APP_PORT=80
```

为每个要暴露的应用重复此操作（Memos、Outline、Linkwarden、Stirling-PDF）。

## 安全提示

**Vaultwarden 使用前必须启用 HTTPS。** Bitwarden 客户端拒绝通过纯 HTTP 同步。在创建密码库或邀请用户之前，请先通过 [network-toolkit](https://github.com/0x10debug/network-toolkit) 启用带 TLS 的反向代理。保持 `VAULTWARDEN_SIGNUPS_ALLOWED=false` 以防止开放注册，并设置强 `VAULTWARDEN_ADMIN_TOKEN` 以保护管理面板。

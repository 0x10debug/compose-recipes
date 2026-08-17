# 隐私保护套件

自托管隐私保护栈，在 DNS 层面屏蔽广告、提供私有搜索引擎、管理你的密码，并用个人 VPN 加密流量。从你自己的 VPS 上夺回数据控制权。

## 包含应用

| 应用 | 用途 | 默认端口 | Profile |
|---|---|---|---|
| AdGuard Home | DNS 过滤/广告屏蔽 | 53（DNS）、80（Web） | 默认 |
| SearXNG | 私有元搜索引擎 | 8080 | 默认 |
| Vaultwarden | 密码管理器（兼容 Bitwarden） | 8222 | 默认 |
| WireGuard Easy | WireGuard VPN（带 Web 管理界面） | 51820/udp（VPN）、51821（Web） | `vpn` |

## 快速开始

```bash
# 只部署默认应用（DNS 屏蔽、私有搜索、密码管理）
docker compose up -d

# 启用 VPN
docker compose --profile vpn up -d

# 全部启用
docker compose --profile all --profile vpn up -d
```

## 数据目录

```
/data/adguardhome/     — AdGuard Home 配置和过滤规则
/data/searxng/         — SearXNG 设置
/data/searxng-redis/   — SearXNG 缓存（Redis）
/data/vaultwarden/     — Vaultwarden 数据库和附件（SQLite）
/data/wireguard/       — WireGuard 配置和客户端档案
```

## 反向代理

要通过 HTTPS 域名暴露此套件，使用 [network-toolkit](https://github.com/0x10debug/network-toolkit)：

```bash
mb net deploy website
# 设置 WEBSITE_DOMAIN=privacy.example.com
# 设置 APP_HOST=searxng
# 设置 APP_PORT=8080
```

为每个要暴露的应用重复此操作（AdGuard Home、Vaultwarden、WireGuard Easy）。
注意：AdGuard Home 的 DNS 服务直接运行在 53 端口，不经过反向代理。

## DNS 设置

AdGuard Home 通过 DNS 提供全网广告屏蔽。使用方法：

1. 部署后，打开 AdGuard Home Web 界面 `http://<VPS-IP>:80`，完成初始设置向导（设置管理员密码）。
2. 将路由器的 DNS 服务器（或单个客户端的 DNS）改为你的 VPS IP 地址。
3. 这些设备的所有 DNS 查询都会被过滤——广告和追踪器在加载前就被屏蔽。

如需精细控制，可在单个设备上分别配置 DNS，而不必修改路由器全局设置。

## VPN 设置

WireGuard Easy 提供个人 VPN，带 Web 管理界面来管理客户端。使用方法：

1. 使用 `vpn` profile 部署：`docker compose --profile vpn up -d`
2. 打开 WireGuard Easy Web 界面 `http://<VPS-IP>:51821`，用你设置的 `ADGUARD_PASSWORD` 登录。
3. 添加一个客户端（如你的手机或笔记本），下载配置文件或扫描二维码。
4. 用 WireGuard 应用连接设备——所有流量都会通过你的 VPS 路由，DNS 由 AdGuard Home 过滤。

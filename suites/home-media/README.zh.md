# 家庭媒体套件

自托管媒体服务器，替代 Netflix、Spotify、Audible 和 Google Photos。从你自己的 VPS 流式播放电影、音乐、有声书和照片。

## 包含应用

| 应用 | 用途 | 默认端口 | Profile |
|---|---|---|---|
| Jellyfin | 视频/电影流媒体 | 8096 | 默认 |
| Navidrome | 音乐流媒体 | 4533 | 默认 |
| Audiobookshelf | 有声书/播客 | 13378 | 默认 |
| Immich | 照片/视频管理 | 2283 | 默认 |
| Transmission | BT 下载 | 9091 | `transmission` |
| Bazarr | 字幕管理 | 6767 | `subtitles` |

## 快速开始

```bash
# 只部署默认应用
docker compose up -d

# 启用 BT 下载
docker compose --profile transmission up -d

# 启用字幕管理
docker compose --profile subtitles up -d

# 全部启用
docker compose --profile transmission --profile subtitles up -d
```

## 数据目录

```
/data/jellyfin/        — Jellyfin 配置和缓存
/data/navidrome/       — Navidrome 数据库
/data/audiobookshelf/  — Audiobookshelf 配置和元数据
/data/immich/          — Immich 上传和数据库
/data/transmission/    — Transmission 下载
/data/bazarr/          — Bazarr 配置
/data/media/           — 你的媒体库（电影、电视、音乐、有声书、照片）
```

## 反向代理

要通过 HTTPS 域名暴露此套件，使用 [network-toolkit](https://github.com/0x10debug/network-toolkit)：

```bash
mb net deploy website
# 设置 WEBSITE_DOMAIN=media.example.com
# 设置 APP_HOST=jellyfin
# 设置 APP_PORT=8096
```

为每个要暴露的应用重复此操作。

## 媒体存储

将你的媒体库挂载到 `/data/media/`，子目录结构：
```
/data/media/movies/
/data/media/tv/
/data/media/music/
/data/media/audiobooks/
/data/media/podcasts/
/data/media/photos/
```

大型媒体库建议挂载外部硬盘或网络存储到 `/data/media/`。

# Home Media Suite

A self-hosted media server that replaces Netflix, Spotify, Audible, and Google Photos. Stream your movies, music, audiobooks, and photos from your own VPS.

## What's Included

| App | Purpose | Default Port | Profile |
|---|---|---|---|
| Jellyfin | Video & movie streaming | 8096 | Default |
| Navidrome | Music streaming | 4533 | Default |
| Audiobookshelf | Audiobooks & podcasts | 13378 | Default |
| Immich | Photo & video management | 2283 | Default |
| Transmission | BitTorrent download | 9091 | `transmission` |
| Bazarr | Subtitle management | 6767 | `subtitles` |

## Quick Start

```bash
# Deploy with default apps only
docker compose up -d

# Deploy with BT download enabled
docker compose --profile transmission up -d

# Deploy with subtitles management
docker compose --profile subtitles up -d

# Deploy everything
docker compose --profile transmission --profile subtitles up -d
```

## Data Directories

```
/data/jellyfin/        — Jellyfin config and cache
/data/navidrome/       — Navidrome database
/data/audiobookshelf/  — Audiobookshelf config and metadata
/data/immich/          — Immich uploads and database
/data/transmission/    — Transmission downloads
/data/bazarr/          — Bazarr config
/data/media/           — Your media library (movies, TV, music, audiobooks, photos)
```

## Reverse Proxy

To expose this suite via HTTPS with a domain, use [network-toolkit](https://github.com/0x10debug/network-toolkit):

```bash
mb net deploy website
# Set WEBSITE_DOMAIN=media.example.com
# Set APP_HOST=jellyfin
# Set APP_PORT=8096
```

Repeat for each app you want to expose (Navidrome, Immich, etc.).

## Media Storage

Mount your media library at `/data/media/` with subdirectories:
```
/data/media/movies/
/data/media/tv/
/data/media/music/
/data/media/audiobooks/
/data/media/podcasts/
/data/media/photos/
```

For large media libraries, consider mounting an external drive or network storage at `/data/media/`.

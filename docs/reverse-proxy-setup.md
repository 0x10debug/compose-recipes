# Reverse Proxy Setup

This guide explains how to expose your self-hosted apps to the internet with HTTPS using a reverse proxy.

## Prerequisites

- A hardened VPS (run [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) first)
- Docker installed
- A domain name pointing to your VPS IP
- A deployed suite from this repo

## Option 1: Use network-toolkit (Recommended)

[network-toolkit](https://github.com/0x10debug/network-toolkit) provides pre-configured reverse proxy templates:

```bash
# Deploy a basic reverse proxy with Caddy + automatic SSL
mb net deploy website

# Enter your domain and the target container
# WEBSITE_DOMAIN=app.example.com
# APP_HOST=container-name
# APP_PORT=8080
```

This creates a Caddy container that:
- Joins the `mb-proxy` Docker network
- Routes traffic from your domain to the target container
- Automatically obtains and renews Let's Encrypt SSL certificates
- Injects security headers (HSTS, X-Content-Type-Options, etc.)

## Option 2: Use minimal-start suite

The [minimal-start](../suites/minimal-start/) suite includes Caddy as the reverse proxy:

```bash
mb recipes deploy minimal-start
```

Then add routes for each app you want to expose:

```bash
mb net proxy add app.example.com app-container:8080
```

## How It Works

All suites in this repo join the `mb-proxy` Docker network. The reverse proxy (Caddy) also joins this network. This allows the proxy to route traffic to any container by name, without exposing container ports to the host.

```
Internet → VPS:443 → Caddy (reverse proxy) → mb-proxy network → target container
```

## Adding a New Route

To expose a newly deployed app:

1. Ensure the app's container is on the `mb-proxy` network (all suites do this by default)
2. Add a DNS record pointing your domain to the VPS IP
3. Add a proxy route:

```bash
# Using network-toolkit
mb net proxy add myapp.example.com myapp-container:8080
```

4. Caddy automatically obtains an SSL certificate for the new domain

## Removing a Route

```bash
mb net proxy remove myapp.example.com
```

## SSL Certificate Management

Caddy handles SSL certificates automatically:
- **Provisioning**: Certificates are obtained from Let's Encrypt on first request
- **Renewal**: Certificates are renewed automatically before expiry
- **Checking**: `mb net ssl list` shows certificate status and expiry dates
- **Manual renew**: `mb net ssl renew` forces renewal

## Security Headers

All reverse proxy templates include these security headers by default:

| Header | Value | Purpose |
|---|---|---|
| Strict-Transport-Security | max-age=31536000; includeSubDomains | Force HTTPS |
| X-Content-Type-Options | nosniff | Prevent MIME type sniffing |
| X-Frame-Options | DENY | Prevent clickjacking |
| Referrer-Policy | strict-origin-when-cross-origin | Limit referrer leakage |

## Troubleshooting

### Container not reachable from proxy
- Verify the container is on the `mb-proxy` network: `docker network inspect mb-proxy`
- Verify the container name matches what you used in the proxy config
- Verify the container port is correct (check the suite's compose.yml)

### SSL certificate not obtained
- Ensure port 80 and 443 are open in your firewall
- Ensure the domain DNS record points to your VPS IP
- Check Caddy logs: `docker logs caddy`

### 502 Bad Gateway
- The target container is not running — check with `docker ps`
- The target container is on a different network — join it to `mb-proxy`
- The target port is wrong — check the suite's compose.yml for the internal port

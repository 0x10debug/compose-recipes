# Container Hardening Matrix

Baseline applied to every service in every suite, with per-app exceptions and
their reasons. `scripts/hardening-lint.sh` enforces the baseline in CI; an
exception must be listed here AND in the lint's allowlist with the same
justification.

## Baseline v1 (this iteration)

| Control | Status | Notes |
|---|---|---|
| `security_opt: [no-new-privileges:true]` | **applied to all 43 services** | Prevents privilege escalation via setuid binaries inside containers. Safe universally: no filesystem or capability impact. |
| Resource limits (`deploy.resources.limits`) | partial | Applied to new services (e.g. gitea-runner). Rolling out limits to every suite needs per-app memory profiling - follow-up. |
| Healthchecks | partial | Present on most stateful services; stateless sidecars (curl demo) do not need them. |
| Pinned image tags | applied | All suites pin versions; digest locks are tracked separately (Round 3, `iter/compose-digest-locks`). |

## Planned controls (require per-app smoke boots first)

| Control | Why it is not blanket-applied | Candidates |
|---|---|---|
| `read_only: true` + `tmpfs` | Many apps write to their image filesystem (transcoding, plugin installs, apt in entrypoints). Each app needs a smoke boot to enumerate write paths. | nginx-based, vaultwarden, searxng |
| `cap_drop: [ALL]` + minimal `cap_add` | Default set is generous; safe drops vary per app (e.g. Jellyfin/Immich need specific caps for hardware access). | per-app table below as it is filled |
| Dedicated user (`user:`) | Apps with entrypoint root-steps (chown of volumes) break silently; needs per-app verification. | nextcloud, gitea |

## Exceptions (none yet)

No service is exempt from `no-new-privileges`. If a future service cannot
tolerate it, add the service to the allowlist in `scripts/hardening-lint.sh`
and document the reason here in the same change.

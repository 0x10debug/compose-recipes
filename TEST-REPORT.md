# TEST-REPORT

Living per-iteration test report, maintained per the Testing Discipline iron
rule (main repo AGENTS.md, 2026-09-06).

Layer definitions: L1 static (bash -n, shellcheck, gitleaks, no-Chinese scan),
L2 config validation, L3 runtime smoke in a disposable environment, L4
host-level lifecycle.

---

## 2026-09-06T20:20:59Z — commit c82ea4c (Round 2 Day 10 backfill: CI pipeline, template repair)

**Layers executed: L1, L2. L3/L4 not run.**

| Check | Result |
|---|---|
| L1 bash -n sweep (12 files + mb) | PASS |
| L1 shellcheck -S warning gate | PASS (0 findings; 3 fixed in iter/compose-ci-validate) |
| L1 gitleaks history scan | PASS (exit 0) |
| L1 no-Chinese content scan (CI job, run 33997460245) | PASS |
| L2 scripts/validate-compose.sh: 8 suites direct + 2 templates via dummy rendering | PASS (10 valid, 0 failed) |

Defects found during this development cycle (fixed pre-push, CI-verified):

- suite-template compose.yml port mappings and DB password used malformed
  brace interpolation (`${{` vs the correct `${{{`) that could never render
  into valid compose - caught by the new validation, fixed in c82ea4c.

Known issues (open): none recorded this cycle.

Untested (honest boundaries):

- L3 runtime smoke: no suite was actually booted this cycle; `docker compose
  config` proves structure, not that services start and answer. Booting at
  least minimal-start in a disposable environment is the next runtime
  evidence step (data dirs on /Volumes/D per the Docker data rule).
- L4 host-level lifecycle (upgrade-with-data-preservation, backup/restore of
  suite volumes) not run - blocked on the Round 3 upgrade/restore fixtures
  (iter/compose-upgrade-fixture, iter/backup-restore-fixture).

---

## 2026-09-11T20:23:49Z — commit 8980ccc (Round 2 Day 12: iter/compose-gitops-suite)

**Layers executed: L1, L2, L3 (hook dry-run + compose profile matrix). L4 not run.**

| Check | Result |
|---|---|
| L1 bash -n + shellcheck repo-wide (incl. modified backup-hooks lib) | PASS |
| L2 validate-compose.sh: 10/10 compose units valid | PASS |
| L3 compose profile matrix: default = 3 core services; --profile ci --profile actions = all 6; standalone --profile actions validates (rc 0) | PASS (3/3 combos) |
| L3 backup-hook discovery with MB_BACKUP_COMPOSE_PROFILES="ci actions": 2/2 postgres services found; dry-run fires 2/2 pg_dump commands | PASS |

Defects found and fixed in this cycle:

1. **Suite profile model broken since creation** (high): core services with
   `profiles: ["all", ""]` are excluded under any --profile flag, so every
   documented optional-profile command failed compose validation. Core
   services are now always enabled (no profiles key).
2. **Backup hooks silently skipped optional-profile databases**: discovery
   enumerated only default-profile services, so databases behind a profile
   were never dumped. MB_BACKUP_COMPOSE_PROFILES now passes profile flags
   through discovery and hooks.
3. Registration-token and socket-mount design for the runner simplified to
   match act_runner's actual registration flow (config-file mount removed).

Untested (honest boundaries):

- The runner was not started against a live Gitea instance (registration
  requires a running Gitea and admin token); registration and job execution
  are runbook-documented only.
- Real pg_dump execution (non-dry-run) requires a running postgres container
  with seed data - covered later with backup-kit's restore fixture work.
- L4 host-level: end-to-end CI job execution and backup-restore of the
  suite's volumes - blocked on a disposable environment.

---

## 2026-09-11T20:28:34Z — commit 380b589 (Round 2 Day 12: iter/compose-hardening-pass)

**Layers executed: L1, L2, L3 (lint + intentional-red). L4 not run.**

| Check | Result |
|---|---|
| L1 bash -n + shellcheck repo-wide (incl. new hardening-lint.sh) | PASS |
| L2 validate-compose.sh 10/10 after 42+1 security_opt insertions | PASS |
| L3 hardening-lint.sh: 43/43 services covered, 0 violations; intentional-red (strip one service) produces a named VIOLATION and rc 1; restored and green | PASS |

Scope decision (recorded in docs/hardening-matrix.md): no-new-privileges is
universal and applied now; read_only, cap_drop, and dedicated-user controls
are NOT blanket-applied because each app needs a smoke boot to enumerate
write paths and capabilities - documented as per-app follow-ups in the
matrix rather than silently skipped.

Untested (honest boundaries):

- No suite was booted with the new security_opt this cycle; the control is
  validated as config (no-new-privileges has no filesystem impact, so boot
  risk is low, but L3 boot evidence is not claimed).
- read_only/cap_drop rollout: blocked on per-app smoke boots (listed in the
  matrix).
- L4 host-level: full lifecycle with hardened services - blocked on a
  disposable environment.

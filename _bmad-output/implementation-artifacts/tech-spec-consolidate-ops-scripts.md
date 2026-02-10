---
title: 'Consolidate and Improve Operational Scripts'
slug: 'consolidate-ops-scripts'
created: '2026-02-10'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack: [bash, docker-compose, docker]
files_to_modify:
  - scripts/lib/common.sh (new)
  - scripts/deploy.sh (rewrite — merge deploy.sh + update.sh)
  - scripts/update.sh (delete)
  - scripts/start.sh (new)
  - scripts/stop.sh (new)
  - scripts/restart.sh (new)
  - scripts/health-check.sh (refactor + fix n8n-worker reference)
  - scripts/backup.sh (refactor to source common.sh)
  - scripts/restore.sh (refactor + fix n8n-worker references on lines 54 and 105)
code_patterns:
  - source scripts/lib/common.sh for shared functions
  - set -euo pipefail in all scripts
  - log helper functions (log_success, log_warn, log_error, log_info) replace raw echo patterns
  - ensure_project_root function for consistent directory resolution
  - compose command builder (dc_cmd) bakes in --profile flag when provided
  - stop uses 'docker compose stop' (preserve containers)
  - restart uses 'docker compose up -d --force-recreate' (recreate with current config, no pull)
  - deploy uses full pipeline with 'docker compose up -d --remove-orphans'
test_patterns: []
---

# Tech-Spec: Consolidate and Improve Operational Scripts

**Created:** 2026-02-10

## Overview

### Problem Statement

The `scripts/` directory has heavy code duplication — `validate_env_vars()`, color definitions, and health-wait logic are copy-pasted across `deploy.sh`, `update.sh`, and `health-check.sh`. Basic operational scripts (start/stop/restart) are missing, forcing manual `docker compose` commands. No scripts are Ollama profile-aware. `restore.sh` references a non-existent singular `n8n-worker` instead of `n8n-worker-{1,2,3}`.

### Solution

Extract shared code into `scripts/lib/common.sh`, merge `deploy.sh` + `update.sh` into a unified `deploy.sh` (git pull ON by default), add `start.sh`/`stop.sh`/`restart.sh` for full-stack operations, make all relevant scripts profile-aware via `--profile <name>`, and fix the `restore.sh` worker bug.

### Scope

**In Scope:**
- Create `scripts/lib/common.sh` with shared functions (colors, env validation, health wait, project root detection)
- Merge `deploy.sh` + `update.sh` into unified `deploy.sh` (git pull default ON, `--skip-git` to opt out)
- Delete `update.sh`
- New `start.sh`, `stop.sh`, `restart.sh` — full stack operations (no per-service targeting)
- `--profile <name>` flag support across start/stop/restart/deploy
- Fix `restore.sh` worker references (`n8n-worker` → `n8n-worker-{1,2,3}`)
- Refactor `health-check.sh`, `backup.sh`, `restore.sh` to source `common.sh`

**Out of Scope:**
- Rewriting backup/restore logic beyond the worker bug fix and common.sh refactor
- Kubernetes scripts
- CI/CD pipeline changes

## Context for Development

### Codebase Patterns

- All scripts use `#!/usr/bin/env bash` and `set -euo pipefail`
- Consistent color scheme: RED, GREEN, YELLOW, BLUE, CYAN, NC
- Scripts expect to be run from project root (check for `docker-compose.yml`)
- `.env` loaded with `set -a; source .env; set +a`
- Banner pattern: blue `===` header lines with script name
- Health checks poll `docker compose ps --format "{{.Health}}"` in a loop
- Backup script is called by deploy with a directory argument
- Docker Compose profiles: `cpu`, `gpu-nvidia`, `gpu-amd` (for Ollama)
- **Log helpers** replace raw `echo -e` patterns: `log_success`, `log_warn`, `log_error`, `log_info`, `log_header`
- **`ensure_project_root`** in common.sh resolves project root via `BASH_SOURCE` and `cd`s there — scripts work from any invocation directory
- **`dc_cmd`** variable in common.sh builds the `docker compose` prefix with `--profile` when provided
- **Semantic stop/restart distinction:** `stop` = `docker compose stop` (preserve containers), `restart` = `docker compose up -d --force-recreate` (recreate with current config, no image pull), `deploy` = full pipeline with `--remove-orphans`

### Duplication Inventory (Ground Truth)

| Code Block | Files Containing Copy | Notes |
| --- | --- | --- |
| `validate_env_vars()` | deploy.sh, update.sh, health-check.sh | health-check has different return semantics (0/1/2 vs 0/1) |
| Color definitions | All 5 scripts | deploy/update/health-check have full 6 colors (RED/GREEN/YELLOW/BLUE/CYAN/NC), backup has 4 (RED/GREEN/BLUE/NC), restore has 5 (adds YELLOW). common.sh will provide all 6 to every script. |
| `.env` loading (`set -a; source .env; set +a`) | deploy.sh, update.sh, health-check.sh, backup.sh | 4 copies |
| Health wait loop | deploy.sh (lines 289-323), update.sh (lines 187-212) | Two different implementations: deploy uses global 60s timeout polling all services together at 5s intervals; update uses per-service sequential retries (30x at 2s). Normalize to global-timeout approach (deploy-style) in `wait_for_healthy`. |
| Version check (n8n vs runner) | deploy.sh (lines 246-260), update.sh (lines 154-168) | Identical grep-based logic |

### Bug Inventory

| File | Line(s) | Bug | Fix |
| --- | --- | --- | --- |
| `restore.sh` | 54 | `docker compose stop n8n n8n-worker` — targets non-existent service, misses task runners | Use bulk `dc stop` (stops everything) |
| `restore.sh` | 105 | `docker compose up -d n8n n8n-worker` — same issue | Use bulk `dc up -d` (starts everything with correct dependency ordering) |
| `health-check.sh` | 123 | `SERVICES` array includes `"n8n-worker"` — doesn't exist | Change to individual `n8n-worker-1`, `n8n-worker-2`, `n8n-worker-3` |
| `deploy.sh` | 246-250 | Fragile version check via `grep -A 1 "^  n8n:"` can match wrong services | Replace with `docker compose config --format json \| jq` in `check_version_sync` |

### Docker Compose Service Map

**Non-profile services:** postgres, redis, n8n-import, n8n, n8n-worker-{1,2,3}, n8n-task-runner, n8n-task-runner-{1,2,3}, caddy, qdrant

**Profile services:**
- `cpu`: ollama-cpu, ollama-pull-llama-cpu
- `gpu-nvidia`: ollama-gpu, ollama-pull-llama-gpu
- `gpu-amd`: ollama-gpu-amd, ollama-pull-llama-gpu-amd

### Files to Reference

| File | Purpose |
| --- | --- |
| `scripts/deploy.sh` | Current deploy script (371 lines) — merge source |
| `scripts/update.sh` | Current update script (230 lines) — merge source, to be deleted |
| `scripts/health-check.sh` | Health checker (210 lines) — refactor + fix worker reference |
| `scripts/backup.sh` | Backup script (139 lines) — refactor to use common.sh |
| `scripts/restore.sh` | Restore script (136 lines) — refactor + fix worker bug (lines 54, 105) |
| `docker-compose.yml` | Service definitions (625 lines), profile names, worker naming |

### Technical Decisions

- **Git pull default ON:** Matches current `deploy.sh` behavior. Opt-out via `--skip-git`.
- **Full stack operations:** start/stop/restart always affect all containers. No per-service targeting.
- **Profile passthrough:** `--profile <name>` flag on start/stop/restart/deploy passes through to `docker compose --profile <name>`.
- **common.sh sourcing:** All scripts resolve their own directory via `BASH_SOURCE`, then source `lib/common.sh` relative to that. Works from any CWD.
- **Stop vs Down:** `stop.sh` uses `docker compose stop` to preserve containers for fast restart. `deploy.sh` uses `docker compose up -d --remove-orphans` for full recreation with new images.
- **Restart semantics:** `restart.sh` uses `docker compose up -d --force-recreate` — recreates containers with current config/env without pulling new images. Picks up .env and compose file changes.
- **Log helpers:** All scripts use `log_success`, `log_warn`, `log_error`, `log_info`, `log_header` from common.sh instead of raw echo patterns.

## Implementation Plan

### Tasks

- [ ] Task 1: Create `scripts/lib/common.sh` — shared library
  - File: `scripts/lib/common.sh` (new)
  - Action: Create the shared library with the following functions and variables:
    - **Color definitions:** `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `NC`
    - **`log_info "msg"`** — prints `echo -e "${BLUE}msg${NC}"`
    - **`log_success "msg"`** — prints `echo -e "${GREEN}✓${NC} msg"`
    - **`log_warn "msg"`** — prints `echo -e "${YELLOW}⚠${NC} msg"`
    - **`log_error "msg"`** — prints `echo -e "${RED}✗${NC} msg"`
    - **`log_header "title"`** — prints the blue `===` banner pattern with title
    - **`ensure_project_root`** — resolves project root from `BASH_SOURCE` (walks up from `scripts/lib/` to project root), verifies `docker-compose.yml` exists, `cd`s there. Exits 1 if not found.
    - **`load_env`** — checks `.env` exists, runs `set -a; source .env; set +a`. Exits 1 if missing.
    - **`validate_env_vars`** — consolidated from deploy.sh/update.sh/health-check.sh. Returns 0 (all good), 1 (warnings — important vars like `DOMAIN_NAME`, `SUBDOMAIN`, `GENERIC_TIMEZONE` missing), 2 (critical — any of `N8N_ENCRYPTION_KEY`, `N8N_USER_MANAGEMENT_JWT_SECRET`, `N8N_RUNNERS_AUTH_TOKEN`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` missing OR set to `change_me`/`changeme`). Prints detailed report. All scripts that mutate state (deploy, start, restart) MUST exit on return code 2. This preserves current deploy.sh behavior where weak/default passwords block deployment.
    - **`wait_for_healthy [timeout_seconds]`** — normalized health poll loop. Checks all services with healthchecks: postgres, redis, n8n, n8n-worker-1, n8n-worker-2, n8n-worker-3. Polls `docker compose ps --format "{{.Health}}"` every 5s using a global timeout (default 60s). Returns 0 if all healthy, 1 if timeout. Prints per-service status as they become healthy.
    - **`check_version_sync`** — verifies n8n and task runner image versions match. Uses `docker compose config --format json | jq` to extract exact image tags for the `n8n` and `n8n-task-runner` services (avoids the fragile `grep -A 1 "^  n8n:"` pattern in current scripts which can match `n8n-import`, `n8n-worker-*`, etc.). Exits 1 on mismatch, prints versions. Requires `jq` to be installed.
    - **`require_docker`** — checks `docker info` succeeds. Exits 1 if Docker not running.
    - **`parse_profile_flag`** — parses `--profile <name>` from `$@`, validates against known profiles (`cpu`, `gpu-nvidia`, `gpu-amd`), sets global `COMPOSE_PROFILE` variable. Uses a global `REMAINING_ARGS` array to return unparsed arguments (bash functions can't return strings). Callers use: `parse_profile_flag "$@"; set -- "${REMAINING_ARGS[@]}"` to get remaining args back into positional params.
    - **`dc` (function)** — wrapper that runs `docker compose ${COMPOSE_PROFILE:+--profile "$COMPOSE_PROFILE"} "$@"`. All scripts call `dc` instead of `docker compose` directly.
  - Notes: This file is sourced by all other scripts, never executed directly. No shebang needed but include one for shellcheck. Include `set -euo pipefail` guard. The `dc` function approach is cleaner than a `$DC_CMD` variable because it handles quoting correctly.

- [ ] Task 2: Rewrite `scripts/deploy.sh` — unified deploy pipeline
  - File: `scripts/deploy.sh` (rewrite)
  - Action: Rewrite as a clean pipeline that sources `common.sh` and uses its functions. Structure:
    1. Source `common.sh`, call `ensure_project_root`, `load_env`
    2. Parse flags: `--no-backup`, `--skip-git`, `--no-health-check`, `--profile <name>`, `--help`
    3. Validate env (call `validate_env_vars`, exit on return code 2)
    4. Step 1 — Git pull (if enabled): check for `.git`, warn on uncommitted changes, pull, show diff. Use existing deploy.sh logic.
    5. Step 2 — Backup (if enabled): call `bash ./scripts/backup.sh` with timestamped dir
    6. Step 3 — Pull images: `dc pull`
    7. Step 4 — Version check: call `check_version_sync`
    8. Step 5 — Restart: `dc up -d --remove-orphans --no-build`
    9. Step 6 — Health wait: call `wait_for_healthy 60`
    10. Step 7 — Image prune: `docker image prune -f`
    11. Step 8 — Health check (if enabled): call `bash ./scripts/health-check.sh`
    12. Summary banner
  - Notes: All `echo -e` replaced with `log_*` helpers. All `docker compose` replaced with `dc`. Profile flag passed through via `parse_profile_flag` in common.sh. Preserve the `--help` output format.

- [ ] Task 3: Create `scripts/start.sh` — bring up all services
  - File: `scripts/start.sh` (new)
  - Action: Create script that:
    1. Sources `common.sh`, calls `ensure_project_root`, `load_env`
    2. Parses flags: `--profile <name>`, `--help`
    3. Validates env (exit on critical)
    4. Calls `require_docker`
    5. Runs `dc up -d`
    6. Calls `wait_for_healthy 60`
    7. Prints summary
  - Notes: Simple script, ~40-50 lines. Used for bringing up services after a `stop` or first-time start.

- [ ] Task 4: Create `scripts/stop.sh` — halt all services (preserve containers)
  - File: `scripts/stop.sh` (new)
  - Action: Create script that:
    1. Sources `common.sh`, calls `ensure_project_root`, `load_env`
    2. Parses flags: `--profile <name>`, `--help`
    3. Calls `require_docker`
    4. Runs `dc stop`
    5. Prints confirmation
  - Notes: Uses `docker compose stop`, NOT `docker compose down`. Containers preserved for fast restart. `load_env` is needed because `docker compose` requires `.env` to interpolate variables in `docker-compose.yml` even for stop operations. No env validation needed though. ~25-30 lines.

- [ ] Task 5: Create `scripts/restart.sh` — recreate with current config
  - File: `scripts/restart.sh` (new)
  - Action: Create script that:
    1. Sources `common.sh`, calls `ensure_project_root`, `load_env`
    2. Parses flags: `--profile <name>`, `--help`
    3. Validates env (exit on critical)
    4. Calls `require_docker`
    5. Runs `dc up -d --force-recreate`
    6. Calls `wait_for_healthy 60`
    7. Prints summary
  - Notes: Recreates containers with current config/env without pulling new images. Picks up `.env` and `docker-compose.yml` changes. ~40-50 lines.

- [ ] Task 6: Refactor `scripts/health-check.sh` — source common.sh, fix worker bug
  - File: `scripts/health-check.sh` (refactor)
  - Action:
    1. Remove inline color definitions, `validate_env_vars()`, `.env` loading, Docker check — replace with `source common.sh` + calls to `load_env`, `validate_env_vars`, `require_docker`
    2. Fix line 123: change `SERVICES=("postgres" "redis" "n8n" "n8n-worker" "caddy" "qdrant")` to `SERVICES=("postgres" "redis" "n8n" "n8n-worker-1" "n8n-worker-2" "n8n-worker-3" "caddy" "qdrant")`
    3. Replace all `echo -e` patterns with `log_*` helpers
    4. Keep the unique health-check logic: per-service status display, Ollama profile detection, Python runner check, resource usage, volume usage, recent logs
  - Notes: health-check.sh has richer output than the shared `wait_for_healthy` — it displays resource usage, volumes, logs. It should NOT use `wait_for_healthy` for its main loop; it just reports current state.

- [ ] Task 7: Refactor `scripts/backup.sh` — source common.sh
  - File: `scripts/backup.sh` (refactor)
  - Action:
    1. Remove inline color definitions and `.env` loading — replace with `source common.sh` + `ensure_project_root` + `load_env`
    2. Replace all `echo -e` patterns with `log_*` helpers
    3. Keep all backup logic unchanged (pg_dump, volume tar, config tar, manifest)
  - Notes: Minimal change — just dedup the shared code. Backup logic is solid and out of scope for changes.

- [ ] Task 8: Refactor `scripts/restore.sh` — source common.sh, use bulk stop/start
  - File: `scripts/restore.sh` (refactor)
  - Action:
    1. Remove inline color definitions — replace with `source common.sh` + `ensure_project_root` + `load_env`
    2. Replace all `echo -e` patterns with `log_*` helpers
    3. Fix line 54: change `docker compose stop n8n n8n-worker` to `dc stop` (bulk stop all services — handles workers, task runners, everything)
    4. Fix line 105: change `docker compose up -d n8n n8n-worker` to `dc up -d` (bulk start — Docker Compose handles dependency ordering)
    5. Keep all restore logic unchanged (interactive confirmation, pg restore, volume restore, config restore)
  - Notes: Bulk stop/start is simpler and safer than targeting individual services — it ensures task runners are stopped/started alongside their workers. `load_env` added so `dc` can parse compose file variable interpolation.

- [ ] Task 9: Delete `scripts/update.sh`
  - File: `scripts/update.sh` (delete)
  - Action: Remove the file. Its functionality is fully absorbed into the rewritten `deploy.sh`.
  - Notes: Verify no other scripts or docs reference `update.sh` before deleting. Update any references found.

- [ ] Task 10: Update documentation references
  - File: `CLAUDE.md`, `QUICK-REFERENCE.md`, `README.md`, `IMPROVEMENTS.md`, `DEPLOYMENT.md`, `OPERATIONS.md`
  - Action:
    1. In `CLAUDE.md` "Common Commands" section: remove `./scripts/update.sh` reference, add `./scripts/start.sh`, `./scripts/stop.sh`, `./scripts/restart.sh` with descriptions. Update `./scripts/deploy.sh` description to note it replaces the old update.sh.
    2. In `QUICK-REFERENCE.md`: same updates if script commands are listed there.
    3. In `README.md`: update all `update.sh` references (at least 4 occurrences) to reference `deploy.sh` instead, add new scripts.
    4. In `IMPROVEMENTS.md`: update all `update.sh` references (at least 3 occurrences).
    5. Check `DEPLOYMENT.md` and `OPERATIONS.md` for `update.sh` references and update.
    6. **Verify with `grep -r "update.sh" .`** that no stale references remain anywhere in the repo.
  - Notes: Ensure docs stay consistent with the new script landscape. This is the final task specifically so the grep verification catches anything missed.

### Acceptance Criteria

- [ ] AC 1: Given a fresh clone with valid `.env`, when running `./scripts/start.sh`, then all non-profile services start and the script reports healthy status for postgres, redis, n8n, and all 3 workers.
- [ ] AC 2: Given running services, when running `./scripts/stop.sh`, then all containers are stopped (not removed) and `docker compose ps` shows them as exited.
- [ ] AC 3: Given stopped services, when running `./scripts/start.sh`, then all services come up and the script reports healthy status. (`docker compose up -d` may recreate containers if config changed — this is expected behavior.)
- [ ] AC 4: Given running services with a `.env` change, when running `./scripts/restart.sh`, then containers are recreated with the new config and the script reports healthy status.
- [ ] AC 5: Given a clean repo, when running `./scripts/deploy.sh`, then it performs: git pull → backup → docker pull → version check → up → health wait → prune → health check, in order.
- [ ] AC 6: Given running `./scripts/deploy.sh --skip-git --no-backup --no-health-check`, then git pull, backup, and health check steps are skipped.
- [ ] AC 7: Given running `./scripts/start.sh --profile cpu`, then `docker compose --profile cpu up -d` is executed and Ollama CPU service starts alongside the standard stack.
- [ ] AC 8: Given running `./scripts/stop.sh --profile cpu`, then Ollama CPU service is also stopped along with the standard stack.
- [ ] AC 9: Given any script run with `--help`, then usage information is printed and the script exits 0 without performing any actions.
- [ ] AC 10: Given a backup directory, when running `./scripts/restore.sh <dir>`, then it bulk-stops all services, restores data, and bulk-starts all services (not targeting individual services like the old `n8n-worker`).
- [ ] AC 11: Given running `./scripts/health-check.sh`, then it reports individual status for `n8n-worker-1`, `n8n-worker-2`, `n8n-worker-3` (not a single `n8n-worker`).
- [ ] AC 12: Given any script invoked from a different working directory (e.g., `cd /tmp && /path/to/scripts/start.sh`), then `ensure_project_root` resolves the correct project root and the script works normally.
- [ ] AC 13: Given `N8N_VERSION` set such that n8n and runner image tags mismatch, when running `./scripts/deploy.sh`, then `check_version_sync` fails with a clear error and the script exits before restarting services.
- [ ] AC 14: Given `scripts/update.sh` is deleted, then no remaining file in the repo references `update.sh` (verified via grep).
- [ ] AC 15: Given all scripts are written, when running `shellcheck scripts/lib/common.sh scripts/*.sh`, then all scripts pass with zero errors.

## Additional Context

### Dependencies

- `jq` — used by `check_version_sync` for robust JSON parsing of `docker compose config --format json`. Falls back to grep-based approach with a warning if not installed.
- All scripts depend on `scripts/lib/common.sh` being present.
- `deploy.sh` calls `scripts/backup.sh` and `scripts/health-check.sh` as subprocesses.
- `shellcheck` — for linting during development (not a runtime dependency).

### Testing Strategy

**Automated linting:**

0. Run `shellcheck scripts/lib/common.sh scripts/*.sh` — all scripts must pass with zero errors/warnings.

**Manual testing checklist:**

1. Run each script with `--help` — verify usage output
2. Run `start.sh` from project root — verify all services come up, including workers
3. Run `stop.sh` — verify containers stopped but not removed (`docker ps -a` shows Exited)
4. Run `start.sh` again — verify services come back up
5. Run `restart.sh` — verify containers recreated (new container IDs)
6. Run `deploy.sh --skip-git --no-backup --no-health-check` — verify minimal deploy
7. Run `deploy.sh` full pipeline — verify all 8 steps execute
8. Run `start.sh --profile cpu` — verify Ollama starts
9. Run `stop.sh --profile cpu` — verify Ollama stops
10. Run `health-check.sh` — verify all 3 workers listed individually
11. Run `restore.sh <backup-dir>` — verify it bulk stops/starts all services
12. Run any script from `/tmp` using absolute path — verify `ensure_project_root` works
13. Run `grep -r "update.sh" .` — verify no stale references remain

### Notes

- **Risk: common.sh sourcing path resolution.** If `BASH_SOURCE` behavior differs across bash versions, the `ensure_project_root` function could fail. Mitigation: test on bash 4.x and 5.x. The project runs on Linux so this is low risk.
- `CLAUDE.md` documents the worker environment duplication pattern — when changing shared n8n env vars, all 3 worker definitions must be updated. Scripts don't need to worry about this (it's a compose-file concern).
- `N8N_VERSION` controls both n8n and runner image tags — the version check in `check_version_sync` ensures they match before any restart.
- The `dc` function wrapper is preferred over a `$DC_CMD` variable because it correctly handles argument quoting and word splitting.
- **`n8n-import` one-shot service:** This is a one-time import container. `docker compose up -d` skips it if already completed. `restart.sh --force-recreate` may re-trigger it — this is acceptable since the import commands are idempotent (import existing credentials/workflows). Document in `restart.sh --help` output as a known behavior.
- **Profile consistency:** There is no mechanism to remember which `--profile` was used. Users must pass `--profile` consistently across start/stop/restart/deploy. Document this in each script's `--help` output. If a user forgets `--profile` on `stop.sh`, Ollama containers will keep running — this is by Docker Compose design, not a bug.
- **No rollback on deploy failure:** If `deploy.sh` health check fails after restart, the pre-deploy backup exists but no automatic rollback is performed. Users should run `restore.sh` manually. This matches current behavior.
- **Unpinned images:** Caddy (`caddy:latest`), Qdrant (`qdrant/qdrant`), and Ollama (`ollama/ollama:latest`) use unpinned tags. `dc pull` during deploy may update them to new versions. This is a compose-file concern, not a scripts concern — but worth noting.
- **`COMPOSE_PROFILES` env var conflict:** Docker Compose recognizes `COMPOSE_PROFILES` (plural) as an environment variable. The `dc` function uses `--profile` (explicit flag), which is additive with any `COMPOSE_PROFILES` value in `.env`. Unlikely to be an issue unless the user sets both.
- **`jq` dependency:** `check_version_sync` requires `jq` for robust JSON parsing of `docker compose config --format json`. If `jq` is not installed, fall back to the grep-based approach with a warning.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production-ready Docker Compose deployment for n8n (workflow automation) optimized for a 32GB RAM server (~22GB allocated, ~10GB OS headroom). Includes PostgreSQL, Redis, Caddy reverse proxy, Qdrant vector DB, and Ollama for local LLM inference.

## Common Commands

```bash
# Deploy / manage services
docker compose up -d                          # Start all services
docker compose down                           # Stop all services
docker compose ps                             # Check service status
docker compose logs -f [service]              # Tail logs for a service

# Operational scripts
./scripts/health-check.sh                     # Full health check with env validation
./scripts/backup.sh                           # Backup PostgreSQL + n8n data + config
./scripts/restore.sh                          # Restore from backup snapshot
./scripts/update.sh                           # Safe image update (backs up first)
./scripts/deploy.sh                           # Automated deployment with checks

# Ollama profiles (pick one)
docker compose --profile cpu up -d            # CPU-only Ollama
docker compose --profile gpu-nvidia up -d     # NVIDIA GPU Ollama
docker compose --profile gpu-amd up -d        # AMD GPU Ollama

# Database access
docker exec -it postgres psql -U root -d n8n
```

## Architecture

**Service dependency chain:** PostgreSQL + Redis (healthy) → n8n main (healthy) → workers 1-3 → task runners 1-3 + main task runner. Caddy depends on n8n main.

### Services and their roles

| Service | Image | Role |
|---|---|---|
| `postgres` | postgres:16 | Primary database, tuned for 32GB server |
| `redis` | redis:7 | Queue backend (Bull), AOF persistence |
| `n8n` | n8nio/n8n | Main instance: UI, API, webhook handling |
| `n8n-worker-{1,2,3}` | n8nio/n8n | Queue workers executing workflows |
| `n8n-task-runner` | n8nio/runners | Code node executor for main instance |
| `n8n-task-runner-{1,2,3}` | n8nio/runners | Code node executor paired with each worker |
| `caddy` | caddy | Reverse proxy, automatic HTTPS via Let's Encrypt |
| `qdrant` | qdrant/qdrant | Vector database for embeddings |
| `ollama-{cpu,gpu,gpu-amd}` | ollama/ollama | Local LLM inference (profile-activated) |

### Worker + Task Runner pairing

Each worker has a dedicated task runner sidecar. The task runner connects to its parent's broker at port 5679 via `N8N_RUNNERS_TASK_BROKER_URI=http://n8n-worker-N:5679`. The main n8n instance also has its own task runner for webhook/manual Code node executions. All runners must use the same `N8N_VERSION` as n8n.

### Network

Single bridge network `web` (subnet `172.19.0.0/16`). Only Caddy exposes ports 80/443 to the host. Qdrant exposes 6333, Ollama exposes 11434.

## Key Files

- `docker-compose.yml` — All service definitions. Uses YAML anchors (`x-n8n`, `x-ollama`, `x-init-ollama`) for shared config, but workers duplicate their environment blocks (not using the anchor) due to per-worker customization needs.
- `.env.sample` → `.env` — All secrets and configuration. Three values must be changed: `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`, `N8N_RUNNERS_AUTH_TOKEN`.
- `caddy/Caddyfile` — Simple reverse proxy: `{$SUBDOMAIN}.{$DOMAIN_NAME}` → `n8n:5678`.
- `postgres/init/01-create-indexes.sql` — 6 composite indexes on `execution_entity` created at first boot.
- `kubernetes/` — Alternative Kubernetes deployment with KEDA auto-scaling.

## Important Patterns

**Version coupling:** `N8N_VERSION` env var controls both `docker.n8n.io/n8nio/n8n` and `n8nio/runners` image tags. These must always match. The `scripts/update.sh` script handles coordinated updates.

**Worker environment duplication:** Workers 1-3 each have their full environment block inline (not using the `x-n8n` anchor's environment) because they need worker-specific settings like `QUEUE_WORKER_LOCK_DURATION`. When changing shared n8n env vars, you must update them in the `x-n8n` anchor AND in all three worker definitions.

**Execution data is aggressively pruned:** 24-hour retention, max 1000 executions, manual executions not saved. This is intentional for performance.

**Health checks gate startup:** Services use `condition: service_healthy` in `depends_on`, so the full stack starts in order. Health check intervals are 5s with 10 retries.

## Documentation

- `DEPLOYMENT.md` — Full deployment checklist, scaling guide, rollback procedures
- `OPERATIONS.md` — Daily/weekly ops, backup/restore, incident response
- `SECURITY.md` — Security audit, hardening recommendations, compliance notes
- `QUICK-REFERENCE.md` — Command cheat sheet for common operations

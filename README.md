# n8n-deploy

Enterprise-grade Docker Compose deployment for n8n with PostgreSQL, Redis, Caddy, Ollama, and Qdrant.

## Architecture

```
                    ┌─────────────┐
                    │   Caddy     │  (reverse proxy, auto HTTPS)
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐ ┌────▼────┐ ┌─────▼─────┐
        │  n8n Main │ │ Workers │ │  Ollama   │
        │  (UI/API) │ │  (x3)   │ │  (LLM)    │
        └─────┬─────┘ └────┬────┘ └───────────┘
              │            │
        ┌─────▼────────────▼─────┐
        │        Redis           │  (queue backend)
        └────────────────────────┘
              │
        ┌─────▼──────┐     ┌─────────────┐
        │ PostgreSQL │     │   Qdrant    │
        │   (data)   │     │ (vectors)   │
        └────────────┘     └─────────────┘
```

## Services

| Service | Purpose | Memory |
|---------|---------|--------|
| **PostgreSQL 16** | Primary database | 12 GB limit |
| **Redis 7** | Queue backend (AOF persistence) | 1.5 GB limit |
| **n8n Main** | UI and API server | 4 GB limit |
| **n8n Workers** | Execution workers (3 replicas) | 2 GB each |
| **Caddy** | Reverse proxy, auto HTTPS | 512 MB limit |
| **Qdrant** | Vector database for embeddings | 2 GB limit |
| **Ollama** | Local LLM inference | varies |

Optimized for a 32 GB RAM server (~22 GB allocated, ~10 GB headroom).

## 📚 Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete deployment guide and checklist
- **[OPERATIONS.md](OPERATIONS.md)** - Day-to-day operational procedures
- **[SECURITY.md](SECURITY.md)** - Security audit and hardening recommendations
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Command cheat sheet and troubleshooting

## Quick Start

1. **Copy environment template:**
   ```bash
   cp .env.sample .env
   ```

2. **Configure `.env`** with your settings:
   - Database credentials
   - Domain and subdomain
   - Encryption keys
   - Timezone

   See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions.

3. **Start services:**
   ```bash
   docker compose up -d
   ```

4. **Check health:**
   ```bash
   ./scripts/health-check.sh
   ```

5. **Access n8n** at `https://your-subdomain.your-domain.com`

For a complete deployment checklist, see [DEPLOYMENT.md](DEPLOYMENT.md).

## 🛠️ Helper Scripts

Operational scripts in `scripts/` directory:

```bash
# Full deploy pipeline (git pull, backup, image pull, restart, health check)
./scripts/deploy.sh

# Start / stop / restart all services
./scripts/start.sh
./scripts/stop.sh
./scripts/restart.sh

# Check service health and resource usage
./scripts/health-check.sh

# Create backup of database and n8n data
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh backups/<directory>
```

## Common Commands

```bash
# Start (create/pull and run in background)
docker compose up -d

# Stop and remove containers (keep volumes)
docker compose down

# Restart after config changes
docker compose up -d --remove-orphans

# Pull updated images
docker compose pull

# View all logs
docker compose logs -f

# View worker logs only
docker compose logs -f n8n-worker

# Check service status
docker compose ps
```

For more commands and troubleshooting, see [QUICK-REFERENCE.md](QUICK-REFERENCE.md).

## GPU Support (Ollama)

For GPU-accelerated LLM inference:

```bash
# NVIDIA GPU
docker compose --profile gpu-nvidia up -d

# AMD GPU
docker compose --profile gpu-amd up -d
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `POSTGRES_DB` | Database name |
| `POSTGRES_USER` | Database user |
| `POSTGRES_PASSWORD` | Database password |
| `DOMAIN_NAME` | Your domain |
| `SUBDOMAIN` | n8n subdomain |
| `N8N_ENCRYPTION_KEY` | Encryption key for credentials |
| `N8N_USER_MANAGEMENT_JWT_SECRET` | JWT secret |
| `N8N_VERSION` | n8n image tag (default: `latest`) |
| `GENERIC_TIMEZONE` | Timezone (e.g., `UTC`) |

### Execution Data Retention

Default settings:
- 14-day retention
- Max 10,000 executions
- Automatic pruning enabled

## Directory Structure

```
n8n-deploy/
├── docker-compose.yml          # Main orchestration
├── docker-compose.override.yml.example
├── .env.sample                  # Environment template
├── DEPLOYMENT.md               # Deployment guide and checklist
├── OPERATIONS.md               # Daily operations guide
├── SECURITY.md                 # Security recommendations
├── QUICK-REFERENCE.md          # Command cheat sheet
├── scripts/                     # Helper scripts
│   ├── lib/common.sh           # Shared library (colors, logging, helpers)
│   ├── deploy.sh               # Full deploy pipeline
│   ├── start.sh                # Start all services
│   ├── stop.sh                 # Stop all services
│   ├── restart.sh              # Recreate containers
│   ├── health-check.sh         # Service health monitoring
│   ├── backup.sh               # Backup creation
│   └── restore.sh              # Backup restoration
├── caddy/
│   └── Caddyfile               # Reverse proxy config
├── n8n/
│   └── demo-data/              # Sample workflows/credentials
├── postgres/
│   └── init/
│       └── 01-create-indexes.sql  # Performance indexes
```

## 🔒 Security

This deployment includes several security considerations. For a complete security audit and hardening recommendations, see [SECURITY.md](SECURITY.md).

**Quick security wins:**
1. Change all default passwords in `.env`
2. Use strong encryption keys (generate with `openssl rand -hex 32`)
3. Configure firewall to restrict access to ports 80/443 only
4. Enable automatic backups (see `scripts/backup.sh`)
5. Keep images updated regularly (`./scripts/deploy.sh`)

## 📊 Monitoring and Maintenance

**Health Monitoring:**
```bash
./scripts/health-check.sh
```

**Regular Backups:**
```bash
# Manual backup
./scripts/backup.sh

# Automated (add to crontab)
0 2 * * * cd /path/to/n8n-deploy && ./scripts/backup.sh
```

**Updates:**
```bash
./scripts/deploy.sh
```

For complete operational procedures, see [OPERATIONS.md](OPERATIONS.md).

## License

Public Domain (Unlicense)

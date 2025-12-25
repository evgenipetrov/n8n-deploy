# Deployment Checklist

Complete guide for deploying the n8n automation lab from scratch.

## Pre-Deployment Requirements

### Server Requirements

- [ ] **Operating System**: Linux (Ubuntu 22.04 LTS recommended)
- [ ] **RAM**: 32 GB minimum (see scaling guide for other sizes)
- [ ] **Storage**: 100+ GB SSD recommended
- [ ] **CPU**: 4+ cores recommended
- [ ] **Network**: Static IP or DDNS configured
- [ ] **Ports**: 80, 443 available (for Caddy)

### Software Prerequisites

- [ ] Docker Engine 24.0+ installed
- [ ] Docker Compose V2 installed
- [ ] Git installed
- [ ] Text editor (vim, nano, etc.)
- [ ] Optional: `htop` for monitoring

### Domain and DNS

- [ ] Domain name registered
- [ ] DNS A record pointing to server IP
  - Example: `n8n.example.com` → `your.server.ip`
- [ ] DNS propagation verified (`dig n8n.example.com`)

## Deployment Steps

### 1. Clone and Prepare Repository

```bash
# Clone repository
git clone <repository-url> n8n-deploy
cd n8n-deploy

# Verify files
ls -la
# Expected: docker-compose.yml, .env.sample, caddy/, postgres/, etc.
```

- [ ] Repository cloned
- [ ] All files present

### 2. Configure Environment

```bash
# Copy environment template
cp .env.sample .env

# Edit configuration
nano .env  # or vim .env
```

**Required configuration in `.env`:**

- [ ] `POSTGRES_USER` - Set database username (default: `root`)
- [ ] `POSTGRES_PASSWORD` - **CHANGE THIS!** Strong password required
- [ ] `POSTGRES_DB` - Database name (default: `n8n`)
- [ ] `N8N_ENCRYPTION_KEY` - **CHANGE THIS!** Generate with: `openssl rand -hex 32`
- [ ] `N8N_USER_MANAGEMENT_JWT_SECRET` - **CHANGE THIS!** Generate with: `openssl rand -hex 32`
- [ ] `SUBDOMAIN` - Your subdomain (e.g., `n8n`)
- [ ] `DOMAIN_NAME` - Your domain (e.g., `example.com`)
- [ ] `GENERIC_TIMEZONE` - Your timezone (e.g., `America/New_York`, `UTC`)

**Verify configuration:**
```bash
# Check all required variables are set
grep -E "^(POSTGRES_PASSWORD|N8N_ENCRYPTION_KEY|N8N_USER_MANAGEMENT_JWT_SECRET|DOMAIN_NAME)=" .env
```

- [ ] All required variables configured
- [ ] Secrets changed from defaults
- [ ] Domain and timezone set correctly

### 3. Review Docker Compose Configuration

```bash
# Validate compose file
docker compose config

# Review memory allocation (should total ~22GB for 32GB server)
grep -A 3 "memory:" docker-compose.yml
```

- [ ] Compose file validates without errors
- [ ] Memory limits reviewed and appropriate for server

### 4. Choose Ollama Profile (Optional)

Select one based on your hardware:

```bash
# CPU only (default, no GPU)
# No special profile needed

# NVIDIA GPU
export COMPOSE_PROFILES=gpu-nvidia

# AMD GPU (ROCm)
export COMPOSE_PROFILES=gpu-amd
```

- [ ] GPU profile selected (if applicable)
- [ ] GPU drivers installed on host (if using GPU)

### 5. Initial Deployment

```bash
# Pull all images
docker compose pull

# Start services in detached mode
docker compose up -d

# Watch logs during startup
docker compose logs -f
```

**Expected startup sequence:**
1. PostgreSQL starts and initializes
2. Redis starts
3. n8n-import runs (imports demo data)
4. n8n main instance starts
5. n8n workers start (3 replicas)
6. Caddy starts and provisions SSL certificates
7. Qdrant starts
8. Ollama starts (if profile selected)

- [ ] All services started successfully
- [ ] No errors in logs
- [ ] All containers show "healthy" status

### 6. Verify Service Health

```bash
# Run health check script
./scripts/health-check.sh

# Or manually check
docker compose ps
```

**Expected output:**
- All services show `Up` status
- Services with health checks show `healthy`
- No containers in restart loop

- [ ] All core services healthy
- [ ] PostgreSQL accessible
- [ ] Redis accessible
- [ ] n8n accessible

### 7. Access n8n

```bash
# Get your n8n URL
echo "https://${SUBDOMAIN}.${DOMAIN_NAME}"
```

1. Open URL in browser
2. **First-time setup:**
   - Create owner account (email + password)
   - Configure workspace name
   - Complete onboarding

- [ ] n8n UI accessible via HTTPS
- [ ] SSL certificate valid (check padlock icon)
- [ ] Owner account created
- [ ] Can login successfully

### 8. Post-Deployment Verification

```bash
# Test workflow execution
# 1. Create a simple "Schedule Trigger" + "HTTP Request" workflow
# 2. Run manually
# 3. Check execution history

# Verify worker scaling
docker compose logs n8n-worker | grep -i "worker"

# Check database connectivity
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SELECT version();"

# Verify queue is working
docker compose exec redis redis-cli ping
```

- [ ] Can create and save workflows
- [ ] Can execute workflows manually
- [ ] Workers processing jobs
- [ ] Database connected
- [ ] Queue operational

### 9. Configure Monitoring (Optional)

```bash
# Check resource usage
./scripts/health-check.sh

# Setup log rotation (recommended)
docker system prune -f --volumes --filter "until=720h"
```

- [ ] Resource usage within expected ranges
- [ ] Monitoring configured (if desired)

### 10. Create First Backup

```bash
# Create initial backup
./scripts/backup.sh

# Verify backup created
ls -lh backups/
```

- [ ] Backup completed successfully
- [ ] Backup files present and non-zero size
- [ ] Backup manifest readable

## Security Hardening (Recommended)

After successful deployment, implement security measures:

### Essential Security Tasks

- [ ] Review `SECURITY.md` for all recommendations
- [ ] Configure firewall rules (UFW, iptables, etc.)
  ```bash
  # Example with UFW
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw enable
  ```
- [ ] Enable automatic security updates
- [ ] Set up SSH key authentication (disable password auth)
- [ ] Configure fail2ban
- [ ] Review and apply Docker security best practices

### Application Security

- [ ] Enable strong passwords in n8n
- [ ] Configure 2FA for n8n users (if available)
- [ ] Review user permissions
- [ ] Set up Redis password authentication (see `SECURITY.md`)
- [ ] Review Caddy security headers (see `SECURITY.md`)

## Maintenance Setup

### Scheduled Tasks

Add to crontab (`crontab -e`):

```bash
# Daily backup at 2 AM
0 2 * * * cd /path/to/n8n-deploy && ./scripts/backup.sh >> /var/log/n8n-backup.log 2>&1

# Weekly cleanup of old backups (keep 30 days)
0 3 * * 0 find /path/to/n8n-deploy/backups -mtime +30 -delete

# Weekly Docker cleanup
0 4 * * 0 docker system prune -f --volumes --filter "until=720h"
```

- [ ] Backup cron job configured
- [ ] Cleanup tasks scheduled
- [ ] Log rotation configured

### Monitoring and Alerts

- [ ] Set up uptime monitoring (UptimeRobot, StatusCake, etc.)
- [ ] Configure email alerts for failures
- [ ] Document incident response procedures

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker compose logs postgres redis n8n

# Check disk space
df -h

# Check memory
free -h

# Recreate containers
docker compose down
docker compose up -d
```

### SSL Certificate Issues

```bash
# Check Caddy logs
docker compose logs caddy

# Verify DNS
dig ${SUBDOMAIN}.${DOMAIN_NAME}

# Check port accessibility
curl -I http://${SUBDOMAIN}.${DOMAIN_NAME}
```

### Database Connection Errors

```bash
# Verify PostgreSQL is healthy
docker compose ps postgres

# Check credentials match
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "\l"

# Reset database (CAUTION: destroys data)
docker compose down -v
docker compose up -d
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Review PostgreSQL settings
docker compose exec postgres psql -U ${POSTGRES_USER} -c "SHOW all;"

# Optimize database
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "VACUUM ANALYZE;"
```

## Rollback Procedure

If deployment fails:

```bash
# Stop all services
docker compose down

# Restore from backup
./scripts/restore.sh ./backups/<backup-directory>

# Restart services
docker compose up -d
```

## Scaling Guide

### Vertical Scaling (More Resources)

**For 64 GB RAM server:**

Create `docker-compose.override.yml`:
```yaml
services:
  postgres:
    command:
      - "postgres"
      - "-c"
      - "shared_buffers=16GB"
      - "-c"
      - "effective_cache_size=48GB"
    deploy:
      resources:
        limits:
          memory: 24g
        reservations:
          memory: 20g

  n8n:
    deploy:
      resources:
        limits:
          memory: 8g
        reservations:
          memory: 4g

  n8n-worker:
    deploy:
      replicas: 5
      resources:
        limits:
          memory: 3g
        reservations:
          memory: 2g
```

### Horizontal Scaling (More Workers)

```yaml
# In docker-compose.override.yml
services:
  n8n-worker:
    deploy:
      replicas: 5  # Increase from 3
```

## Next Steps

- [ ] Read `OPERATIONS.md` for daily operational procedures
- [ ] Review `SECURITY.md` for security hardening
- [ ] Plan monitoring and observability stack (see roadmap)
- [ ] Set up custom node development environment
- [ ] Configure backup retention policy
- [ ] Document custom workflows and integrations

---

**Deployment Complete! 🎉**

Your n8n automation lab is now running. Access it at:
```
https://${SUBDOMAIN}.${DOMAIN_NAME}
```

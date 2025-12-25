# Operations Guide

Day-to-day operational procedures for managing your n8n automation lab.

## Daily Operations

### Health Monitoring

**Quick Health Check:**
```bash
./scripts/health-check.sh
```

**Manual Checks:**
```bash
# Check all services
docker compose ps

# Check resource usage
docker stats --no-stream

# Check logs for errors
docker compose logs --tail=100 | grep -i error
```

**What to Monitor:**
- Service status (all should be "Up" and "healthy")
- Memory usage (should be below limits)
- CPU usage (spikes are normal, sustained high usage needs investigation)
- Disk usage (PostgreSQL and Redis data growth)
- Error logs (any recurring errors need attention)

### Backup Procedures

**Daily Backup (Automated):**
```bash
# Run backup script
./scripts/backup.sh

# Verify backup completed
ls -lh backups/$(date +%Y-%m-%d-)*
```

**Backup Verification:**
```bash
# Check backup integrity
cd backups/<latest-backup>/
cat MANIFEST.txt

# Test backup (non-production only!)
./scripts/restore.sh backups/<backup-directory>
```

**Backup Retention:**
```bash
# Keep last 30 days of backups
find backups/ -type d -mtime +30 -exec rm -rf {} +

# Keep weekly backups for 90 days (manual archive)
# Manually copy backups to archive directory every Sunday
```

## Weekly Operations

### System Updates

**Update Docker Images:**
```bash
# Automated update with backup
./scripts/update.sh

# Update without backup (not recommended)
./scripts/update.sh --no-backup
```

**Manual Update Process:**
```bash
# 1. Create backup
./scripts/backup.sh

# 2. Pull latest images
docker compose pull

# 3. Recreate containers
docker compose up -d --remove-orphans

# 4. Verify health
./scripts/health-check.sh

# 5. Cleanup old images
docker image prune -f
```

### Database Maintenance

**Optimize Database:**
```bash
# Run VACUUM and ANALYZE
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "VACUUM ANALYZE;"

# Check database size
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "\l+"

# Check table sizes
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "\dt+ execution_entity"
```

**Execution History Cleanup:**
```bash
# Check execution count
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SELECT COUNT(*) FROM execution_entity;"

# Manual cleanup (if automatic pruning isn't working)
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
  DELETE FROM execution_entity
  WHERE \"startedAt\" < NOW() - INTERVAL '14 days'
  AND finished = true;
"
```

### Log Management

**View Logs:**
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f n8n
docker compose logs -f n8n-worker
docker compose logs -f postgres

# With timestamp
docker compose logs -f --timestamps

# Last N lines
docker compose logs --tail=100 n8n
```

**Log Rotation:**
```bash
# Configure log rotation in /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}

# Restart Docker daemon
sudo systemctl restart docker
```

### Performance Monitoring

**Resource Usage:**
```bash
# Real-time stats
docker stats

# Historical usage
docker stats --no-stream

# Check PostgreSQL performance
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
  SELECT query, calls, total_exec_time, mean_exec_time
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 10;
"
```

## Monthly Operations

### Security Audit

**Review Access Logs:**
```bash
# Check Caddy access logs
docker compose logs caddy | grep -v "healthcheck"

# Check for failed login attempts in n8n
docker compose logs n8n | grep -i "login.*failed"
```

**Update Secrets:**
```bash
# Rotate encryption keys (requires data migration - plan carefully)
# See n8n documentation for key rotation procedure

# Update passwords
nano .env
# Change POSTGRES_PASSWORD
# Change N8N_USER_MANAGEMENT_JWT_SECRET

# Recreate services
docker compose up -d --force-recreate
```

**Security Patches:**
```bash
# Update host OS
sudo apt update && sudo apt upgrade -y

# Update Docker
sudo apt install docker-ce docker-ce-cli containerd.io

# Update all images
./scripts/update.sh
```

### Capacity Planning

**Check Growth Trends:**
```bash
# Database size over time
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
  SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}')) as db_size;
"

# Execution history growth
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
  SELECT COUNT(*), DATE(\"startedAt\")
  FROM execution_entity
  GROUP BY DATE(\"startedAt\")
  ORDER BY DATE(\"startedAt\") DESC
  LIMIT 30;
"

# Volume sizes
docker system df -v
```

**Scaling Decisions:**
- If CPU usage consistently >80%: Add more worker replicas
- If memory usage >90%: Increase RAM or reduce memory limits
- If database >50GB: Plan for storage expansion or increase pruning
- If queue backlog growing: Add more workers or optimize workflows

## Common Maintenance Tasks

### Restart Services

**Graceful Restart:**
```bash
# Restart specific service
docker compose restart n8n

# Restart workers only
docker compose restart n8n-worker

# Restart all services
docker compose restart
```

**Hard Restart:**
```bash
# Stop all services
docker compose down

# Start all services
docker compose up -d
```

### Scale Workers

**Increase Worker Count:**
```bash
# Edit docker-compose.override.yml
cat > docker-compose.override.yml <<EOF
services:
  n8n-worker:
    deploy:
      replicas: 5
EOF

# Apply changes
docker compose up -d --scale n8n-worker=5
```

**Decrease Worker Count:**
```bash
docker compose up -d --scale n8n-worker=2
```

### Update Configuration

**Change Environment Variables:**
```bash
# 1. Edit .env
nano .env

# 2. Recreate affected services
docker compose up -d --force-recreate

# 3. Verify changes applied
docker compose exec n8n env | grep N8N_
```

**Update Docker Compose:**
```bash
# 1. Backup current configuration
cp docker-compose.yml docker-compose.yml.backup

# 2. Make changes
nano docker-compose.yml

# 3. Validate syntax
docker compose config

# 4. Apply changes
docker compose up -d --remove-orphans
```

### Manage Ollama Models

**List Installed Models:**
```bash
# For CPU profile
docker compose exec ollama-cpu ollama list

# For GPU profile
docker compose exec ollama-gpu ollama list
```

**Pull New Models:**
```bash
# Pull specific model
docker compose exec ollama-cpu ollama pull codellama

# Pull latest model
docker compose exec ollama-cpu ollama pull llama3.2:latest
```

**Remove Models:**
```bash
docker compose exec ollama-cpu ollama rm <model-name>
```

### Database Operations

**Create Manual Backup:**
```bash
# Full database dump
docker compose exec postgres pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB} > backup.sql

# Specific table
docker compose exec postgres pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB} -t execution_entity > executions.sql
```

**Restore from Backup:**
```bash
# Full restore (DESTRUCTIVE!)
cat backup.sql | docker compose exec -T postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}
```

**Database Console Access:**
```bash
# PostgreSQL shell
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}

# Run single command
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SELECT COUNT(*) FROM execution_entity;"
```

### Redis Operations

**Redis Console:**
```bash
docker compose exec redis redis-cli
```

**Common Redis Commands:**
```bash
# Check queue size
docker compose exec redis redis-cli LLEN bull:jobs:active

# Monitor commands
docker compose exec redis redis-cli MONITOR

# Get info
docker compose exec redis redis-cli INFO

# Flush queue (DESTRUCTIVE!)
docker compose exec redis redis-cli FLUSHALL
```

## Incident Response

### Service Down

**Diagnosis:**
```bash
# Check what's down
docker compose ps

# Check logs
docker compose logs --tail=100 <service-name>

# Check resource constraints
docker stats
df -h
free -h
```

**Recovery:**
```bash
# Restart failed service
docker compose restart <service-name>

# If restart fails, recreate
docker compose up -d --force-recreate <service-name>

# If still failing, check dependencies
docker compose up -d postgres redis
docker compose up -d n8n
```

### High Memory Usage

**Immediate Actions:**
```bash
# Check which container is using memory
docker stats

# Restart high-memory service
docker compose restart <service-name>

# If PostgreSQL is high, run VACUUM
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "VACUUM FULL ANALYZE;"
```

### Disk Space Full

**Quick Cleanup:**
```bash
# Clean Docker artifacts
docker system prune -f --volumes

# Remove old logs
docker compose logs --tail=0

# Clean old backups
find backups/ -mtime +7 -delete

# Check what's using space
du -sh *
docker system df -v
```

### Database Corruption

**Recovery Procedure:**
```bash
# 1. Stop n8n services
docker compose stop n8n n8n-worker

# 2. Backup current state
./scripts/backup.sh

# 3. Try to repair
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "REINDEX DATABASE ${POSTGRES_DB};"

# 4. If repair fails, restore from last good backup
./scripts/restore.sh backups/<last-good-backup>

# 5. Restart services
docker compose up -d
```

### SSL Certificate Renewal Failure

**Manual Renewal:**
```bash
# Check Caddy logs
docker compose logs caddy

# Verify DNS
dig ${SUBDOMAIN}.${DOMAIN_NAME}

# Restart Caddy
docker compose restart caddy

# If still failing, remove and recreate
docker compose stop caddy
docker volume rm n8n-deploy_caddy_data
docker compose up -d caddy
```

## Performance Tuning

### Optimize PostgreSQL

**Analyze Query Performance:**
```bash
# Enable pg_stat_statements
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

# View slow queries
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
  SELECT query, calls, mean_exec_time
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 10;
"
```

**Tune Settings (docker-compose.override.yml):**
```yaml
services:
  postgres:
    command:
      - "postgres"
      - "-c"
      - "shared_buffers=12GB"  # Increase for more caching
      - "-c"
      - "effective_cache_size=28GB"
      - "-c"
      - "work_mem=512MB"  # Increase for complex queries
```

### Optimize n8n Workers

**Adjust Worker Count Based on Workload:**
```yaml
# CPU-intensive workflows: Fewer workers with more memory
services:
  n8n-worker:
    deploy:
      replicas: 2
      resources:
        limits:
          memory: 4g

# Many lightweight workflows: More workers with less memory
services:
  n8n-worker:
    deploy:
      replicas: 5
      resources:
        limits:
          memory: 1.5g
```

## Best Practices

### Change Management

1. **Always backup before changes**
   ```bash
   ./scripts/backup.sh
   ```

2. **Test in override file first**
   ```bash
   # Make changes in docker-compose.override.yml
   # Validate before applying
   docker compose config
   ```

3. **Document changes**
   ```bash
   # Keep change log
   echo "$(date): Changed worker replicas to 5" >> CHANGELOG.md
   ```

### Monitoring Checklist

Daily:
- [ ] Check service health
- [ ] Review error logs
- [ ] Monitor disk usage

Weekly:
- [ ] Verify backups
- [ ] Check for updates
- [ ] Review resource trends

Monthly:
- [ ] Security audit
- [ ] Performance review
- [ ] Capacity planning

### Emergency Contacts

Document your escalation procedures:
- Who to contact for issues
- Emergency backup administrator
- Cloud provider support (if applicable)
- n8n community forums: https://community.n8n.io

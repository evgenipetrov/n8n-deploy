# Quick Reference Guide

Essential commands and troubleshooting for n8n deployment.

## 📋 Cheat Sheet

### Service Management

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# Restart a service
docker compose restart <service>

# View all services
docker compose ps

# View logs
docker compose logs -f

# View logs for specific service
docker compose logs -f n8n
```

### Health Checks

```bash
# Quick health check
./scripts/health-check.sh

# Check specific service
docker compose ps <service>

# Real-time resource usage
docker stats
```

### Backups

```bash
# Create backup
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh backups/<directory>

# List backups
ls -lh backups/
```

### Updates

```bash
# Update all images
./scripts/update.sh

# Pull latest images only
docker compose pull

# Apply updates
docker compose up -d
```

## 🔧 Common Tasks

### Change Environment Variables

```bash
# 1. Edit .env
nano .env

# 2. Recreate services
docker compose up -d --force-recreate

# 3. Verify
./scripts/health-check.sh
```

### Scale Workers

```bash
# Scale to 5 workers
docker compose up -d --scale n8n-worker=5

# Scale to 2 workers
docker compose up -d --scale n8n-worker=2
```

### Access Database

```bash
# PostgreSQL shell
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

# Run SQL command
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM execution_entity;"
```

### Access Redis

```bash
# Redis CLI
docker compose exec redis redis-cli

# Check queue size
docker compose exec redis redis-cli LLEN bull:jobs:active
```

### Manage Ollama Models

```bash
# List models (CPU)
docker compose exec ollama-cpu ollama list

# Pull new model
docker compose exec ollama-cpu ollama pull <model-name>

# Remove model
docker compose exec ollama-cpu ollama rm <model-name>
```

## 🚨 Emergency Procedures

### Service Won't Start

```bash
# 1. Check logs
docker compose logs --tail=50 <service>

# 2. Check dependencies
docker compose ps postgres redis

# 3. Restart
docker compose restart <service>

# 4. If still failing, recreate
docker compose up -d --force-recreate <service>
```

### Database Issues

```bash
# Check PostgreSQL status
docker compose ps postgres
docker compose logs postgres

# Verify connection
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "\l"

# Repair database
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "VACUUM ANALYZE;"
```

### SSL Certificate Problems

```bash
# Check Caddy logs
docker compose logs caddy

# Verify DNS
dig ${SUBDOMAIN}.${DOMAIN_NAME}

# Restart Caddy
docker compose restart caddy

# Reset certificates (if needed)
docker compose stop caddy
docker volume rm n8n-deploy_caddy_data
docker compose up -d caddy
```

### Out of Disk Space

```bash
# Quick cleanup
docker system prune -f --volumes

# Check usage
df -h
docker system df -v

# Remove old backups
find backups/ -mtime +7 -delete

# Clean old logs
docker compose logs --tail=0
```

### High Memory Usage

```bash
# Check what's using memory
docker stats

# Restart high-memory service
docker compose restart <service>

# Optimize database
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "VACUUM FULL;"
```

### Completely Reset

**⚠️ WARNING: This will DELETE ALL DATA!**

```bash
# 1. Backup first!
./scripts/backup.sh

# 2. Stop and remove everything
docker compose down -v

# 3. Clean system
docker system prune -af --volumes

# 4. Start fresh
docker compose up -d
```

## 📊 Monitoring Commands

### Resource Usage

```bash
# CPU and Memory
docker stats --no-stream

# Disk usage
df -h
docker system df -v

# Network
docker compose exec n8n netstat -tunlp
```

### Database Stats

```bash
# Database size
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));"

# Execution count
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM execution_entity;"

# Table sizes
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt+"
```

### Queue Status

```bash
# Active jobs
docker compose exec redis redis-cli LLEN bull:jobs:active

# Waiting jobs
docker compose exec redis redis-cli LLEN bull:jobs:waiting

# Failed jobs
docker compose exec redis redis-cli LLEN bull:jobs:failed
```

## 🔍 Logs and Debugging

### View Logs

```bash
# All services, follow
docker compose logs -f

# Specific service
docker compose logs -f n8n

# Last 100 lines
docker compose logs --tail=100 n8n

# With timestamps
docker compose logs -f --timestamps n8n

# Search logs
docker compose logs n8n | grep -i error
```

### Debug Mode

```bash
# Enable debug logging for n8n
# Add to .env:
# N8N_LOG_LEVEL=debug

# Recreate service
docker compose up -d --force-recreate n8n
```

## 🎯 Performance Tips

### Optimize PostgreSQL

```bash
# Analyze database
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "VACUUM ANALYZE;"

# Reindex
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "REINDEX DATABASE $POSTGRES_DB;"
```

### Clean Old Executions

```bash
# Delete executions older than 7 days
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "
  DELETE FROM execution_entity
  WHERE \"startedAt\" < NOW() - INTERVAL '7 days'
  AND finished = true;
"

# Run VACUUM after large delete
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "VACUUM ANALYZE execution_entity;"
```

### Optimize Redis

```bash
# Check memory usage
docker compose exec redis redis-cli INFO memory

# Check keyspace
docker compose exec redis redis-cli INFO keyspace

# If memory is high, flush old data (CAREFUL!)
docker compose exec redis redis-cli FLUSHDB
```

## 📝 File Locations

### Configuration Files

```
.env                     - Environment variables
docker-compose.yml       - Main orchestration
docker-compose.override.yml - Custom overrides
caddy/Caddyfile         - Reverse proxy config
postgres/init/          - Database initialization scripts
```

### Data Volumes

```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect n8n-deploy_n8n_data

# Backup volume
docker run --rm -v n8n-deploy_n8n_data:/source:ro -v $(pwd):/backup alpine tar czf /backup/n8n_data.tar.gz -C /source .
```

### Helper Scripts

```
scripts/health-check.sh  - Check service health
scripts/backup.sh        - Create backup
scripts/restore.sh       - Restore from backup
scripts/update.sh        - Update images
```

## 🔗 Useful URLs

### Local Services

```bash
# n8n UI
https://${SUBDOMAIN}.${DOMAIN_NAME}

# Qdrant dashboard
http://localhost:6333/dashboard

# Ollama API
http://localhost:11434/api/tags
```

### Documentation

- n8n Docs: https://docs.n8n.io
- Docker Docs: https://docs.docker.com
- PostgreSQL Docs: https://www.postgresql.org/docs/
- Caddy Docs: https://caddyserver.com/docs

## 💡 Pro Tips

1. **Always backup before major changes**
   ```bash
   ./scripts/backup.sh
   ```

2. **Use docker-compose.override.yml for custom config**
   - Keeps main docker-compose.yml clean
   - Not tracked in git
   - Automatically merged

3. **Monitor disk space regularly**
   ```bash
   df -h
   ```

4. **Set up automated backups**
   ```bash
   # Add to crontab
   0 2 * * * cd /path/to/n8n-deploy && ./scripts/backup.sh
   ```

5. **Review logs weekly**
   ```bash
   docker compose logs --since 7d | grep -i error
   ```

6. **Keep execution history clean**
   - Automatic pruning is enabled (14 days)
   - Adjust in .env if needed: `EXECUTIONS_DATA_MAX_AGE`

7. **Use health-check.sh regularly**
   ```bash
   ./scripts/health-check.sh
   ```

## 📞 Getting Help

- Check `OPERATIONS.md` for detailed procedures
- Check `SECURITY.md` for security issues
- Check `DEPLOYMENT.md` for deployment problems
- n8n Community: https://community.n8n.io
- Docker Forums: https://forums.docker.com

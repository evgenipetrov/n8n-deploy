#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Restore Script
# =============================================================================
# Restores PostgreSQL database, n8n data, and configuration from backup
#
# Usage: ./scripts/restore.sh <backup-directory>
# Example: ./scripts/restore.sh ./backups/2025-12-25-120000
#
# WARNING: This will OVERWRITE existing data!
# =============================================================================

set -euo pipefail

# Check arguments
if [ $# -eq 0 ]; then
    echo "ERROR: Backup directory required"
    echo "Usage: $0 <backup-directory>"
    exit 1
fi

BACKUP_DIR="$1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verify backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}ERROR: Backup directory not found: $BACKUP_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}n8n Deployment Restore${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will OVERWRITE all existing data!${NC}"
echo -e "Backup location: ${BLUE}$BACKUP_DIR${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Stop services
echo -e "${BLUE}Stopping n8n services...${NC}"
docker compose stop n8n n8n-worker
echo -e "${GREEN}✓${NC} Services stopped"

# Find backup files
POSTGRES_BACKUP=$(find "$BACKUP_DIR" -name "postgres_*.sql.gz" | head -n 1)
N8N_DATA_BACKUP=$(find "$BACKUP_DIR" -name "n8n_data_*.tar.gz" | head -n 1)
CONFIG_BACKUP=$(find "$BACKUP_DIR" -name "config_*.tar.gz" | head -n 1)

# Restore PostgreSQL
if [ -n "$POSTGRES_BACKUP" ]; then
    echo ""
    echo -e "${BLUE}Restoring PostgreSQL database...${NC}"
    gunzip -c "$POSTGRES_BACKUP" | docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null
    echo -e "${GREEN}✓${NC} PostgreSQL restored from: $(basename "$POSTGRES_BACKUP")"
else
    echo -e "${YELLOW}⚠${NC} No PostgreSQL backup found, skipping..."
fi

# Restore n8n data volume
if [ -n "$N8N_DATA_BACKUP" ]; then
    echo ""
    echo -e "${BLUE}Restoring n8n data volume...${NC}"
    docker run --rm \
        -v n8n-deploy_n8n_data:/target \
        -v "$(realpath "$BACKUP_DIR")":/backup:ro \
        alpine \
        sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar xzf /backup/$(basename "$N8N_DATA_BACKUP") -C /target"
    echo -e "${GREEN}✓${NC} n8n data restored from: $(basename "$N8N_DATA_BACKUP")"
else
    echo -e "${YELLOW}⚠${NC} No n8n data backup found, skipping..."
fi

# Restore configuration files
if [ -n "$CONFIG_BACKUP" ]; then
    echo ""
    echo -e "${BLUE}Restoring configuration files...${NC}"
    echo -e "${YELLOW}⚠${NC} Manual review recommended for .env and docker-compose.yml"
    read -p "Restore configuration files? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        tar xzf "$CONFIG_BACKUP" -C .
        echo -e "${GREEN}✓${NC} Configuration restored from: $(basename "$CONFIG_BACKUP")"
    else
        echo -e "${YELLOW}⊙${NC} Configuration restore skipped"
    fi
else
    echo -e "${YELLOW}⚠${NC} No configuration backup found, skipping..."
fi

# Restart services
echo ""
echo -e "${BLUE}Starting n8n services...${NC}"
docker compose up -d n8n n8n-worker
echo -e "${GREEN}✓${NC} Services started"

# Wait for health checks
echo ""
echo -e "${BLUE}Waiting for services to become healthy...${NC}"
sleep 5

# Check service health
SERVICES=("postgres" "redis" "n8n")
ALL_HEALTHY=true

for service in "${SERVICES[@]}"; do
    HEALTH=$(docker compose ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")
    if [[ "$HEALTH" == "healthy" ]]; then
        echo -e "  ${GREEN}✓${NC} $service is healthy"
    else
        echo -e "  ${YELLOW}⊙${NC} $service health: $HEALTH"
        ALL_HEALTHY=false
    fi
done

echo ""
echo -e "${BLUE}==============================================================================${NC}"
if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}Restore complete! All services are healthy.${NC}"
else
    echo -e "${YELLOW}Restore complete! Some services may still be starting.${NC}"
    echo -e "Run ${BLUE}./scripts/health-check.sh${NC} to verify status."
fi
echo -e "${BLUE}==============================================================================${NC}"

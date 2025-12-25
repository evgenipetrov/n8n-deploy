#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Backup Script
# =============================================================================
# Creates backups of PostgreSQL database, n8n data, and configuration
#
# Usage: ./scripts/backup.sh [backup-directory]
# Default backup location: ./backups/YYYY-MM-DD-HHMMSS
# =============================================================================

set -euo pipefail

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "ERROR: .env file not found"
    exit 1
fi

# Configuration
BACKUP_DIR="${1:-./backups/$(date +%Y-%m-%d-%H%M%S)}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}n8n Deployment Backup${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓${NC} Backup directory: $BACKUP_DIR"

# Backup PostgreSQL
echo ""
echo -e "${BLUE}Backing up PostgreSQL database...${NC}"
docker compose exec -T postgres pg_dump \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --clean \
    --if-exists \
    > "$BACKUP_DIR/postgres_${TIMESTAMP}.sql"

# Compress the SQL dump
gzip "$BACKUP_DIR/postgres_${TIMESTAMP}.sql"
echo -e "${GREEN}✓${NC} PostgreSQL backup: postgres_${TIMESTAMP}.sql.gz"

# Backup n8n data volume
echo ""
echo -e "${BLUE}Backing up n8n data volume...${NC}"
docker run --rm \
    -v n8n-deploy_n8n_data:/source:ro \
    -v "$(pwd)/$BACKUP_DIR":/backup \
    alpine \
    tar czf "/backup/n8n_data_${TIMESTAMP}.tar.gz" -C /source .
echo -e "${GREEN}✓${NC} n8n data backup: n8n_data_${TIMESTAMP}.tar.gz"

# Backup configuration files
echo ""
echo -e "${BLUE}Backing up configuration files...${NC}"
tar czf "$BACKUP_DIR/config_${TIMESTAMP}.tar.gz" \
    .env \
    docker-compose.yml \
    caddy/Caddyfile \
    postgres/init/ \
    2>/dev/null || true
echo -e "${GREEN}✓${NC} Configuration backup: config_${TIMESTAMP}.tar.gz"

# Backup workflows and credentials separately (if n8n-import demo data exists)
if [ -d "n8n/demo-data" ]; then
    echo ""
    echo -e "${BLUE}Backing up demo data...${NC}"
    tar czf "$BACKUP_DIR/demo_data_${TIMESTAMP}.tar.gz" n8n/demo-data/
    echo -e "${GREEN}✓${NC} Demo data backup: demo_data_${TIMESTAMP}.tar.gz"
fi

# Create backup manifest
echo ""
echo -e "${BLUE}Creating backup manifest...${NC}"
cat > "$BACKUP_DIR/MANIFEST.txt" <<EOF
n8n Deployment Backup Manifest
================================
Backup Date: $(date)
Backup Location: $BACKUP_DIR

Contents:
---------
$(ls -lh "$BACKUP_DIR" | tail -n +2)

Backup Instructions:
-------------------
To restore this backup:

1. PostgreSQL Database:
   gunzip postgres_${TIMESTAMP}.sql.gz
   cat postgres_${TIMESTAMP}.sql | docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

2. n8n Data Volume:
   docker run --rm -v n8n-deploy_n8n_data:/target -v \$(pwd)/$BACKUP_DIR:/backup alpine \\
     sh -c "rm -rf /target/* && tar xzf /backup/n8n_data_${TIMESTAMP}.tar.gz -C /target"

3. Configuration Files:
   tar xzf config_${TIMESTAMP}.tar.gz

Environment:
-----------
POSTGRES_DB: $POSTGRES_DB
POSTGRES_USER: $POSTGRES_USER
N8N_HOST: ${SUBDOMAIN}.${DOMAIN_NAME}
GENERIC_TIMEZONE: $GENERIC_TIMEZONE

Notes:
------
- Ensure the same encryption keys are used when restoring
- Verify Docker volumes exist before restoring
- Stop n8n services before restoring data
EOF

echo -e "${GREEN}✓${NC} Manifest created: MANIFEST.txt"

# Calculate total backup size
echo ""
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${GREEN}Backup complete!${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "Total backup size: ${GREEN}$TOTAL_SIZE${NC}"
echo -e "Location: ${GREEN}$BACKUP_DIR${NC}"
echo ""
echo "To restore, see: $BACKUP_DIR/MANIFEST.txt"

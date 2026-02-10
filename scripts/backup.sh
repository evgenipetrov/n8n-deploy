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

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_project_root
load_env

# Configuration
BACKUP_DIR="${1:-./backups/$(date +%Y-%m-%d-%H%M%S)}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log_header "n8n Deployment Backup"

# Create backup directory
mkdir -p "$BACKUP_DIR"
log_success "Backup directory: $BACKUP_DIR"

# Backup PostgreSQL
echo ""
log_info "Backing up PostgreSQL database..."
docker compose exec -T postgres pg_dump \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --clean \
    --if-exists \
    > "$BACKUP_DIR/postgres_${TIMESTAMP}.sql"

# Compress the SQL dump
gzip "$BACKUP_DIR/postgres_${TIMESTAMP}.sql"
log_success "PostgreSQL backup: postgres_${TIMESTAMP}.sql.gz"

# Backup n8n data volume
echo ""
log_info "Backing up n8n data volume..."
docker run --rm \
    -v n8n-deploy_n8n_data:/source:ro \
    -v "$(pwd)/$BACKUP_DIR":/backup \
    alpine \
    tar czf "/backup/n8n_data_${TIMESTAMP}.tar.gz" -C /source .
log_success "n8n data backup: n8n_data_${TIMESTAMP}.tar.gz"

# Backup configuration files
echo ""
log_info "Backing up configuration files..."
tar czf "$BACKUP_DIR/config_${TIMESTAMP}.tar.gz" \
    .env \
    docker-compose.yml \
    caddy/Caddyfile \
    postgres/init/ \
    2>/dev/null || true
log_success "Configuration backup: config_${TIMESTAMP}.tar.gz"

# Backup workflows and credentials separately (if n8n-import demo data exists)
if [[ -d "n8n/demo-data" ]]; then
    echo ""
    log_info "Backing up demo data..."
    tar czf "$BACKUP_DIR/demo_data_${TIMESTAMP}.tar.gz" n8n/demo-data/
    log_success "Demo data backup: demo_data_${TIMESTAMP}.tar.gz"
fi

# Create backup manifest
echo ""
log_info "Creating backup manifest..."
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

log_success "Manifest created: MANIFEST.txt"

# Calculate total backup size
echo ""
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log_header "Backup complete!"
echo -e "Total backup size: ${GREEN}$TOTAL_SIZE${NC}"
echo -e "Location: ${GREEN}$BACKUP_DIR${NC}"
echo ""
echo "To restore, see: $BACKUP_DIR/MANIFEST.txt"

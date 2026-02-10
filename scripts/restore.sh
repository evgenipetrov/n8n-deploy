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

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_project_root
load_env

# Check arguments
if [[ $# -eq 0 ]]; then
    log_error "Backup directory required"
    echo "Usage: $0 <backup-directory>"
    exit 1
fi

BACKUP_DIR="$1"

# Verify backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

log_header "n8n Deployment Restore"

echo -e "${YELLOW}WARNING: This will OVERWRITE all existing data!${NC}"
echo -e "Backup location: ${BLUE}$BACKUP_DIR${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Stop all services (bulk stop — handles workers, task runners, everything)
log_info "Stopping all services..."
dc stop
log_success "Services stopped"

# Find backup files
POSTGRES_BACKUP=$(find "$BACKUP_DIR" -name "postgres_*.sql.gz" | head -n 1)
N8N_DATA_BACKUP=$(find "$BACKUP_DIR" -name "n8n_data_*.tar.gz" | head -n 1)
CONFIG_BACKUP=$(find "$BACKUP_DIR" -name "config_*.tar.gz" | head -n 1)

# Need postgres running for restore
log_info "Starting postgres for restore..."
dc start postgres
sleep 5

# Restore PostgreSQL
if [[ -n "$POSTGRES_BACKUP" ]]; then
    echo ""
    log_info "Restoring PostgreSQL database..."
    gunzip -c "$POSTGRES_BACKUP" | docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null
    log_success "PostgreSQL restored from: $(basename "$POSTGRES_BACKUP")"
else
    log_warn "No PostgreSQL backup found, skipping..."
fi

# Restore n8n data volume
if [[ -n "$N8N_DATA_BACKUP" ]]; then
    echo ""
    log_info "Restoring n8n data volume..."
    docker run --rm \
        -v n8n-deploy_n8n_data:/target \
        -v "$(realpath "$BACKUP_DIR")":/backup:ro \
        alpine \
        sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar xzf /backup/$(basename "$N8N_DATA_BACKUP") -C /target"
    log_success "n8n data restored from: $(basename "$N8N_DATA_BACKUP")"
else
    log_warn "No n8n data backup found, skipping..."
fi

# Restore configuration files
if [[ -n "$CONFIG_BACKUP" ]]; then
    echo ""
    log_info "Restoring configuration files..."
    log_warn "Manual review recommended for .env and docker-compose.yml"
    read -p "Restore configuration files? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        tar xzf "$CONFIG_BACKUP" -C .
        log_success "Configuration restored from: $(basename "$CONFIG_BACKUP")"
    else
        log_warn "Configuration restore skipped"
    fi
else
    log_warn "No configuration backup found, skipping..."
fi

# Start all services (bulk start — Docker Compose handles dependency ordering)
echo ""
log_info "Starting all services..."
dc up -d
log_success "Services started"

# Wait for health checks
echo ""
if wait_for_healthy 60; then
    log_header "Restore complete! All services are healthy."
else
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${YELLOW}Restore complete! Some services may still be starting.${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""
    echo -e "Run ${CYAN}./scripts/health-check.sh${NC} to verify status."
fi

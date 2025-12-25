#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Update Script
# =============================================================================
# Safely updates all Docker images and restarts services with zero downtime
#
# Usage: ./scripts/update.sh [--backup] [--no-backup]
# Default: Creates backup before updating
# =============================================================================

set -euo pipefail

# Parse arguments
CREATE_BACKUP=true
if [ "${1:-}" = "--no-backup" ]; then
    CREATE_BACKUP=false
elif [ "${1:-}" = "--backup" ]; then
    CREATE_BACKUP=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}n8n Deployment Update${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Create backup before update
if [ "$CREATE_BACKUP" = true ]; then
    echo -e "${BLUE}Creating backup before update...${NC}"
    if [ -f "./scripts/backup.sh" ]; then
        bash ./scripts/backup.sh "./backups/pre-update-$(date +%Y-%m-%d-%H%M%S)"
        echo -e "${GREEN}✓${NC} Backup created"
    else
        echo -e "${YELLOW}⚠${NC} Backup script not found, skipping backup"
    fi
    echo ""
fi

# Pull latest images
echo -e "${BLUE}Pulling latest Docker images...${NC}"
docker compose pull
echo -e "${GREEN}✓${NC} Images updated"
echo ""

# Check for image updates
echo -e "${BLUE}Checking for updates...${NC}"
UPDATED_IMAGES=$(docker compose images --quiet | xargs docker inspect --format='{{.RepoDigests}}' | sort -u | wc -l)
echo -e "${GREEN}✓${NC} Found $UPDATED_IMAGES unique images"
echo ""

# Recreate services with new images
echo -e "${BLUE}Recreating services...${NC}"
docker compose up -d --remove-orphans --no-build
echo -e "${GREEN}✓${NC} Services recreated"
echo ""

# Wait for services to be healthy
echo -e "${BLUE}Waiting for services to become healthy...${NC}"
sleep 10

# Check service health
SERVICES=("postgres" "redis" "n8n")
ALL_HEALTHY=true

for service in "${SERVICES[@]}"; do
    MAX_RETRIES=30
    RETRY=0

    while [ $RETRY -lt $MAX_RETRIES ]; do
        HEALTH=$(docker compose ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")

        if [[ "$HEALTH" == "healthy" ]]; then
            echo -e "  ${GREEN}✓${NC} $service is healthy"
            break
        elif [[ "$HEALTH" == "starting" ]]; then
            echo -e "  ${YELLOW}⊙${NC} $service is starting... ($RETRY/$MAX_RETRIES)"
            sleep 2
            RETRY=$((RETRY + 1))
        else
            echo -e "  ${RED}✗${NC} $service health: $HEALTH"
            ALL_HEALTHY=false
            break
        fi
    done

    if [ $RETRY -eq $MAX_RETRIES ]; then
        echo -e "  ${RED}✗${NC} $service failed to become healthy"
        ALL_HEALTHY=false
    fi
done

# Cleanup old images
echo ""
echo -e "${BLUE}Cleaning up old images...${NC}"
docker image prune -f >/dev/null 2>&1
echo -e "${GREEN}✓${NC} Old images removed"

echo ""
echo -e "${BLUE}==============================================================================${NC}"
if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}Update complete! All services are healthy.${NC}"
else
    echo -e "${YELLOW}Update complete! Some services may have issues.${NC}"
    echo -e "Run ${BLUE}./scripts/health-check.sh${NC} to verify status."
    echo -e "Run ${BLUE}docker compose logs -f${NC} to view logs."
fi
echo -e "${BLUE}==============================================================================${NC}"

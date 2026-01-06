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
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Environment Variable Validation Function
# =============================================================================
validate_env_vars() {
    local missing_vars=()
    local weak_vars=()
    local has_errors=false

    # Critical variables that must be set
    local critical_vars=(
        "N8N_ENCRYPTION_KEY"
        "N8N_USER_MANAGEMENT_JWT_SECRET"
        "N8N_RUNNERS_AUTH_TOKEN"
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "POSTGRES_DB"
    )

    # Important variables that should be set
    local important_vars=(
        "DOMAIN_NAME"
        "SUBDOMAIN"
        "GENERIC_TIMEZONE"
    )

    echo -e "${BLUE}Validating environment variables...${NC}"
    echo ""

    # Check critical variables
    for var in "${critical_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
            has_errors=true
        elif [ "${!var}" = "change_me" ] || [ "${!var}" = "changeme" ]; then
            weak_vars+=("$var")
            has_errors=true
        fi
    done

    # Check important variables
    for var in "${important_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo -e "  ${YELLOW}⚠${NC} $var is not set (recommended)"
        fi
    done

    # Report critical issues
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo -e "${RED}✗ Critical variables missing:${NC}"
        for var in "${missing_vars[@]}"; do
            echo -e "  ${RED}•${NC} $var"
        done
        echo ""
    fi

    if [ ${#weak_vars[@]} -gt 0 ]; then
        echo -e "${RED}✗ Security issue - default values detected:${NC}"
        for var in "${weak_vars[@]}"; do
            echo -e "  ${RED}•${NC} $var is set to 'change_me' (INSECURE!)"
        done
        echo ""
    fi

    # Report status
    if [ "$has_errors" = true ]; then
        echo -e "${RED}Environment validation failed!${NC}"
        echo -e ""
        echo -e "Please update your .env file with proper values:"
        echo -e "  ${CYAN}nano .env${NC}"
        echo -e ""
        echo -e "Reference: .env.sample for required variables"
        return 1
    else
        echo -e "${GREEN}✓${NC} All critical environment variables are set"
        echo ""
        return 0
    fi
}

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}n8n Deployment Update${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Load environment variables and validate
if [ -f ".env" ]; then
    set -a
    source .env
    set +a

    if ! validate_env_vars; then
        exit 1
    fi
else
    echo -e "${RED}✗ .env file not found${NC}"
    echo -e "Please create a .env file (copy from .env.sample)"
    exit 1
fi

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

# Verify version synchronization between n8n and task runner
echo -e "${BLUE}Verifying version synchronization...${NC}"
N8N_IMAGE=$(docker compose config | grep -A 1 "^  n8n:" | grep "image:" | awk '{print $2}')
RUNNER_IMAGE=$(docker compose config | grep -A 1 "^  n8n-task-runner:" | grep "image:" | awk '{print $2}')

N8N_VERSION=$(echo "$N8N_IMAGE" | cut -d: -f2)
RUNNER_VERSION=$(echo "$RUNNER_IMAGE" | cut -d: -f2)

if [ "$N8N_VERSION" != "$RUNNER_VERSION" ]; then
    echo -e "${RED}✗${NC} Version mismatch detected!"
    echo -e "   ${YELLOW}n8n version:${NC} $N8N_VERSION"
    echo -e "   ${YELLOW}Task runner version:${NC} $RUNNER_VERSION"
    echo -e ""
    echo -e "${RED}ERROR: n8n and task runner versions MUST match for compatibility.${NC}"
    echo -e "Please check your .env file and ensure N8N_VERSION is set correctly."
    exit 1
fi

echo -e "${GREEN}✓${NC} n8n and task runner versions match: $N8N_VERSION"
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

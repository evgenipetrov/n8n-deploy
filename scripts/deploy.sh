#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Script
# =============================================================================
# Complete deployment workflow: git pull, backup, update images, restart
#
# Usage: ./scripts/deploy.sh [--no-backup] [--skip-git] [--no-health-check]
# Default: Full deployment with all steps
# =============================================================================

set -euo pipefail

# Parse arguments
CREATE_BACKUP=true
PULL_GIT=true
RUN_HEALTH_CHECK=true

for arg in "$@"; do
    case $arg in
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        --skip-git)
            PULL_GIT=false
            shift
            ;;
        --no-health-check)
            RUN_HEALTH_CHECK=false
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-backup         Skip backup creation"
            echo "  --skip-git          Skip git pull"
            echo "  --no-health-check   Skip post-deployment health check"
            echo "  --help              Show this help message"
            exit 0
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}n8n Deployment Script${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}✗ docker-compose.yml not found${NC}"
    echo -e "Please run this script from the project root directory"
    exit 1
fi

# =============================================================================
# Step 1: Git Pull (if enabled)
# =============================================================================
if [ "$PULL_GIT" = true ]; then
    echo -e "${BLUE}Step 1: Pulling latest changes from Git${NC}"

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        echo -e "${YELLOW}⚠${NC} Not a git repository, skipping git pull"
    else
        # Check for uncommitted changes
        if [ -n "$(git status --porcelain)" ]; then
            echo -e "${YELLOW}⚠${NC} Warning: You have uncommitted changes:"
            git status --short
            echo ""
            read -p "Continue with deployment? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${RED}✗${NC} Deployment cancelled"
                exit 1
            fi
        fi

        # Store current commit
        BEFORE_COMMIT=$(git rev-parse --short HEAD)
        BEFORE_BRANCH=$(git rev-parse --abbrev-ref HEAD)

        # Pull latest changes
        echo -e "Pulling from ${CYAN}$BEFORE_BRANCH${NC}..."
        if git pull origin "$BEFORE_BRANCH"; then
            AFTER_COMMIT=$(git rev-parse --short HEAD)

            if [ "$BEFORE_COMMIT" = "$AFTER_COMMIT" ]; then
                echo -e "${GREEN}✓${NC} Already up to date (${CYAN}$AFTER_COMMIT${NC})"
            else
                echo -e "${GREEN}✓${NC} Updated from ${CYAN}$BEFORE_COMMIT${NC} to ${CYAN}$AFTER_COMMIT${NC}"
                echo ""
                echo -e "${BLUE}Changes:${NC}"
                git log --oneline --graph "$BEFORE_COMMIT..$AFTER_COMMIT"
            fi
        else
            echo -e "${RED}✗${NC} Git pull failed"
            exit 1
        fi
    fi
    echo ""
else
    echo -e "${YELLOW}⊙${NC} Skipping git pull"
    echo ""
fi

# =============================================================================
# Step 2: Backup (if enabled)
# =============================================================================
if [ "$CREATE_BACKUP" = true ]; then
    echo -e "${BLUE}Step 2: Creating pre-deployment backup${NC}"

    if [ -f "./scripts/backup.sh" ]; then
        BACKUP_DIR="./backups/pre-deploy-$(date +%Y-%m-%d-%H%M%S)"
        bash ./scripts/backup.sh "$BACKUP_DIR"
        echo -e "${GREEN}✓${NC} Backup created at ${CYAN}$BACKUP_DIR${NC}"
    else
        echo -e "${YELLOW}⚠${NC} Backup script not found, skipping backup"
    fi
    echo ""
else
    echo -e "${YELLOW}⊙${NC} Skipping backup"
    echo ""
fi

# =============================================================================
# Step 3: Pull Latest Docker Images
# =============================================================================
echo -e "${BLUE}Step 3: Pulling latest Docker images${NC}"
docker compose pull
echo -e "${GREEN}✓${NC} Docker images updated"
echo ""

# =============================================================================
# Step 4: Version Verification
# =============================================================================
echo -e "${BLUE}Step 4: Verifying version synchronization${NC}"
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

echo -e "${GREEN}✓${NC} n8n and task runner versions match: ${CYAN}$N8N_VERSION${NC}"
echo ""

# =============================================================================
# Step 5: Restart Services
# =============================================================================
echo -e "${BLUE}Step 5: Restarting services with new configuration${NC}"
docker compose up -d --remove-orphans --no-build
echo -e "${GREEN}✓${NC} Services restarted"
echo ""

# =============================================================================
# Step 6: Wait for Services to Start
# =============================================================================
echo -e "${BLUE}Step 6: Waiting for services to become healthy${NC}"
echo -e "This may take 30-60 seconds..."
echo ""

# Wait a bit for services to start
sleep 10

# Check service health
SERVICES=("postgres" "redis" "n8n")
ALL_HEALTHY=true
MAX_WAIT=60
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    ALL_READY=true

    for service in "${SERVICES[@]}"; do
        HEALTH=$(docker compose ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")

        if [[ "$HEALTH" != "healthy" ]]; then
            ALL_READY=false
            echo -e "  ${YELLOW}⊙${NC} Waiting for $service to be healthy... (${ELAPSED}s)"
            break
        fi
    done

    if [ "$ALL_READY" = true ]; then
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""
for service in "${SERVICES[@]}"; do
    HEALTH=$(docker compose ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")

    if [[ "$HEALTH" == "healthy" ]]; then
        echo -e "  ${GREEN}✓${NC} $service is healthy"
    elif [[ "$HEALTH" == "starting" ]]; then
        echo -e "  ${YELLOW}⊙${NC} $service is still starting"
        ALL_HEALTHY=false
    else
        echo -e "  ${RED}✗${NC} $service health: $HEALTH"
        ALL_HEALTHY=false
    fi
done
echo ""

# =============================================================================
# Step 7: Cleanup Old Images
# =============================================================================
echo -e "${BLUE}Step 7: Cleaning up old Docker images${NC}"
docker image prune -f >/dev/null 2>&1
echo -e "${GREEN}✓${NC} Old images removed"
echo ""

# =============================================================================
# Step 8: Health Check (if enabled)
# =============================================================================
if [ "$RUN_HEALTH_CHECK" = true ]; then
    echo -e "${BLUE}Step 8: Running post-deployment health check${NC}"
    echo ""

    if [ -f "./scripts/health-check.sh" ]; then
        bash ./scripts/health-check.sh
    else
        echo -e "${YELLOW}⚠${NC} Health check script not found"
    fi
else
    echo -e "${YELLOW}⊙${NC} Skipping health check"
    echo ""
fi

# =============================================================================
# Deployment Summary
# =============================================================================
echo ""
echo -e "${BLUE}==============================================================================${NC}"
if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}✓ Deployment Complete!${NC}"
    echo -e ""
    echo -e "All services are running and healthy"
    if [ "$PULL_GIT" = true ] && [ -n "${AFTER_COMMIT:-}" ] && [ "$BEFORE_COMMIT" != "${AFTER_COMMIT:-}" ]; then
        echo -e "Deployed version: ${CYAN}${AFTER_COMMIT}${NC}"
    fi
    echo -e "n8n version: ${CYAN}$N8N_VERSION${NC}"
else
    echo -e "${YELLOW}⚠ Deployment Complete (with warnings)${NC}"
    echo -e ""
    echo -e "Some services may still be starting up."
    echo -e "Run ${CYAN}./scripts/health-check.sh${NC} in a few minutes to verify."
fi
echo -e "${BLUE}==============================================================================${NC}"

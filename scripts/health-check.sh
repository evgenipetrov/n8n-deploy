#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Health Check Script
# =============================================================================
# Checks the health status of all services in the n8n deployment
#
# Usage: ./scripts/health-check.sh
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Environment Variable Validation Function
# =============================================================================
validate_env_vars() {
    local missing_vars=()
    local weak_vars=()
    local warning_count=0

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

    # Check critical variables
    for var in "${critical_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        elif [ "${!var}" = "change_me" ] || [ "${!var}" = "changeme" ]; then
            weak_vars+=("$var")
        fi
    done

    # Check important variables
    for var in "${important_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            warning_count=$((warning_count + 1))
        fi
    done

    # Return status: 0 = all good, 1 = warnings, 2 = critical issues
    if [ ${#missing_vars[@]} -gt 0 ] || [ ${#weak_vars[@]} -gt 0 ]; then
        return 2
    elif [ $warning_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}n8n Deployment Health Check${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Load and validate environment variables
if [ -f ".env" ]; then
    set -a
    source .env 2>/dev/null
    set +a

    validate_env_vars
    ENV_STATUS=$?

    if [ $ENV_STATUS -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Environment variables validated"
    elif [ $ENV_STATUS -eq 1 ]; then
        echo -e "${YELLOW}⚠${NC} Environment has warnings (non-critical)"
    else
        echo -e "${RED}✗${NC} Environment validation failed (critical)"
    fi
else
    echo -e "${RED}✗${NC} .env file not found"
fi
echo ""

# Check if Docker is running
if ! docker info &>/dev/null; then
    echo -e "${RED}✗ Docker is not running${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"

# Check if compose file exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}✗ docker-compose.yml not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ docker-compose.yml found${NC}"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠ .env file not found (using .env.sample for reference)${NC}"
else
    echo -e "${GREEN}✓ .env file found${NC}"
fi

echo ""
echo -e "${BLUE}Service Health Status:${NC}"
echo ""

# Get list of running containers
SERVICES=("postgres" "redis" "n8n" "n8n-worker" "caddy" "qdrant")

for service in "${SERVICES[@]}"; do
    # Check if container exists
    if docker compose ps -q "$service" &>/dev/null; then
        # Get container status
        STATUS=$(docker compose ps "$service" --format "{{.Status}}")
        HEALTH=$(docker compose ps "$service" --format "{{.Health}}")

        if [[ "$STATUS" == *"Up"* ]]; then
            if [[ "$HEALTH" == "healthy" ]]; then
                echo -e "  ${GREEN}✓${NC} $service: ${GREEN}UP${NC} (${GREEN}healthy${NC})"
            elif [[ "$HEALTH" == "starting" ]]; then
                echo -e "  ${YELLOW}⊙${NC} $service: ${GREEN}UP${NC} (${YELLOW}starting${NC})"
            elif [[ -z "$HEALTH" ]]; then
                echo -e "  ${YELLOW}⊙${NC} $service: ${GREEN}UP${NC} (${YELLOW}no healthcheck${NC})"
            else
                echo -e "  ${RED}✗${NC} $service: ${GREEN}UP${NC} (${RED}$HEALTH${NC})"
            fi
        else
            echo -e "  ${RED}✗${NC} $service: ${RED}DOWN${NC} ($STATUS)"
        fi
    else
        echo -e "  ${RED}✗${NC} $service: ${RED}NOT RUNNING${NC}"
    fi
done

# Check for Ollama (profile-based)
if docker compose ps -q "ollama-cpu" &>/dev/null || \
   docker compose ps -q "ollama-gpu" &>/dev/null || \
   docker compose ps -q "ollama-gpu-amd" &>/dev/null; then
    OLLAMA_SERVICE=$(docker compose ps --format "{{.Service}}" | grep "ollama-" | grep -v "pull" | head -n 1)
    if [ -n "$OLLAMA_SERVICE" ]; then
        STATUS=$(docker compose ps "$OLLAMA_SERVICE" --format "{{.Status}}")
        if [[ "$STATUS" == *"Up"* ]]; then
            echo -e "  ${GREEN}✓${NC} $OLLAMA_SERVICE: ${GREEN}UP${NC} (${YELLOW}no healthcheck${NC})"
        else
            echo -e "  ${RED}✗${NC} $OLLAMA_SERVICE: ${RED}DOWN${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}⊙${NC} ollama: ${YELLOW}NOT DEPLOYED${NC} (use --profile cpu/gpu-nvidia/gpu-amd)"
fi

# Check Python Runner Status (n8n v2)
echo ""
echo -e "${BLUE}Python Runner Status (n8n v2):${NC}"
PYTHON_ENABLED=$(docker exec n8n printenv N8N_NATIVE_PYTHON_RUNNER 2>/dev/null || echo "not set")
if [ "$PYTHON_ENABLED" = "true" ]; then
    echo -e "  ${GREEN}✓${NC} Native Python runner enabled"
else
    echo -e "  ${YELLOW}⚠${NC} Native Python runner not enabled (set N8N_NATIVE_PYTHON_RUNNER=true)"
fi

echo ""
echo -e "${BLUE}Resource Usage:${NC}"
echo ""

# Display resource usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
    $(docker compose ps -q) 2>/dev/null | grep -v "^CONTAINER" | while read line; do
    echo "  $line"
done

echo ""
echo -e "${BLUE}Volume Usage:${NC}"
echo ""

# Display volume sizes
docker volume ls --format "{{.Name}}" | grep "n8n-deploy" | while read volume; do
    SIZE=$(docker system df -v | grep "$volume" | awk '{print $3}')
    if [ -n "$SIZE" ]; then
        echo -e "  $volume: ${SIZE}"
    fi
done

echo ""
echo -e "${BLUE}Recent Logs (last 10 lines):${NC}"
echo ""

# Show recent errors from all services
docker compose logs --tail=10 --no-color 2>&1 | tail -20

echo ""
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${GREEN}Health check complete!${NC}"
echo -e "${BLUE}==============================================================================${NC}"

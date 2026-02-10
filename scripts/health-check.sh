#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Health Check Script
# =============================================================================
# Checks the health status of all services in the n8n deployment.
# Reports: env validation, service health, resource usage, volume usage, logs.
#
# Usage: ./scripts/health-check.sh
# =============================================================================

set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_project_root
load_env

log_header "n8n Deployment Health Check"

# Validate environment
validate_env_vars
env_status=$?
if [[ $env_status -eq 0 ]]; then
    log_success "Environment variables validated"
elif [[ $env_status -eq 1 ]]; then
    log_warn "Environment has warnings (non-critical)"
else
    log_error "Environment validation failed (critical)"
fi
echo ""

# Check Docker
require_docker
log_success "Docker is running"

# Check compose file
if [[ ! -f "docker-compose.yml" ]]; then
    log_error "docker-compose.yml not found"
    exit 1
fi
log_success "docker-compose.yml found"

# Check .env
if [[ ! -f ".env" ]]; then
    log_warn ".env file not found (using .env.sample for reference)"
else
    log_success ".env file found"
fi

echo ""
log_info "Service Health Status:"
echo ""

# Get list of running containers
SERVICES=("postgres" "redis" "n8n" "n8n-worker-1" "n8n-worker-2" "n8n-worker-3" "caddy" "qdrant")

for service in "${SERVICES[@]}"; do
    if dc ps -q "$service" &>/dev/null; then
        STATUS=$(dc ps "$service" --format "{{.Status}}")
        HEALTH=$(dc ps "$service" --format "{{.Health}}")

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

# Check task runners (no healthcheck, just up/down)
RUNNERS=("n8n-task-runner" "n8n-task-runner-1" "n8n-task-runner-2" "n8n-task-runner-3")
for runner in "${RUNNERS[@]}"; do
    if dc ps -q "$runner" &>/dev/null; then
        STATUS=$(dc ps "$runner" --format "{{.Status}}")
        if [[ "$STATUS" == *"Up"* ]]; then
            echo -e "  ${GREEN}✓${NC} $runner: ${GREEN}UP${NC}"
        else
            echo -e "  ${RED}✗${NC} $runner: ${RED}DOWN${NC} ($STATUS)"
        fi
    fi
done

# Check for Ollama (profile-based)
if dc ps -q "ollama-cpu" &>/dev/null || \
   dc ps -q "ollama-gpu" &>/dev/null || \
   dc ps -q "ollama-gpu-amd" &>/dev/null; then
    OLLAMA_SERVICE=$(dc ps --format "{{.Service}}" | grep "ollama-" | grep -v "pull" | head -n 1)
    if [[ -n "$OLLAMA_SERVICE" ]]; then
        STATUS=$(dc ps "$OLLAMA_SERVICE" --format "{{.Status}}")
        if [[ "$STATUS" == *"Up"* ]]; then
            log_success "$OLLAMA_SERVICE: ${GREEN}UP${NC} (${YELLOW}no healthcheck${NC})"
        else
            log_error "$OLLAMA_SERVICE: ${RED}DOWN${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}⊙${NC} ollama: ${YELLOW}NOT DEPLOYED${NC} (use --profile cpu/gpu-nvidia/gpu-amd)"
fi

# Check Python Runner Status
echo ""
log_info "Python Runner Status:"
PYTHON_ENABLED=$(docker exec n8n printenv N8N_NATIVE_PYTHON_RUNNER 2>/dev/null || echo "not set")
if [[ "$PYTHON_ENABLED" == "true" ]]; then
    log_success "Native Python runner enabled"
else
    log_warn "Native Python runner not enabled (set N8N_NATIVE_PYTHON_RUNNER=true)"
fi

echo ""
log_info "Resource Usage:"
echo ""

# Display resource usage
CONTAINER_IDS=$(dc ps -q 2>/dev/null)
# shellcheck disable=SC2086
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
    $CONTAINER_IDS 2>/dev/null | while IFS= read -r line; do
    echo "  $line"
done

echo ""
log_info "Volume Usage:"
echo ""

# Display volume sizes
docker volume ls --format "{{.Name}}" | grep "n8n-deploy" | while IFS= read -r volume; do
    SIZE=$(docker system df -v 2>/dev/null | grep "$volume" | awk '{print $3}')
    if [[ -n "$SIZE" ]]; then
        echo -e "  $volume: ${SIZE}"
    fi
done

echo ""
log_info "Recent Logs (last 10 lines):"
echo ""

# Show recent logs from all services
dc logs --tail=10 --no-color 2>&1 | tail -20

echo ""
log_header "Health check complete!"

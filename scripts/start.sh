#!/usr/bin/env bash
# =============================================================================
# n8n Start Script
# =============================================================================
# Brings up all services. Use after stop.sh or for first-time start.
#
# Usage: ./scripts/start.sh [options]
#   --profile <name>    Activate Docker Compose profile (cpu, gpu-nvidia, gpu-amd)
#   --help              Show this help message
#
# Note: Pass --profile consistently across start/stop/restart/deploy
# to ensure profile-activated services (e.g., Ollama) are included.
# =============================================================================

set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_project_root
load_env

# Parse arguments
parse_profile_flag "$@"
set -- "${REMAINING_ARGS[@]}"

for arg in "$@"; do
    case "$arg" in
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Brings up all n8n services."
            echo ""
            echo "Options:"
            echo "  --profile <name>    Activate Compose profile (cpu, gpu-nvidia, gpu-amd)"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $arg"
            echo "Run $0 --help for usage"
            exit 1
            ;;
    esac
done

# Validate environment
validate_env_vars
env_status=$?
if [[ $env_status -eq 2 ]]; then
    exit 1
fi

require_docker

log_header "n8n Start"

log_info "Starting all services..."
dc up -d
log_success "Services started"
echo ""

if wait_for_healthy 60; then
    log_header "All services are running and healthy"
else
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${YELLOW}⚠ Some services may still be starting up${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""
    echo -e "Run ${CYAN}./scripts/health-check.sh${NC} in a few minutes to verify."
fi

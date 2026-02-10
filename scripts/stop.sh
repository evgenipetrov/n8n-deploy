#!/usr/bin/env bash
# =============================================================================
# n8n Stop Script
# =============================================================================
# Stops all services, preserving containers for fast restart.
# Uses 'docker compose stop' (NOT 'down') — containers are not removed.
#
# Usage: ./scripts/stop.sh [options]
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
            echo "Stops all n8n services (containers preserved for fast restart)."
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

require_docker

log_header "n8n Stop"

log_info "Stopping all services..."
dc stop
log_success "All services stopped"
echo ""
echo -e "Containers are preserved. Run ${CYAN}./scripts/start.sh${NC} to bring them back up."

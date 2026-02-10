#!/usr/bin/env bash
# =============================================================================
# n8n Deployment Script
# =============================================================================
# Full deployment pipeline: git pull, backup, pull images, version check,
# restart services, health wait, image prune, health check.
#
# Usage: ./scripts/deploy.sh [options]
#   --skip-git          Skip git pull
#   --no-backup         Skip pre-deployment backup
#   --no-health-check   Skip post-deployment health check
#   --profile <name>    Activate Docker Compose profile (cpu, gpu-nvidia, gpu-amd)
#   --help              Show this help message
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

PULL_GIT=true
CREATE_BACKUP=true
RUN_HEALTH_CHECK=true

for arg in "$@"; do
    case "$arg" in
        --skip-git)
            PULL_GIT=false
            ;;
        --no-backup)
            CREATE_BACKUP=false
            ;;
        --no-health-check)
            RUN_HEALTH_CHECK=false
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Full deployment pipeline: git pull, backup, pull images, version check,"
            echo "restart services, health wait, image prune, health check."
            echo ""
            echo "Options:"
            echo "  --skip-git          Skip git pull"
            echo "  --no-backup         Skip pre-deployment backup"
            echo "  --no-health-check   Skip post-deployment health check"
            echo "  --profile <name>    Activate Compose profile (cpu, gpu-nvidia, gpu-amd)"
            echo "  --help              Show this help message"
            echo ""
            echo "Note: Pass --profile consistently across start/stop/restart/deploy"
            echo "to ensure profile-activated services (e.g., Ollama) are included."
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

log_header "n8n Deployment"

# =============================================================================
# Step 1: Git Pull
# =============================================================================
if [[ "$PULL_GIT" == true ]]; then
    log_info "Step 1: Pulling latest changes from Git"

    if [[ ! -d ".git" ]]; then
        log_warn "Not a git repository, skipping git pull"
    else
        if [[ -n "$(git status --porcelain)" ]]; then
            log_warn "You have uncommitted changes:"
            git status --short
            echo ""
            read -p "Continue with deployment? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Deployment cancelled"
                exit 1
            fi
        fi

        BEFORE_COMMIT=$(git rev-parse --short HEAD)
        BEFORE_BRANCH=$(git rev-parse --abbrev-ref HEAD)

        echo -e "Pulling from ${CYAN}$BEFORE_BRANCH${NC}..."
        if git pull origin "$BEFORE_BRANCH"; then
            AFTER_COMMIT=$(git rev-parse --short HEAD)
            if [[ "$BEFORE_COMMIT" == "$AFTER_COMMIT" ]]; then
                log_success "Already up to date (${CYAN}$AFTER_COMMIT${NC})"
            else
                log_success "Updated from ${CYAN}$BEFORE_COMMIT${NC} to ${CYAN}$AFTER_COMMIT${NC}"
                echo ""
                log_info "Changes:"
                git log --oneline --graph "$BEFORE_COMMIT..$AFTER_COMMIT"
            fi
        else
            log_error "Git pull failed"
            exit 1
        fi
    fi
    echo ""
else
    log_warn "Skipping git pull"
    echo ""
fi

# =============================================================================
# Step 2: Backup
# =============================================================================
if [[ "$CREATE_BACKUP" == true ]]; then
    log_info "Step 2: Creating pre-deployment backup"

    if [[ -f "./scripts/backup.sh" ]]; then
        BACKUP_DIR="./backups/pre-deploy-$(date +%Y-%m-%d-%H%M%S)"
        bash ./scripts/backup.sh "$BACKUP_DIR"
        log_success "Backup created at ${CYAN}$BACKUP_DIR${NC}"
    else
        log_warn "Backup script not found, skipping backup"
    fi
    echo ""
else
    log_warn "Skipping backup"
    echo ""
fi

# =============================================================================
# Step 3: Pull Latest Docker Images
# =============================================================================
log_info "Step 3: Pulling latest Docker images"
dc pull
log_success "Docker images updated"
echo ""

# =============================================================================
# Step 4: Version Check
# =============================================================================
log_info "Step 4: Verifying version synchronization"
check_version_sync

# =============================================================================
# Step 5: Restart Services
# =============================================================================
log_info "Step 5: Restarting services with new images"
dc up -d --remove-orphans --no-build
log_success "Services restarted"
echo ""

# =============================================================================
# Step 6: Health Wait
# =============================================================================
log_info "Step 6: Waiting for services to become healthy"
ALL_HEALTHY=true
if ! wait_for_healthy 60; then
    ALL_HEALTHY=false
fi

# =============================================================================
# Step 7: Image Prune
# =============================================================================
log_info "Step 7: Cleaning up old Docker images"
docker image prune -f >/dev/null 2>&1
log_success "Old images removed"
echo ""

# =============================================================================
# Step 8: Health Check
# =============================================================================
if [[ "$RUN_HEALTH_CHECK" == true ]]; then
    log_info "Step 8: Running post-deployment health check"
    echo ""

    if [[ -f "./scripts/health-check.sh" ]]; then
        bash ./scripts/health-check.sh || true
    else
        log_warn "Health check script not found"
    fi
else
    log_warn "Skipping health check"
    echo ""
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
if [[ "$ALL_HEALTHY" == true ]]; then
    log_header "Deployment Complete!"
    echo -e "All services are running and healthy"
else
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${YELLOW}⚠ Deployment Complete (with warnings)${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""
    echo -e "Some services may still be starting up."
    echo -e "Run ${CYAN}./scripts/health-check.sh${NC} in a few minutes to verify."
fi

if [[ "$PULL_GIT" == true ]] && [[ -n "${AFTER_COMMIT:-}" ]] && [[ "${BEFORE_COMMIT:-}" != "${AFTER_COMMIT:-}" ]]; then
    echo -e "Deployed version: ${CYAN}${AFTER_COMMIT}${NC}"
fi

#!/usr/bin/env bash
# =============================================================================
# Shared library for n8n deployment scripts
# =============================================================================
# Sourced by all scripts in scripts/ — never executed directly.
# Provides: colors, logging, env loading, validation, health checks,
#           version sync, Docker checks, profile handling, compose wrapper.
# =============================================================================

# Guard against double-sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

set -euo pipefail

# =============================================================================
# Colors
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Logging Helpers
# =============================================================================
log_info()    { echo -e "${BLUE}$*${NC}"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
log_error()   { echo -e "${RED}✗${NC} $*"; }

log_header() {
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""
}

# =============================================================================
# Project Root Resolution
# =============================================================================
# Resolves the project root from the calling script's location via BASH_SOURCE.
# Walks up from scripts/lib/ (or scripts/) to find the directory containing
# docker-compose.yml, then cd's there.
# =============================================================================
ensure_project_root() {
    local source_dir
    # BASH_SOURCE[1] is the caller of this function (the script that sourced common.sh)
    # Fall back to BASH_SOURCE[0] (this file) if [1] isn't set
    if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
        source_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    else
        source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    # Walk up to find docker-compose.yml
    local dir="$source_dir"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/docker-compose.yml" ]]; then
            cd "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    log_error "Could not find docker-compose.yml in any parent directory of $source_dir"
    exit 1
}

# =============================================================================
# Environment Loading
# =============================================================================
load_env() {
    if [[ ! -f ".env" ]]; then
        log_error ".env file not found"
        echo -e "Please create a .env file (copy from .env.sample)"
        exit 1
    fi
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
}

# =============================================================================
# Environment Validation
# =============================================================================
# Returns: 0 = all good, 1 = warnings only, 2 = critical issues
#
# Critical (return 2): N8N_ENCRYPTION_KEY, N8N_USER_MANAGEMENT_JWT_SECRET,
#   N8N_RUNNERS_AUTH_TOKEN, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
#   missing or set to change_me/changeme.
#
# Warnings (return 1): DOMAIN_NAME, SUBDOMAIN, GENERIC_TIMEZONE missing.
# =============================================================================
validate_env_vars() {
    local missing_vars=()
    local weak_vars=()
    local has_critical=false
    local has_warnings=false

    local critical_vars=(
        "N8N_ENCRYPTION_KEY"
        "N8N_USER_MANAGEMENT_JWT_SECRET"
        "N8N_RUNNERS_AUTH_TOKEN"
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "POSTGRES_DB"
    )

    local important_vars=(
        "DOMAIN_NAME"
        "SUBDOMAIN"
        "GENERIC_TIMEZONE"
    )

    log_info "Validating environment variables..."
    echo ""

    # Check critical variables
    for var in "${critical_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
            has_critical=true
        elif [[ "${!var}" == "change_me" || "${!var}" == "changeme" ]]; then
            weak_vars+=("$var")
            has_critical=true
        fi
    done

    # Check important variables
    for var in "${important_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_warn "$var is not set (recommended)"
            has_warnings=true
        fi
    done

    # Report critical issues
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Critical variables missing:"
        for var in "${missing_vars[@]}"; do
            echo -e "  ${RED}•${NC} $var"
        done
        echo ""
    fi

    if [[ ${#weak_vars[@]} -gt 0 ]]; then
        log_error "Security issue - default values detected:"
        for var in "${weak_vars[@]}"; do
            echo -e "  ${RED}•${NC} $var is set to 'change_me' (INSECURE!)"
        done
        echo ""
    fi

    # Return status
    if [[ "$has_critical" == true ]]; then
        log_error "Environment validation failed!"
        echo ""
        echo -e "Please update your .env file with proper values:"
        echo -e "  ${CYAN}nano .env${NC}"
        echo ""
        echo -e "Reference: .env.sample for required variables"
        return 2
    elif [[ "$has_warnings" == true ]]; then
        return 1
    else
        log_success "All critical environment variables are set"
        echo ""
        return 0
    fi
}

# =============================================================================
# Docker Check
# =============================================================================
require_docker() {
    if ! docker info &>/dev/null; then
        log_error "Docker is not running"
        exit 1
    fi
}

# =============================================================================
# Health Wait Loop
# =============================================================================
# Polls all services with healthchecks using a global timeout.
# Usage: wait_for_healthy [timeout_seconds]
# Returns: 0 if all healthy, 1 if timeout
# =============================================================================
wait_for_healthy() {
    local timeout="${1:-60}"
    local interval=5
    local elapsed=0
    local services=("postgres" "redis" "n8n" "n8n-worker-1" "n8n-worker-2" "n8n-worker-3")
    local all_healthy=true

    log_info "Waiting for services to become healthy..."
    echo -e "This may take up to ${timeout}s..."
    echo ""

    # Initial wait for containers to start
    sleep 10
    elapsed=10

    while [[ $elapsed -lt $timeout ]]; do
        local all_ready=true

        for service in "${services[@]}"; do
            local health
            health=$(dc ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")

            if [[ "$health" != "healthy" ]]; then
                all_ready=false
                break
            fi
        done

        if [[ "$all_ready" == true ]]; then
            break
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    # Final status report
    echo ""
    all_healthy=true
    for service in "${services[@]}"; do
        local health
        health=$(dc ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")

        if [[ "$health" == "healthy" ]]; then
            log_success "$service is healthy"
        elif [[ "$health" == "starting" ]]; then
            log_warn "$service is still starting"
            all_healthy=false
        else
            log_error "$service health: $health"
            all_healthy=false
        fi
    done
    echo ""

    if [[ "$all_healthy" == true ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Version Sync Check
# =============================================================================
# Verifies n8n and task runner image versions match.
# Uses jq for robust JSON parsing, falls back to grep if jq unavailable.
# =============================================================================
check_version_sync() {
    log_info "Verifying version synchronization..."

    local n8n_version runner_version

    if command -v jq &>/dev/null; then
        # Robust: parse JSON output
        local config_json
        config_json=$(dc config --format json)
        n8n_version=$(echo "$config_json" | jq -r '.services.n8n.image' | cut -d: -f2)
        runner_version=$(echo "$config_json" | jq -r '.services."n8n-task-runner".image' | cut -d: -f2)
    else
        # Fallback: grep-based (less reliable)
        log_warn "jq not installed — using fallback version check (install jq for reliability)"
        n8n_version=$(dc config | grep -E "^\s+image:.*n8nio/n8n:" | head -1 | sed 's/.*://')
        runner_version=$(dc config | grep -E "^\s+image:.*n8nio/runners:" | head -1 | sed 's/.*://')
    fi

    if [[ "$n8n_version" != "$runner_version" ]]; then
        log_error "Version mismatch detected!"
        echo -e "   ${YELLOW}n8n version:${NC} $n8n_version"
        echo -e "   ${YELLOW}Task runner version:${NC} $runner_version"
        echo ""
        log_error "n8n and task runner versions MUST match for compatibility."
        echo -e "Please check your .env file and ensure N8N_VERSION is set correctly."
        exit 1
    fi

    log_success "n8n and task runner versions match: ${CYAN}$n8n_version${NC}"
    echo ""
}

# =============================================================================
# Profile Flag Parsing
# =============================================================================
# Parses --profile <name> from arguments.
# Sets global COMPOSE_PROFILE and REMAINING_ARGS.
# Usage: parse_profile_flag "$@"; set -- "${REMAINING_ARGS[@]}"
# =============================================================================
COMPOSE_PROFILE=""
REMAINING_ARGS=()

parse_profile_flag() {
    COMPOSE_PROFILE=""
    REMAINING_ARGS=()
    local valid_profiles=("cpu" "gpu-nvidia" "gpu-amd")

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                if [[ $# -lt 2 ]]; then
                    log_error "--profile requires a value (cpu, gpu-nvidia, gpu-amd)"
                    exit 1
                fi
                local profile="$2"
                local valid=false
                for p in "${valid_profiles[@]}"; do
                    if [[ "$p" == "$profile" ]]; then
                        valid=true
                        break
                    fi
                done
                if [[ "$valid" == false ]]; then
                    log_error "Invalid profile: $profile"
                    echo "Valid profiles: ${valid_profiles[*]}"
                    exit 1
                fi
                COMPOSE_PROFILE="$profile"
                shift 2
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# Docker Compose Wrapper
# =============================================================================
# Wraps docker compose with optional --profile flag.
# All scripts should call dc instead of docker compose directly.
# =============================================================================
dc() {
    # shellcheck disable=SC2086
    docker compose ${COMPOSE_PROFILE:+--profile "$COMPOSE_PROFILE"} "$@"
}

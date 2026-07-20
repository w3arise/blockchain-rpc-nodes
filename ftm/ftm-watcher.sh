#!/bin/sh

# FTM Health Watcher Script
# Monitors FTM container logs for dirty state errors and automatically triggers healing

set -euo pipefail

# Configuration from environment variables with defaults
DIRTY_STATE_PATTERN="${DIRTY_STATE_PATTERN:-dirty state}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-ftm}"
COMPOSE_FILE="/app/docker-compose.yml"
HEAL_SCRIPT="/app/ftm-heal.sh"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check if a container is running (exact name match)
is_container_running() {
    local container_name=$1
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$" 2>/dev/null || return 1
}

# Check if any heal container is running (pattern match for containers containing "ftm-heal")
is_heal_container_running() {
    docker ps --format '{{.Names}}' | grep -q "ftm-heal" 2>/dev/null || return 1
}

# Check if any FTM-related container is running
any_ftm_container_running() {
    is_container_running "ftm" || is_heal_container_running
}

# Main monitoring loop
main() {
    log "FTM Health Watcher started"
    log "Dirty state pattern: '${DIRTY_STATE_PATTERN}'"
    log "Check interval: ${CHECK_INTERVAL} seconds"
    
    while true; do
        # Check if ftm container exists and is running
        if is_container_running "ftm"; then
            # Get recent logs (last 10 lines to avoid checking too much)
            log_output=$(docker logs --tail 10 ftm 2>&1 || true)
            
            # Check for dirty state pattern
            if echo "$log_output" | grep -qi "${DIRTY_STATE_PATTERN}"; then
                log "WARNING: Dirty state detected in ftm logs!"
                log "Pattern found: '${DIRTY_STATE_PATTERN}'"
                
                # Check if heal is already running
                if is_heal_container_running; then
                    log "Heal container already running, waiting for it to complete..."
                    while is_heal_container_running; do
                        sleep 5
                    done
                    log "Heal container has finished"
                fi
                
                # Stop and remove ftm service to clear logs (only the ftm service, not the watcher)
                log "Stopping ftm service..."
                cd /app
                docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" stop ftm || docker stop ftm || true

                log "Removing ftm container to clear logs..."
                docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" rm -f ftm || docker rm -f ftm || true
                
                # Wait a moment for container to be removed
                sleep 2
                
                # Run heal script
                log "Running heal script..."
                if [ -f "$HEAL_SCRIPT" ]; then
                    sh "$HEAL_SCRIPT"
                else
                    log "ERROR: Heal script not found at $HEAL_SCRIPT"
                    log "Exiting watcher due to missing heal script"
                    exit 1
                fi
                
                # Wait for heal container to finish
                log "Waiting for heal container to complete..."
                while is_heal_container_running; do
                    sleep 5
                done
                
                # Verify no FTM containers are running
                if ! any_ftm_container_running; then
                    log "No FTM containers running - heal completed successfully"
                    log "Restarting ftm service..."
                    cd /app
                    docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d ftm
                    log "ftm service restarted"
                else
                    log "WARNING: Some FTM containers are still running after heal"
                fi
            else
                # Normal check - no dirty state found
                log "Health check: ftm container running, no dirty state detected"
            fi
        elif is_heal_container_running; then
            # ftm is not running but heal is - just wait
            log "ftm container not running, but heal container is active - waiting..."
            while is_heal_container_running; do
                sleep 5
            done
            
            # After heal finishes, check if we should restart ftm
            if ! any_ftm_container_running; then
                log "Heal completed and no FTM containers running - restarting ftm service..."
                cd /app
                docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d ftm
                log "ftm service restarted"
            fi
        else
            # Neither ftm nor heal is running - ftm might have crashed
            log "No ftm or ftm-heal containers running (this is normal if ftm was stopped manually)"
        fi
        
        # Sleep before next check
        sleep "${CHECK_INTERVAL}"
    done
}

# Run main function
main


#!/bin/bash

# Get project name from environment or default to ftm
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-ftm}"

# Stop and remove the main ftm service if it's running to clear logs (only ftm service, not watcher)
echo "Stopping ftm service..."
docker compose -p "$COMPOSE_PROJECT_NAME" -f docker-compose.yml stop ftm || docker stop ftm || true
echo "Removing ftm container to clear logs..."
docker compose -p "$COMPOSE_PROJECT_NAME" -f docker-compose.yml rm -f ftm || docker rm -f ftm || true

# Run the ftm-heal service
echo "Running ftm-heal command in detached mode..."
docker compose -p "$COMPOSE_PROJECT_NAME" -f docker-compose-heal.yml run --rm -d ftm-heal

echo "ftm-heal command started in background."

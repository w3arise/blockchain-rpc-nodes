#!/bin/bash

# Stop the main sonic service if it's running
echo "Stopping sonic service..."
docker compose -f docker-compose.yml down

# Run the sonic-heal service
echo "Running sonic-heal command in detached mode..."
docker compose -f docker-compose-heal.yml run --rm -d sonic-heal

echo "sonic-heal command started in background."

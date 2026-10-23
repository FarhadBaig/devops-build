#!/usr/bin/env bash
set -Eeuo pipefail

echo "==> Checking Docker Compose configuration"
docker compose config --quiet

echo "==> Starting application"
docker compose up -d

echo "==> Container status"
docker compose ps

echo "==> Checking application health"
for attempt in $(seq 1 15); do
    if curl --fail --silent http://127.0.0.1:8080/health; then
        echo
        echo "Deployment succeeded"
        exit 0
    fi

    echo "Health check attempt ${attempt}/15 failed; retrying..."
    sleep 2
done

echo "ERROR: Application health check failed" >&2
docker compose logs --tail=100 web
exit 1
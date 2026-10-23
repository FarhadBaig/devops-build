#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="${IMAGE_NAME:-react-app}"
IMAGE_TAG="${IMAGE_TAG:-local}"

echo "==> Validating Docker Compose configuration"
docker compose config --quiet

echo "==> Building ${IMAGE_NAME}:${IMAGE_TAG}"
docker build --tag "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "==> Build completed successfully"
docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format 'Image ID: {{.Id}}'
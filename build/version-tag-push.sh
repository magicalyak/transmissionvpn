#!/bin/bash
set -euo pipefail

IMAGE_NAME="magicalyak/nzbgetvpn"

echo "[INFO] Extracting NZBGet version from Dockerfile..."

# Extract version from Dockerfile
NZBGET_VERSION=$(grep -oP 'NZBGET_VERSION=\K[0-9.]+' Dockerfile | head -n 1)

if [[ -z "$NZBGET_VERSION" ]]; then
    echo "[ERROR] Could not extract NZBGet version from Dockerfile."
    exit 1
fi

TAG="v${NZBGET_VERSION}"
echo "[INFO] NZBGet version: $NZBGET_VERSION"
echo "[INFO] Tagging image as: $IMAGE_NAME:$TAG and $IMAGE_NAME:latest"

# Check if logged in to Docker
if ! docker info 2>/dev/null | grep -q "Username:"; then
    echo "[INFO] Docker login required..."
    docker login || {
        echo "[ERROR] Docker login failed. Aborting."
        exit 1
    }
fi

# Build image
echo "[INFO] Building Docker image..."
docker build -t "$IMAGE_NAME:$TAG" .

# Tag as latest too
docker tag "$IMAGE_NAME:$TAG" "$IMAGE_NAME:latest"

# Push both tags
echo "[INFO] Pushing image: $IMAGE_NAME:$TAG"
docker push "$IMAGE_NAME:$TAG"

echo "[INFO] Pushing image: $IMAGE_NAME:latest"
docker push "$IMAGE_NAME:latest"

echo "[SUCCESS] Image pushed: $IMAGE_NAME ($TAG and latest)"

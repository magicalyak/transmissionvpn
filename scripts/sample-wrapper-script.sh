#!/bin/bash

# Sample Transmission Wrapper Script
# Copy this to /opt/containerd/start-transmission-wrapper.sh and customize

set -e

# Load environment variables
ENV_FILE="/opt/containerd/env/transmission.env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from $ENV_FILE"
    source "$ENV_FILE"
else
    echo "ERROR: Environment file not found at $ENV_FILE"
    exit 1
fi

# Set defaults if not specified in env file
CONTAINER_NAME=${CONTAINER_NAME:-transmissionvpn}
IMAGE_NAME=${IMAGE_NAME:-magicalyak/transmissionvpn:latest}
HOST_PORT_WEB=${HOST_PORT_WEB:-9091}
HOST_PORT_METRICS=${HOST_PORT_METRICS:-9099}
HOST_PORT_PEER=${HOST_PORT_PEER:-51413}

# Create directories if they don't exist
mkdir -p "${DOWNLOADS_PATH:-/opt/transmission/downloads}"
mkdir -p "${CONFIG_PATH:-/opt/transmission/config}"
mkdir -p "${WATCH_PATH:-/opt/transmission/watch}"

echo "Starting Transmission container: $CONTAINER_NAME"
echo "Using image: $IMAGE_NAME"

# Stop and remove existing container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping existing container: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" || true
    docker rm "$CONTAINER_NAME" || true
fi

# Pull latest image
echo "Pulling latest image: $IMAGE_NAME"
docker pull "$IMAGE_NAME"

# Start the container
echo "Starting new container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --cap-add=NET_ADMIN \
    --device=/dev/net/tun \
    --dns=1.1.1.1 \
    --dns=1.0.0.1 \
    -p "${HOST_PORT_WEB}:9091" \
    -p "${HOST_PORT_METRICS}:9099" \
    -p "${HOST_PORT_PEER}:51413" \
    -p "${HOST_PORT_PEER}:51413/udp" \
    -v "${CONFIG_PATH:-/opt/transmission/config}:/config" \
    -v "${DOWNLOADS_PATH:-/opt/transmission/downloads}:/downloads" \
    -v "${WATCH_PATH:-/opt/transmission/watch}:/watch" \
    -e VPN_PROVIDER="${VPN_PROVIDER:-PRIVADOVPN}" \
    -e VPN_CONFIG="${VPN_CONFIG:-atl-009.ovpn}" \
    -e VPN_USERNAME="${VPN_USERNAME}" \
    -e VPN_PASSWORD="${VPN_PASSWORD}" \
    -e TRANSMISSION_WEB_UI="${TRANSMISSION_WEB_UI:-flood}" \
    -e TRANSMISSION_DOWNLOAD_DIR="${TRANSMISSION_DOWNLOAD_DIR:-/downloads}" \
    -e TRANSMISSION_INCOMPLETE_DIR="${TRANSMISSION_INCOMPLETE_DIR:-/downloads/incomplete}" \
    -e TRANSMISSION_WATCH_DIR="${TRANSMISSION_WATCH_DIR:-/downloads/watch}" \
    -e TRANSMISSION_RPC_USERNAME="${TRANSMISSION_RPC_USERNAME}" \
    -e TRANSMISSION_RPC_PASSWORD="${TRANSMISSION_RPC_PASSWORD}" \
    -e VPN_HEALTH_REQUIRED="${VPN_HEALTH_REQUIRED:-true}" \
    -e VPN_GRACE_PERIOD="${VPN_GRACE_PERIOD:-300}" \
    -e HEALTH_CHECK_HOST="${HEALTH_CHECK_HOST:-google.com}" \
    -e TZ="${TZ:-UTC}" \
    -e PUID="${PUID:-1000}" \
    -e PGID="${PGID:-1000}" \
    --restart unless-stopped \
    "$IMAGE_NAME"

echo "Container started successfully!"
echo "Web UI: http://$(hostname):${HOST_PORT_WEB}/transmission/web/"
echo "Metrics: http://$(hostname):${HOST_PORT_METRICS}/metrics"

# Wait a moment and check container status
sleep 5
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ Container is running"
    docker logs --tail 10 "$CONTAINER_NAME"
else
    echo "❌ Container failed to start"
    docker logs "$CONTAINER_NAME"
    exit 1
fi 
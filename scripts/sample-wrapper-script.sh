#!/bin/bash

# Sample Transmission Wrapper Script
# Copy this to /opt/containerd/start-transmission-wrapper.sh and customize

set -e

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker is not running"
    exit 1
fi

# Load environment variables
ENV_FILE="/opt/containerd/env/transmission.env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from $ENV_FILE"
    source "$ENV_FILE"
    log "INFO: Loaded environment variables"
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

# Check for and remove existing containers
for CONTAINER in "transmission" "transmissionvpn"; do
  if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
    log "INFO: Stopping and removing existing container $CONTAINER"
    docker stop "$CONTAINER" 2>/dev/null || true
    docker rm "$CONTAINER" 2>/dev/null || true
  fi
done

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

if [[ $? -eq 0 ]]; then
    log "INFO: Container started successfully"
    log "INFO: Web UI available at: http://$(hostname):${HOST_PORT_WEB}"
    log "INFO: Metrics available at: http://$(hostname):${HOST_PORT_METRICS}/metrics"
else
    log "ERROR: Failed to start container"
    exit 1
fi 
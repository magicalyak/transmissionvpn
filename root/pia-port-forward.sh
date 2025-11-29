#!/command/with-contenv bash
# shellcheck shell=bash
# PIA (Private Internet Access) Port Forwarding Script
#
# This script enables port forwarding for PIA VPN connections.
# Based on the official PIA manual-connections scripts.
#
# Requirements:
# - PIA_PORT_FORWARD=true environment variable
# - VPN_USER and VPN_PASS set (same as OpenVPN credentials)
# - Connected to a PIA server that supports port forwarding (NOT US servers)
#
# Note: Port forwarding is disabled on PIA's US servers.
# Use servers like: CA Toronto, CA Montreal, Netherlands, Switzerland, etc.

set -e

# Log function
log() {
  echo "[PIA-PF] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Check if port forwarding is enabled
if [ "${PIA_PORT_FORWARD,,}" != "true" ]; then
  log "PIA port forwarding not enabled (PIA_PORT_FORWARD != true). Exiting."
  exit 0
fi

log "Starting PIA port forwarding setup..."

# Check dependencies
for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    log "ERROR: Required command '$cmd' not found. Please install it."
    exit 1
  fi
done

# Check for credentials
if [ -z "$VPN_USER" ] || [ -z "$VPN_PASS" ]; then
  log "ERROR: VPN_USER and VPN_PASS must be set for PIA port forwarding."
  exit 1
fi

# Wait for VPN to be up
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
if [ ! -f "$VPN_INTERFACE_FILE" ]; then
  log "ERROR: VPN interface file not found. Is VPN connected?"
  exit 1
fi
VPN_INTERFACE=$(cat "$VPN_INTERFACE_FILE")

# Get the gateway IP (PIA server we're connected to)
PF_GATEWAY=$(ip route | grep "dev $VPN_INTERFACE" | grep -oP 'via \K[0-9.]+' | head -1)
if [ -z "$PF_GATEWAY" ]; then
  # Try alternate method
  PF_GATEWAY=$(ip route show dev "$VPN_INTERFACE" | awk '/via/ {print $3}' | head -1)
fi

if [ -z "$PF_GATEWAY" ]; then
  log "ERROR: Could not determine PIA gateway IP. VPN may not be connected."
  exit 1
fi
log "Detected PIA gateway: $PF_GATEWAY"

# Determine PF_HOSTNAME from VPN config or use default
# PIA NextGen servers use their hostname for certificate verification
if [ -f "/tmp/config.ovpn" ]; then
  PF_HOSTNAME=$(grep '^remote ' /tmp/config.ovpn | head -1 | awk '{print $2}')
fi
if [ -z "$PF_HOSTNAME" ]; then
  # Fallback - try to get from VPN_CONFIG
  if [ -f "$VPN_CONFIG" ]; then
    PF_HOSTNAME=$(grep '^remote ' "$VPN_CONFIG" | head -1 | awk '{print $2}')
  fi
fi
log "PIA hostname for certificate verification: ${PF_HOSTNAME:-unknown}"

# Step 1: Get PIA authentication token
log "Obtaining PIA authentication token..."
TOKEN_RESPONSE=$(curl -s -u "$VPN_USER:$VPN_PASS" \
  "https://www.privateinternetaccess.com/api/client/v2/token" 2>&1)

PIA_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token' 2>/dev/null)

if [ -z "$PIA_TOKEN" ] || [ "$PIA_TOKEN" = "null" ]; then
  log "ERROR: Failed to get PIA token. Response: $TOKEN_RESPONSE"
  log "This could mean invalid credentials or API issues."
  exit 1
fi
log "Successfully obtained PIA token."

# Step 2: Get port forwarding signature from the gateway
log "Requesting port forwarding signature from gateway..."

# PIA uses a self-signed cert, we need to handle this
# The gateway exposes port 19999 for the PF API
SIGNATURE_RESPONSE=$(curl -s -m 10 \
  --connect-to "${PF_HOSTNAME}:19999:${PF_GATEWAY}:19999" \
  --cacert /config/openvpn/ca.rsa.4096.crt \
  "https://${PF_HOSTNAME}:19999/getSignature?token=$PIA_TOKEN" 2>&1 || \
  # Fallback without cert verification if ca cert not available
  curl -s -m 10 -k \
  "https://${PF_GATEWAY}:19999/getSignature?token=$PIA_TOKEN" 2>&1)

SIGNATURE_STATUS=$(echo "$SIGNATURE_RESPONSE" | jq -r '.status' 2>/dev/null)

if [ "$SIGNATURE_STATUS" != "OK" ]; then
  log "ERROR: Failed to get port forwarding signature."
  log "Response: $SIGNATURE_RESPONSE"
  log ""
  log "This typically means:"
  log "  - You're connected to a US server (port forwarding disabled in US)"
  log "  - The server doesn't support port forwarding"
  log "  - Network connectivity issues"
  log ""
  log "Try switching to a non-US server like:"
  log "  - CA Toronto, CA Montreal"
  log "  - Netherlands, Switzerland, Sweden"
  log "  - Germany, France, UK"
  exit 1
fi

# Extract signature and payload
PF_SIGNATURE=$(echo "$SIGNATURE_RESPONSE" | jq -r '.signature')
PF_PAYLOAD=$(echo "$SIGNATURE_RESPONSE" | jq -r '.payload')

# Decode payload to get port
PF_PORT=$(echo "$PF_PAYLOAD" | base64 -d 2>/dev/null | jq -r '.port')
PF_EXPIRES=$(echo "$PF_PAYLOAD" | base64 -d 2>/dev/null | jq -r '.expires_at')

if [ -z "$PF_PORT" ] || [ "$PF_PORT" = "null" ]; then
  log "ERROR: Could not extract port from payload."
  exit 1
fi

log "Port forwarding enabled! Forwarded port: $PF_PORT"
log "Port expires at: $PF_EXPIRES"

# Save port to file for other scripts/healthchecks
echo "$PF_PORT" > /tmp/pia_forwarded_port
log "Saved forwarded port to /tmp/pia_forwarded_port"

# Step 3: Configure Transmission to use this port
configure_transmission_port() {
  local port=$1
  log "Configuring Transmission to use port $port..."

  # Wait for Transmission to be ready
  local retries=30
  while [ $retries -gt 0 ]; do
    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9091/transmission/rpc" | grep -q "409"; then
      break
    fi
    sleep 2
    retries=$((retries - 1))
  done

  if [ $retries -eq 0 ]; then
    log "WARNING: Transmission RPC not responding. Will try to set port anyway."
  fi

  # Get session-id for RPC
  SESSION_ID=$(curl -s -i "http://127.0.0.1:9091/transmission/rpc" 2>/dev/null | \
    grep -i "X-Transmission-Session-Id" | awk '{print $2}' | tr -d '\r')

  if [ -z "$SESSION_ID" ]; then
    log "WARNING: Could not get Transmission session ID."
    return 1
  fi

  # Build auth header if RPC authentication is enabled
  AUTH_HEADER=""
  if [ -n "$TRANSMISSION_RPC_USERNAME" ] && [ -n "$TRANSMISSION_RPC_PASSWORD" ]; then
    AUTH_HEADER="-u $TRANSMISSION_RPC_USERNAME:$TRANSMISSION_RPC_PASSWORD"
  fi

  # Set peer port via RPC
  # shellcheck disable=SC2086
  RESULT=$(curl -s $AUTH_HEADER \
    -H "X-Transmission-Session-Id: $SESSION_ID" \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"session-set\",\"arguments\":{\"peer-port\":$port}}" \
    "http://127.0.0.1:9091/transmission/rpc" 2>&1)

  if echo "$RESULT" | jq -e '.result == "success"' > /dev/null 2>&1; then
    log "Successfully set Transmission peer port to $port"
    return 0
  else
    log "WARNING: Failed to set Transmission port. Response: $RESULT"
    return 1
  fi
}

# Configure Transmission
configure_transmission_port "$PF_PORT"

# Step 4: Port binding keepalive loop
# PIA requires a keepalive every 15 minutes to maintain the port
log "Starting port binding keepalive loop (every 15 minutes)..."

bind_port() {
  local response
  response=$(curl -s -m 10 \
    --connect-to "${PF_HOSTNAME}:19999:${PF_GATEWAY}:19999" \
    --cacert /config/openvpn/ca.rsa.4096.crt \
    "https://${PF_HOSTNAME}:19999/bindPort?payload=$PF_PAYLOAD&signature=$PF_SIGNATURE" 2>&1 || \
    curl -s -m 10 -k \
    "https://${PF_GATEWAY}:19999/bindPort?payload=$PF_PAYLOAD&signature=$PF_SIGNATURE" 2>&1)

  local status
  status=$(echo "$response" | jq -r '.status' 2>/dev/null)

  if [ "$status" = "OK" ]; then
    log "Port binding refreshed successfully. Port $PF_PORT active."
    return 0
  else
    log "WARNING: Port binding refresh failed. Response: $response"
    return 1
  fi
}

# Initial bind
bind_port

# Run keepalive in background
(
  while true; do
    sleep 900  # 15 minutes
    if ! bind_port; then
      log "Port binding failed. Port forwarding may have expired."
      # Try to get a new signature
      log "Attempting to renew port forwarding..."
      # Exit this loop - the main script should be restarted
      exit 1
    fi
  done
) &

KEEPALIVE_PID=$!
echo "$KEEPALIVE_PID" > /tmp/pia_keepalive_pid
log "Keepalive process started with PID $KEEPALIVE_PID"

log "PIA port forwarding setup complete!"
log "Forwarded port: $PF_PORT"
log "Port will be refreshed every 15 minutes automatically."

exit 0

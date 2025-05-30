#!/bin/bash
set -e

echo "[INFO] Starting NZBGet + VPN container"

# Create credentials file
echo "$VPN_USER" > /config/openvpn/credentials
echo "$VPN_PASS" >> /config/openvpn/credentials
chmod 600 /config/openvpn/credentials

# Check .ovpn file
if [[ ! -f "$VPN_CONFIG" ]]; then
  echo "[ERROR] VPN config file not found at $VPN_CONFIG"
  exit 1
fi

# Inject auth-user-pass line into .ovpn if missing
grep -q 'auth-user-pass' "$VPN_CONFIG" || echo "auth-user-pass /config/openvpn/credentials" >> "$VPN_CONFIG"

echo "[INFO] Starting OpenVPN..."
openvpn --config "$VPN_CONFIG" --daemon --writepid /run/openvpn.pid

# Wait for tunnel to come up
echo "[INFO] Waiting for VPN tunnel..."
sleep 15

# Confirm tunnel
ip addr show tun0 || {
  echo "[ERROR] VPN tunnel not established"
  exit 2
}

echo "[INFO] VPN tunnel is up, launching NZBGet..."
exec /init

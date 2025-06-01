#!/command/with-contenv bash
# shellcheck disable=SC1008
# Ensure /config/openvpn and /config/wireguard directories exist

echo "Ensuring VPN configuration directories exist in /config..."

mkdir -p /config/openvpn
mkdir -p /config/wireguard

echo "VPN configuration directories checked." 
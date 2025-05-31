#!/bin/bash

# Basic check: is NZBGet responding?
curl -sSf http://localhost:6789 || exit 1 # Reverted to base URL check

# Determine VPN interface
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
if [ -f "$VPN_INTERFACE_FILE" ]; then
  VPN_IF=$(cat "$VPN_INTERFACE_FILE")
else
  # Fallback if file not found (should not happen if 50-vpn-setup ran correctly)
  # Check for common interfaces, prioritize wg0 then tun0
  if ip link show wg0 &> /dev/null; then
    VPN_IF="wg0"
  elif ip link show tun0 &> /dev/null; then
    VPN_IF="tun0"
  else
    # echo "Healthcheck: Could not determine VPN interface and fallbacks (wg0, tun0) not found."
    exit 3 # Specific exit code for VPN interface determination failure
  fi
fi

# echo "Healthcheck: Checking VPN interface: $VPN_IF"
# echo "Healthcheck: Output of 'ip link show \"$VPN_IF\"':"
# ip link show "$VPN_IF"
# echo "Healthcheck: Output of 'ip link show \"$VPN_IF\" | grep -q \"UP\'; echo $?'"

# Check that the determined tunnel is up
ip link show "$VPN_IF" | grep -q "UP" || exit 2 # Changed to grep for "UP" only

exit 0

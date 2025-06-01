#!/command/with-contenv bash
# shellcheck shell=bash
# This script sets up the VPN connection (OpenVPN or WireGuard)
# and configures iptables for policy-based routing.

set -e # Exit immediately if a command exits with a non-zero status.
# set -x # Uncomment for debugging

echo "[INFO] Starting VPN setup script..."
date

# Ensure /tmp exists and is writable
mkdir -p /tmp
chmod 777 /tmp

# Log all output of this script to a file in /tmp for easier debugging via docker exec
exec &> /tmp/vpn-setup.log
# Also print to stdout/stderr for s6 logging
exec > >(tee -a /tmp/vpn-setup.log) 2> >(tee -a /tmp/vpn-setup.log >&2)


if [ "${DEBUG,,}" = "true" ]; then
  echo "[DEBUG] Debug mode enabled. Full script output will be logged."
  set -x
fi

# Default VPN Interface (will be updated after connection)
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
DEFAULT_VPN_INTERFACE="tun0" # Common for OpenVPN
if [ "${VPN_CLIENT,,}" = "wireguard" ]; then
  # For WireGuard, derive from VPN_CONFIG or default to wg0
  if [ -n "$VPN_CONFIG" ]; then # Using VPN_CONFIG now
    DEFAULT_VPN_INTERFACE=$(basename "$VPN_CONFIG" .conf)
  else # try to find a .conf file
    WG_CONF_FOUND=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
    if [ -n "$WG_CONF_FOUND" ]; then
        DEFAULT_VPN_INTERFACE=$(basename "$WG_CONF_FOUND" .conf)
    else
        DEFAULT_VPN_INTERFACE="wg0" # Fallback if no specific config found
    fi
  fi
fi
echo "$DEFAULT_VPN_INTERFACE" > "$VPN_INTERFACE_FILE"
echo "[INFO] Default VPN interface set to: $(cat $VPN_INTERFACE_FILE)"


# Function to find OpenVPN credentials
find_vpn_credentials() {
  # Clear any stale credentials file
  rm -f /tmp/vpn-credentials

  # Priority 1: VPN_USER and VPN_PASS from environment.
  if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[INFO] Using VPN_USER and VPN_PASS from environment."
    echo "$VPN_USER" > /tmp/vpn-credentials
    echo "$VPN_PASS" >> /tmp/vpn-credentials
    if [ -s /tmp/vpn-credentials ] && [ "$(wc -l < /tmp/vpn-credentials)" -ge 2 ]; then
        echo "[INFO] Credentials successfully written to /tmp/vpn-credentials from environment variables."
        return 0
    else
        echo "[WARN] VPN_USER and/or VPN_PASS were provided but resulted in an empty or incomplete credential file. Clearing."
        rm -f /tmp/vpn-credentials
    fi
  fi

  # Priority 2: Fixed credentials file path /config/openvpn/credentials.txt
  FIXED_CRED_PATH="/config/openvpn/credentials.txt"
  if [ -f "$FIXED_CRED_PATH" ] && [ -r "$FIXED_CRED_PATH" ]; then
    echo "[INFO] Checking for credentials file at fixed path: $FIXED_CRED_PATH"
    # Ensure the file is not empty and has at least two lines (user & pass)
    if [ -s "$FIXED_CRED_PATH" ] && [ "$(wc -l < "$FIXED_CRED_PATH")" -ge 2 ]; then
      echo "[INFO] Using OpenVPN credentials from $FIXED_CRED_PATH."
      cp "$FIXED_CRED_PATH" /tmp/vpn-credentials
      # Double check copy success and content
      if [ -s /tmp/vpn-credentials ] && [ "$(wc -l < /tmp/vpn-credentials)" -ge 2 ]; then
        echo "[INFO] Credentials successfully copied to /tmp/vpn-credentials from $FIXED_CRED_PATH."
        return 0
      else
        echo "[WARN] Failed to copy or validate credentials from $FIXED_CRED_PATH to /tmp/vpn-credentials. Clearing."
        rm -f /tmp/vpn-credentials
      fi
    else
      echo "[WARN] Credentials file $FIXED_CRED_PATH was found but is empty or does not contain at least two lines. Ignoring."
    fi
  else
    echo "[INFO] No credentials file found at $FIXED_CRED_PATH (this is okay if using VPN_USER/PASS or if your VPN config doesn't need separate auth)."
  fi
  
  # If neither method yielded credentials
  echo "[WARN] No valid VPN credentials provided via VPN_USER/VPN_PASS or at $FIXED_CRED_PATH."
  echo "[INFO] If your OpenVPN configuration requires username/password authentication and doesn't embed them, connection may fail."
  return 1 
}

# Function to start OpenVPN
start_openvpn() {
  echo "[INFO] Setting up OpenVPN..."
  OVPN_CONFIG_FILE=""
  if [ -n "$VPN_CONFIG" ]; then
    if [ -f "$VPN_CONFIG" ]; then
      OVPN_CONFIG_FILE="$VPN_CONFIG"
      echo "[INFO] Using OpenVPN config: $OVPN_CONFIG_FILE"
    else
      echo "[ERROR] Specified VPN_CONFIG=$VPN_CONFIG not found."
      exit 1
    fi
  else
    # Try to find the first .ovpn file in /config/openvpn
    OVPN_CONFIG_FILE=$(find /config/openvpn -maxdepth 1 -name '*.ovpn' -print -quit)
    if [ -z "$OVPN_CONFIG_FILE" ]; then
      echo "[ERROR] No OpenVPN configuration file specified via VPN_CONFIG and none found in /config/openvpn."
      exit 1
    else
      echo "[INFO] Automatically selected OpenVPN config: $OVPN_CONFIG_FILE"
    fi
  fi

  # Credentials
  if ! find_vpn_credentials; then
    echo "[ERROR] OpenVPN credentials not provided or found. Please set VPN_USER/VPN_PASS environment variables, or create a credentials file at /config/openvpn/credentials.txt (username on line 1, password on line 2)."
    exit 1
  fi

  # Create up/down scripts for OpenVPN
  mkdir -p /etc/openvpn
  cat << EOF > /etc/openvpn/update-resolv.sh
#!/bin/bash
# Script to update resolv.conf with DNS servers from OpenVPN
# exec &> /tmp/openvpn_script.log # DO NOT log here, it causes issues with OpenVPN execution context
# Instead, log to /tmp/openvpn.log directly in this script

set -x # For debugging individual commands in this script

echo "--- OpenVPN UP script started ---" | tee -a /tmp/openvpn.log
date | tee -a /tmp/openvpn.log
# env | tee -a /tmp/openvpn.log # Log environment to see what OpenVPN provides

# Backup original resolv.conf if not already backed up
if [ ! -f "/tmp/resolv.conf.backup" ]; then
  if [ -f "/etc/resolv.conf" ]; then # Only backup if original exists
    cp "/etc/resolv.conf" "/tmp/resolv.conf.backup"
    echo "Backed up /etc/resolv.conf to /tmp/resolv.conf.backup" | tee -a /tmp/openvpn.log
  else
    echo "Original /etc/resolv.conf not found, cannot backup." | tee -a /tmp/openvpn.log
  fi
fi

# Start with an empty temp resolv.conf
echo "# Generated by OpenVPN update-resolv.sh" > "/tmp/resolv.conf.openvpn"

# Option 1: Use NAME_SERVERS if provided from parent environment
# The 'foreign_option' parsing relies on these being exported to the script by OpenVPN
# Ensure NAME_SERVERS is accessible here if set in Docker env.
# openvpn --script-security 2 --up /etc/openvpn/update-resolv.sh --up-restart
# needs NAME_SERVERS to be pushed or available in the script's env.
# If using with-contenv, NAME_SERVERS should be available.

if [ -n "\$NAME_SERVERS" ]; then
  echo "[INFO] Using NAME_SERVERS: \$NAME_SERVERS" | tee -a /tmp/openvpn.log
  # Use sed to transform comma-separated list directly to nameserver lines
  echo "\$NAME_SERVERS" | sed -e 's/,/\nnameserver /g' -e 's/^/nameserver /' >> "/tmp/resolv.conf.openvpn"
else
  # Option 2: Try to parse foreign_option_ variables for DNS (pushed by VPN server)
  echo "[INFO] NAME_SERVERS not set, trying to use DNS from VPN (foreign_option_X)" | tee -a /tmp/openvpn.log
  dns_found=0
  for option_var_name in \$(env | grep '^foreign_option_' | cut -d= -f1); do
    option_var_value=\$(eval echo "\\\"\$\$option_var_name\\\"")
    if echo "\$option_var_value" | grep -q '^dhcp-option DNS'; then
      dns_server=\$(echo "\$option_var_value" | cut -d' ' -f3)
      echo "nameserver \$dns_server" >> "/tmp/resolv.conf.openvpn"
      echo "[INFO] Added DNS server from VPN: \$dns_server" | tee -a /tmp/openvpn.log
      dns_found=1
    fi
  done
  if [ \$dns_found -eq 0 ]; then
      echo "[WARN] No DNS servers pushed by VPN, and NAME_SERVERS not set. Using fallbacks." | tee -a /tmp/openvpn.log
      echo "nameserver 1.1.1.1" >> "/tmp/resolv.conf.openvpn" # Cloudflare
      echo "nameserver 8.8.8.8" >> "/tmp/resolv.conf.openvpn" # Google
  fi
fi

# Atomically replace resolv.conf
# Check if /tmp/resolv.conf.openvpn has content beyond the initial comment
if [ \$(grep -cv '^#' /tmp/resolv.conf.openvpn) -gt 0 ]; then
  cp "/tmp/resolv.conf.openvpn" "/etc/resolv.conf"
  echo "Updated /etc/resolv.conf" | tee -a /tmp/openvpn.log
else
  echo "[WARN] /tmp/resolv.conf.openvpn was empty or only comments. Not updating /etc/resolv.conf." | tee -a /tmp/openvpn.log
fi

# Create a flag file to indicate the 'up' script has completed
# This helps the main vpn-setup.sh script to know when tun0 is likely configured
echo "OpenVPN UP script completed. Interface: \$dev" > /tmp/openvpn_up_complete
echo "[INFO] OpenVPN UP script for \$dev completed (flag file created)." | tee -a /tmp/openvpn.log
exit 0
EOF

  cat << EOF > /etc/openvpn/restore-resolv.sh
#!/bin/bash
# Script to restore original resolv.conf
# exec &> /tmp/openvpn_script_down.log # DO NOT log here
set -x
echo "--- OpenVPN DOWN script started ---" | tee -a /tmp/openvpn.log
date | tee -a /tmp/openvpn.log

if [ -f "/tmp/resolv.conf.backup" ]; then
  cp "/tmp/resolv.conf.backup" "/etc/resolv.conf"
  echo "Restored /etc/resolv.conf from /tmp/resolv.conf.backup" | tee -a /tmp/openvpn.log
  rm "/tmp/resolv.conf.backup" # Clean up backup
else
  echo "No backup /tmp/resolv.conf.backup found to restore." | tee -a /tmp/openvpn.log
fi
# Remove the flag file
rm -f /tmp/openvpn_up_complete
echo "[INFO] OpenVPN DOWN script for \$dev completed (flag file removed)." | tee -a /tmp/openvpn.log
exit 0
EOF

  chmod +x /etc/openvpn/update-resolv.sh /etc/openvpn/restore-resolv.sh

  # Modify OVPN config on the fly for auth-user-pass and script security
  TEMP_OVPN_CONFIG="/tmp/config.ovpn"
  cp "$OVPN_CONFIG_FILE" "$TEMP_OVPN_CONFIG"
  # Ensure auth-user-pass points to our standard credentials file
  if grep -q "^auth-user-pass" "$TEMP_OVPN_CONFIG"; then
    sed -i 's|^auth-user-pass.*|auth-user-pass /tmp/vpn-credentials|' "$TEMP_OVPN_CONFIG"
  else
    echo "auth-user-pass /tmp/vpn-credentials" >> "$TEMP_OVPN_CONFIG"
  fi
  # Ensure script-security 2 is set for up/down scripts
  if grep -q "^script-security" "$TEMP_OVPN_CONFIG"; then
    sed -i 's|^script-security.*|script-security 2|' "$TEMP_OVPN_CONFIG"
  else
    echo "script-security 2" >> "$TEMP_OVPN_CONFIG"
  fi
  # Add up and down script directives
  if ! grep -q "^up " "$TEMP_OVPN_CONFIG"; then
    echo "up /etc/openvpn/update-resolv.sh" >> "$TEMP_OVPN_CONFIG"
  fi
  if ! grep -q "^down " "$TEMP_OVPN_CONFIG"; then
    echo "down /etc/openvpn/restore-resolv.sh" >> "$TEMP_OVPN_CONFIG"
  fi
  # Remove redirect-gateway if LAN_NETWORK is set, we'll handle routing
  if [ -n "$LAN_NETWORK" ]; then
    sed -i '/^redirect-gateway def1/d' "$TEMP_OVPN_CONFIG"
    echo "[INFO] Removed redirect-gateway def1 from OpenVPN config due to LAN_NETWORK being set."
  fi


  echo "[INFO] Starting OpenVPN client..."
  # Using exec to replace the shell process with openvpn is not suitable here as we need to run commands after it.
  # Run OpenVPN in the background. s6 will manage its lifecycle if needed as part of this init script.
  openvpn --config "$TEMP_OVPN_CONFIG" \
          --dev "$(cat $VPN_INTERFACE_FILE)" \
          ${VPN_OPTIONS} > /tmp/openvpn.log 2>&1 &

  # Wait for the 'up' script to complete by checking for the flag file
  echo "[INFO] Waiting for OpenVPN 'up' script to complete (expect /tmp/openvpn_up_complete)..."
  UP_SCRIPT_TIMEOUT=60 # seconds
  UP_SCRIPT_FLAG="/tmp/openvpn_up_complete"
  SECONDS=0
  while [ ! -f "$UP_SCRIPT_FLAG" ]; do
    if [ "$SECONDS" -ge "$UP_SCRIPT_TIMEOUT" ]; then
      echo "[ERROR] Timeout waiting for OpenVPN 'up' script to create $UP_SCRIPT_FLAG."
      echo "OpenVPN log (/tmp/openvpn.log) contents:"
      cat /tmp/openvpn.log
      echo "update-resolv.sh log (/tmp/openvpn_script.log) contents (if any):"
      cat /tmp/openvpn_script.log || echo "No /tmp/openvpn_script.log found."
      exit 1
    fi
    sleep 1
  done
  echo "[INFO] OpenVPN 'up' script completed (flag file found)."
  VPN_INTERFACE_FROM_UP_SCRIPT=$(awk -F': ' '/Interface: / {print $2}' "$UP_SCRIPT_FLAG" | tr -d '\r')
  if [ -n "$VPN_INTERFACE_FROM_UP_SCRIPT" ]; then
      echo "$VPN_INTERFACE_FROM_UP_SCRIPT" > "$VPN_INTERFACE_FILE"
      echo "[INFO] VPN interface updated from 'up' script: $(cat $VPN_INTERFACE_FILE)"
  else
      echo "[WARN] Could not determine VPN interface from up script. Using default: $(cat $VPN_INTERFACE_FILE)"
  fi

}

# Function to start WireGuard
start_wireguard() {
  echo "[INFO] Setting up WireGuard..."
  WG_CONFIG="" # This will be the path to the actual config file
  if [ -n "$VPN_CONFIG" ]; then # Using VPN_CONFIG now
      if [ -f "$VPN_CONFIG" ]; then
          WG_CONFIG="$VPN_CONFIG"
          echo "[INFO] Using WireGuard config: $WG_CONFIG"
      else
          echo "[ERROR] Specified VPN_CONFIG (for WireGuard) = $VPN_CONFIG not found."
          exit 1
      fi
  else
      # Try to find the first .conf file in /config/wireguard
      WG_CONF_FOUND=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
      if [ -z "$WG_CONF_FOUND" ]; then
          echo "[ERROR] No WireGuard configuration file specified via VPN_CONFIG and none found in /config/wireguard."
          exit 1
      else
          WG_CONFIG="$WG_CONF_FOUND"
          echo "[INFO] Automatically selected WireGuard config: $WG_CONFIG"
          # Update VPN_INTERFACE_FILE based on found config, if VPN_CONFIG was not explicitly set
          echo "$(basename "$WG_CONFIG" .conf)" > "$VPN_INTERFACE_FILE"
      fi
  fi
  INTERFACE_NAME=$(cat "$VPN_INTERFACE_FILE")
  echo "[INFO] Starting WireGuard for interface $INTERFACE_NAME using $WG_CONFIG..."
  wg-quick up "$WG_CONFIG"
  echo "[INFO] WireGuard started. Interface: $INTERFACE_NAME"
  # For WireGuard, DNS is typically set in the .conf file's [Interface] section (DNS = x.x.x.x)
  # wg-quick should handle setting this up.
  # If NAME_SERVERS is provided, we can override /etc/resolv.conf
  if [ -n "$NAME_SERVERS" ]; then
    echo "[INFO] NAME_SERVERS is set ($NAME_SERVERS), updating /etc/resolv.conf for WireGuard."
    # Backup original resolv.conf if not already backed up
    if [ ! -f "/tmp/resolv.conf.backup" ]; then
      if [ -f "/etc/resolv.conf" ]; then cp "/etc/resolv.conf" "/tmp/resolv.conf.backup"; fi
    fi
    echo "# Generated by vpn-setup.sh for WireGuard using NAME_SERVERS" > /tmp/resolv.conf.wireguard
    echo "$NAME_SERVERS" | sed -e 's/,/\nnameserver /g' -e 's/^/nameserver /' >> "/tmp/resolv.conf.wireguard"
    cp "/tmp/resolv.conf.wireguard" "/etc/resolv.conf"
    echo "Updated /etc/resolv.conf with NAME_SERVERS."
  fi
}

# Select VPN client
if [ "${VPN_CLIENT,,}" = "openvpn" ]; then
  start_openvpn
elif [ "${VPN_CLIENT,,}" = "wireguard" ]; then
  start_wireguard
else
  echo "[ERROR] Invalid VPN_CLIENT: $VPN_CLIENT. Must be 'openvpn' or 'wireguard'."
  exit 1
fi

# Wait for VPN interface to be up and have an IP
VPN_INTERFACE=$(cat "$VPN_INTERFACE_FILE")
echo "[INFO] Waiting for VPN interface $VPN_INTERFACE to come up and get an IP address..."
TIMEOUT=60 # seconds
SECONDS=0
while true; do
  # Check for interface existence and UP state broadly
  if ! ip link show "$VPN_INTERFACE" | grep -q "state UP"; then
    # For tun devices, state might be UNKNOWN but still functional if it has an IP
    if ! (ip addr show "$VPN_INTERFACE" | grep -q "inet ") && ! (ip link show "$VPN_INTERFACE" | grep -q "state UNKNOWN"); then
        echo "[DEBUG] Interface $VPN_INTERFACE not UP yet or no IP. Waiting..."
    elif ! (ip addr show "$VPN_INTERFACE" | grep -q "inet "); then
        echo "[DEBUG] Interface $VPN_INTERFACE is UP but no IP address yet. Waiting..."
    else # Has IP
        echo "[INFO] Interface $VPN_INTERFACE has an IP address."
        break
    fi
  else # State is UP
    # Now check for IP specifically
    if ip addr show "$VPN_INTERFACE" | grep -q "inet "; then
        echo "[INFO] Interface $VPN_INTERFACE is UP and has an IP address."
        break
    else
        echo "[DEBUG] Interface $VPN_INTERFACE is UP but no IP address yet. Waiting..."
    fi
  fi

  if [ "$SECONDS" -ge "$TIMEOUT" ]; then
    echo "[ERROR] Timeout waiting for $VPN_INTERFACE to come up and get an IP."
    echo "Details for interface $VPN_INTERFACE:"
    ip addr show "$VPN_INTERFACE" || echo "Interface $VPN_INTERFACE not found."
    if [ "${VPN_CLIENT,,}" = "openvpn" ]; then
        echo "OpenVPN log (/tmp/openvpn.log) contents:"
        cat /tmp/openvpn.log || echo "No /tmp/openvpn.log"
    fi
    exit 1
  fi
  sleep 1
done
echo "[INFO] VPN interface $VPN_INTERFACE is active."

# --- IPTables and Routing ---
echo "[INFO] Configuring iptables and routing rules..."

# Get gateway for eth0 (Docker's bridge)
ETH0_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')
if [ -z "$ETH0_GATEWAY" ]; then
    # Fallback for older ip route versions or different outputs
    ETH0_GATEWAY=$(ip route show dev eth0 | awk '/default via/ {print $3}')
fi
if [ -z "$ETH0_GATEWAY" ]; then
    # A common default if detection fails, but this is a guess
    ETH0_GATEWAY="172.17.0.1" # This often is the Docker host IP on the default bridge
    echo "[WARN] Could not reliably determine eth0 gateway. Using default $ETH0_GATEWAY. If UI is inaccessible, this might be the cause."
else
    echo "[INFO] Detected eth0 gateway: $ETH0_GATEWAY"
fi

# Get IP for eth0
ETH0_IP=$(ip -4 addr show dev eth0 | awk '/inet/ {print $2}' | cut -d/ -f1)
if [ -z "$ETH0_IP" ]; then
    echo "[WARN] Could not determine IP address of eth0. Policy routing for UI access might not be optimal."
else
    echo "[INFO] Detected eth0 IP: $ETH0_IP"
fi

# Flush existing rules (important for restarts or rule changes)
iptables -F INPUT
iptables -F FORWARD
iptables -F OUTPUT
iptables -t nat -F
iptables -t mangle -F
echo "[INFO] Flushed existing iptables rules."

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT # Allow outbound traffic by default, will be shaped by VPN
echo "[INFO] Set default iptables policies (INPUT/FORWARD DROP, OUTPUT ACCEPT)."

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
echo "[INFO] Allowed loopback traffic."

# Allow established and related connections (standard rule)
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
# For FORWARD chain as well, if container were to act as a router for others (not typical for this use case but good practice)
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "[INFO] Allowed established/related connections."

# Allow Transmission UI access from host (Docker for Mac via 127.0.0.1 proxies to eth0 IP)
iptables -A INPUT -i eth0 -p tcp --dport 9091 -j ACCEPT
echo "[INFO] Added iptables rule to allow Transmission UI on eth0:9091."

# Policy routing for Transmission UI & Privoxy when accessed from host
# This ensures replies to connections hitting eth0 go back out via eth0 gateway, not VPN tunnel
echo "[INFO] Adding CONNMARK policy routing for UI access (mark 0x1, table 100)"

if [ -n "$ETH0_IP" ]; then
  echo "[INFO] Using specific eth0 IP $ETH0_IP for PREROUTING CONNMARK rules."
  # 1. On incoming connections to Transmission on eth0, mark the connection
  iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 9091 -j CONNMARK --set-mark 0x1
else
  echo "[WARN] ETH0_IP not found. Using less specific -i eth0 for PREROUTING CONNMARK rule for Transmission."
  iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 9091 -j CONNMARK --set-mark 0x1
fi

# 2. Restore mark on packets belonging to these connections in OUTPUT chain
iptables -t mangle -A OUTPUT -p tcp --sport 9091 -j CONNMARK --restore-mark
# 3. Create a routing rule to use table 100 if mark is 0x1
ip rule add fwmark 0x1 lookup 100 priority 1000
# 4. Add a default route to table 100 via "$ETH0_GATEWAY" dev eth0 table 100
ip route add default via "$ETH0_GATEWAY" dev eth0 table 100

echo "[INFO] CONNMARK rules for Transmission UI (port 9091) applied."


# VPN is up, redirect all other OUTPUT traffic through VPN interface
# This is the main "kill switch" part.
# All OUTPUT not matching previous rules (like loopback, PBR for UI)
# and not going to LAN_NETWORK, will be forced via VPN.

# If LAN_NETWORK is set, allow traffic to it without VPN
if [ -n "$LAN_NETWORK" ]; then
  echo "[INFO] LAN_NETWORK ($LAN_NETWORK) is set. Adding route and iptables exception."
  # Add route for LAN_NETWORK to go via eth0's gateway
  ip route add "$LAN_NETWORK" via "$ETH0_GATEWAY" dev eth0
  # Allow output to LAN_NETWORK
  iptables -A OUTPUT -o eth0 -d "$LAN_NETWORK" -j ACCEPT
  # Allow input from LAN_NETWORK (e.g. for NZBGet calling back to a local Sonarr/Radarr)
  iptables -A INPUT -i eth0 -s "$LAN_NETWORK" -j ACCEPT
  echo "[INFO] Allowed traffic to/from LAN_NETWORK $LAN_NETWORK via eth0."
fi

# Allow specific additional ports if ADDITIONAL_PORTS is set
if [ -n "$ADDITIONAL_PORTS" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for port_entry in $ADDITIONAL_PORTS; do
    IFS="$OLD_IFS" # Restore IFS for commands inside the loop
    port_num=$(echo "$port_entry" | cut -d'/' -f1 | xargs)
    proto=$(echo "$port_entry" | awk -F'/' '{if (NF>1) {print $2} else {print "tcp"}}' | xargs) # Default to tcp if no proto specified
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        echo "[WARN] Invalid protocol '$proto' in ADDITIONAL_PORTS for entry '$port_entry'. Assuming tcp."
        proto="tcp"
    fi
    if [[ "$port_num" =~ ^[0-9]+$ ]] && [ "$port_num" -ge 1 ] && [ "$port_num" -le 65535 ]; then
      echo "[INFO] Allowing outbound traffic on $proto port $port_num via $VPN_INTERFACE."
      iptables -A OUTPUT -o "$VPN_INTERFACE" -p "$proto" --dport "$port_num" -j ACCEPT
    else
      echo "[WARN] Invalid port number '$port_num' in ADDITIONAL_PORTS for entry '$port_entry'. Skipping."
    fi
    IFS=',' # Re-set IFS for the loop
  done
  IFS="$OLD_IFS"
  echo "[INFO] Processed ADDITIONAL_PORTS."
fi

# All other OUTPUT traffic must go through VPN interface or be dropped
iptables -A OUTPUT -o "$VPN_INTERFACE" -j ACCEPT
iptables -A OUTPUT -o eth0 -j DROP # Drop if trying to go out eth0 and not LAN/PBR
# Could also be more strict: iptables -A OUTPUT ! -o "$VPN_INTERFACE" -j DROP
# but the above allows things like established connections already handled.
echo "[INFO] Default OUTPUT traffic routed through $VPN_INTERFACE. Other outbound on eth0 (non-LAN, non-PBR) dropped."


# Privoxy: Apply firewall and PBR rules if enabled (s6 will start the service)
if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
  echo "[INFO] Privoxy is enabled. Ensuring firewall and PBR rules for port ${PRIVOXY_PORT:-8118}."
  iptables -A INPUT -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j ACCEPT # Allow incoming to Privoxy

  if [ -n "$ETH0_IP" ]; then
    echo "[INFO] Adding CONNMARK rules for Privoxy on port ${PRIVOXY_PORT:-8118} to $ETH0_IP"
    iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport "${PRIVOXY_PORT:-8118}" -j CONNMARK --set-mark 0x1
  else
    echo "[WARN] ETH0_IP not found, using less specific -i eth0 for PREROUTING CONNMARK rule for Privoxy."
    iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j CONNMARK --set-mark 0x1
  fi
  iptables -t mangle -A OUTPUT -p tcp --sport "${PRIVOXY_PORT:-8118}" -j CONNMARK --restore-mark # For replies
  echo "[INFO] CONNMARK rules for Privoxy (port ${PRIVOXY_PORT:-8118}) applied."
else
  echo "[INFO] Privoxy is disabled."
fi

# Create a flag file indicating VPN script completed successfully
# This is mostly for the healthcheck or external monitoring.
touch /tmp/vpn_setup_complete
echo "[INFO] VPN setup script finished. Container should now be routing traffic through VPN (if connection was successful)."
echo "[INFO] Final VPN interface: $(cat $VPN_INTERFACE_FILE)"
echo "[INFO] Transmission UI should be accessible on host port 9091."
if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
  echo "[INFO] Privoxy should be accessible on host port ${PRIVOXY_PORT:-8118}."
fi
date
echo "[INFO] --- End of vpn-setup.sh ---"

exit 0
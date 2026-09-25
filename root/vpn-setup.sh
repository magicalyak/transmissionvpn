#!/command/with-contenv bash
# shellcheck shell=bash
# FIXED VERSION: This script sets up the VPN connection (OpenVPN or WireGuard)
# and configures iptables for policy-based routing.
# 
# BUG FIX: Ensures proper newlines when appending OpenVPN configuration directives

set -e # Exit immediately if a command exits with a non-zero status.
# set -x # Uncomment for debugging

echo "[INFO] Starting FIXED VPN setup script..."
date

# Ensure /tmp exists and is writable
mkdir -p /tmp
chmod 777 /tmp

# Log all output of this script to /tmp/vpn-setup.log for debugging via docker exec,
# and to stdout/stderr so it also lands in `docker logs`.
#
# Do NOT point stdout at the file before setting up the tee. `exec &> file` followed by
# `exec > >(tee -a file)` starts each tee with the file already installed as its own
# stdout, so tee writes the data back into the file instead of to the console and nothing
# after this point ever reaches `docker logs`. That made every diagnostic this script
# prints - including the `set -e` abort path - invisible from outside the container.
# Truncate the file up front, then tee to the console fds that are still attached.
: > /tmp/vpn-setup.log
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

# VPN server parsing and kill switch exceptions, shared with vpn-monitor.
remote_log() { echo "[INFO] $*"; }
# shellcheck source=root/vpn-remotes.sh
. "${VPN_REMOTES_LIB:-/usr/local/bin/vpn-remotes.sh}"

# Rules that only exist while the tunnel comes up carry this comment, so they can
# be removed once the kill switch is built without flushing the chains again.
BOOTSTRAP_TAG="vpn-bootstrap"

# The nat and mangle rules this script adds carry this comment. Those tables are
# not flushed: on Docker user-defined networks the nat table holds the DNAT and
# SNAT rules that make the embedded DNS server at 127.0.0.11 work.
SETUP_TAG="vpn-setup"

# The nameservers the VPN client resolves its server through. Docker's embedded DNS
# server (127.0.0.11) lists its upstreams as "# ExtServers: [host(192.168.1.1) 1.1.1.1]".
# It queries host(...) entries from the host's network namespace, outside this
# firewall, and the others (--dns overrides) from this one, so those go out eth0.
bootstrap_nameservers() {
  {
    awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf
    sed -n 's/^# ExtServers: \[\(.*\)\]$/\1/p' /etc/resolv.conf | tr ' ' '\n' | grep -v '^host(' || true
  } 2>/dev/null | awk 'NF && !seen[$0]++'
}

# Let the VPN client resolve its server while nothing else can use DNS: only to
# the nameservers above, and only if a server is a hostname.
bootstrap_allow_dns() {
  local ns
  while read -r ns; do
    vpn_is_ipv4 "$ns" || continue
    if [[ "$ns" == 127.* ]]; then
      echo "[INFO] Nameserver $ns is on loopback, which stays open until the tunnel is up."
      continue
    fi
    echo "[INFO] Allowing DNS to $ns on eth0 until the tunnel is up (VPN server is a hostname)."
    iptables -A OUTPUT -o eth0 -d "$ns" -p udp --dport 53 -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
    iptables -A OUTPUT -o eth0 -d "$ns" -p tcp --dport 53 -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
  done < <(bootstrap_nameservers)
}

# delete_tagged TABLE TAG CHAIN... removes the rules carrying TAG. Deleting the -S
# spec with -A turned into -D keeps this exact, whatever the rule matched.
delete_tagged() {
  local table="$1" tag="$2" chain rule
  shift 2
  for chain in "$@"; do
    while read -r rule; do
      [ -n "$rule" ] || continue
      eval "iptables -t $table ${rule/-A /-D }" || true
    done < <(iptables -t "$table" -S "$chain" 2>/dev/null | grep -E -- "--comment \"?$tag\"?( |$)" || true)
  done
}

# Remove every bootstrap rule.
bootstrap_clear() {
  delete_tagged filter "$BOOTSTRAP_TAG" INPUT OUTPUT
  echo "[INFO] Removed tunnel bootstrap rules."
}

# Function to find OpenVPN credentials
find_vpn_credentials() {
  # Clear any stale credentials file
  rm -f /tmp/vpn-credentials

  # Priority 1: Check for Docker secrets using FILE__ prefix convention
  # This supports both FILE__VPN_USER and FILE__VPN_PASS
  VPN_USER_FROM_FILE=""
  VPN_PASS_FROM_FILE=""
  
  if [ -n "$FILE__VPN_USER" ] && [ -f "$FILE__VPN_USER" ] && [ -r "$FILE__VPN_USER" ]; then
    echo "[INFO] Reading VPN username from Docker secret: $FILE__VPN_USER"
    VPN_USER_FROM_FILE=$(head -n 1 "$FILE__VPN_USER" | tr -d '\n\r')
    if [ -n "$VPN_USER_FROM_FILE" ]; then
      echo "[INFO] VPN username successfully read from Docker secret."
    else
      echo "[WARN] Docker secret file $FILE__VPN_USER is empty."
    fi
  fi
  
  if [ -n "$FILE__VPN_PASS" ] && [ -f "$FILE__VPN_PASS" ] && [ -r "$FILE__VPN_PASS" ]; then
    echo "[INFO] Reading VPN password from Docker secret: $FILE__VPN_PASS"
    VPN_PASS_FROM_FILE=$(head -n 1 "$FILE__VPN_PASS" | tr -d '\n\r')
    if [ -n "$VPN_PASS_FROM_FILE" ]; then
      echo "[INFO] VPN password successfully read from Docker secret."
    else
      echo "[WARN] Docker secret file $FILE__VPN_PASS is empty."
    fi
  fi
  
  # Use Docker secrets if both are available
  if [ -n "$VPN_USER_FROM_FILE" ] && [ -n "$VPN_PASS_FROM_FILE" ]; then
    echo "[INFO] Using VPN credentials from Docker secrets."
    echo "$VPN_USER_FROM_FILE" > /tmp/vpn-credentials
    echo "$VPN_PASS_FROM_FILE" >> /tmp/vpn-credentials
    
    # Secure the credentials file
    chmod 600 /tmp/vpn-credentials
    
    if [ -s /tmp/vpn-credentials ] && [ "$(wc -l < /tmp/vpn-credentials)" -ge 2 ]; then
      echo "[INFO] Credentials successfully written to /tmp/vpn-credentials from Docker secrets."
      return 0
    else
      echo "[WARN] Docker secrets were provided but resulted in an empty or incomplete credential file. Clearing."
      rm -f /tmp/vpn-credentials
    fi
  elif [ -n "$VPN_USER_FROM_FILE" ] || [ -n "$VPN_PASS_FROM_FILE" ]; then
    echo "[WARN] Only one of FILE__VPN_USER or FILE__VPN_PASS was provided. Both are required for Docker secrets authentication."
  fi

  # Priority 2: VPN_USER and VPN_PASS from environment.
  if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[INFO] Using VPN_USER and VPN_PASS from environment variables."
    echo "$VPN_USER" > /tmp/vpn-credentials
    echo "$VPN_PASS" >> /tmp/vpn-credentials
    
    # Secure the credentials file
    chmod 600 /tmp/vpn-credentials
    
    if [ -s /tmp/vpn-credentials ] && [ "$(wc -l < /tmp/vpn-credentials)" -ge 2 ]; then
        echo "[INFO] Credentials successfully written to /tmp/vpn-credentials from environment variables."
        return 0
    else
        echo "[WARN] VPN_USER and/or VPN_PASS were provided but resulted in an empty or incomplete credential file. Clearing."
        rm -f /tmp/vpn-credentials
    fi
  fi

  # Priority 3: Fixed credentials file path /config/openvpn/credentials.txt
  FIXED_CRED_PATH="/config/openvpn/credentials.txt"
  if [ -f "$FIXED_CRED_PATH" ] && [ -r "$FIXED_CRED_PATH" ]; then
    echo "[INFO] Checking for credentials file at fixed path: $FIXED_CRED_PATH"
    # Ensure the file is not empty and has at least two lines (user & pass)
    if [ -s "$FIXED_CRED_PATH" ] && [ "$(wc -l < "$FIXED_CRED_PATH")" -ge 2 ]; then
      echo "[INFO] Using OpenVPN credentials from $FIXED_CRED_PATH."
      cp "$FIXED_CRED_PATH" /tmp/vpn-credentials
      
      # Secure the credentials file
      chmod 600 /tmp/vpn-credentials
      
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
    echo "[INFO] No credentials file found at $FIXED_CRED_PATH (this is okay if using VPN_USER/PASS or Docker secrets, or if your VPN config doesn't need separate auth)."
  fi
  
  # If no method yielded credentials
  echo "[WARN] No valid VPN credentials provided via Docker secrets (FILE__VPN_USER/FILE__VPN_PASS), environment variables (VPN_USER/VPN_PASS), or at $FIXED_CRED_PATH."
  echo "[INFO] If your OpenVPN configuration requires username/password authentication and doesn't embed them, connection may fail."
  return 1 
}

# Function to start OpenVPN
# Explain a missing VPN config file.
#
# The usual cause is a bind mount that does not point where the operator thinks it does:
# /config comes from a host directory named by a relative path in docker-compose.yml, and
# relative volume paths resolve against the compose file's own directory rather than the
# working directory. On top of that, 01-ensure-vpn-config-dirs.sh creates /config/openvpn
# and /config/wireguard when they are absent, so a wrong mount shows up as an *empty*
# directory instead of a missing one, and "it's right there on the host" looks like a
# container bug. Print what the container can actually see so the mismatch is obvious.
report_missing_vpn_config() {
  local dir="$1"
  echo "[ERROR] Contents of $dir, as this container sees it:"
  if [ -d "$dir" ]; then
    # shellcheck disable=SC2012  # a human-readable listing is the point here:
    # permissions and ownership are part of what makes a wrong mount recognisable.
    ls -la "$dir" 2>&1 | sed 's/^/[ERROR]   /'
  else
    echo "[ERROR]   (no such directory)"
  fi
  echo "[ERROR]"
  echo "[ERROR] If the file exists on the host but is not listed above, then /config is"
  echo "[ERROR] bound to a different host directory than you expect. Relative volume paths"
  echo "[ERROR] in docker-compose.yml are resolved against the directory holding the compose"
  echo "[ERROR] file, not the directory you ran docker compose from. Compare the two with:"
  echo "[ERROR]"
  echo "[ERROR]   docker exec <container> ls -la /config/openvpn /config/wireguard"
  echo '[ERROR]   docker inspect <container> --format "{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}"'
}

start_openvpn() {
  echo "[INFO] Setting up OpenVPN..."
  OVPN_CONFIG_FILE=""
  if [ -n "$VPN_CONFIG" ]; then
    if [ -f "$VPN_CONFIG" ]; then
      OVPN_CONFIG_FILE="$VPN_CONFIG"
      echo "[INFO] Using OpenVPN config: $OVPN_CONFIG_FILE"
    else
      echo "[ERROR] Specified VPN_CONFIG=$VPN_CONFIG not found inside the container."
      report_missing_vpn_config "$(dirname "$VPN_CONFIG")"
      exit 1
    fi
  else
    # Try to find the first .ovpn file in /config/openvpn
    OVPN_CONFIG_FILE=$(find /config/openvpn -maxdepth 1 -name '*.ovpn' -print -quit)
    if [ -z "$OVPN_CONFIG_FILE" ]; then
      echo "[ERROR] No OpenVPN configuration file specified via VPN_CONFIG and none found in /config/openvpn."
      report_missing_vpn_config /config/openvpn
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
  cat << 'EOF' > /etc/openvpn/update-resolv.sh
#!/bin/bash
# Script to update resolv.conf with DNS servers from OpenVPN
set -x # For debugging individual commands in this script

echo "--- OpenVPN UP script started ---" | tee -a /tmp/openvpn.log
date | tee -a /tmp/openvpn.log

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
if [ -n "$NAME_SERVERS" ]; then
  echo "[INFO] Using NAME_SERVERS: $NAME_SERVERS" | tee -a /tmp/openvpn.log
  # Use sed to transform comma-separated list directly to nameserver lines
  echo "$NAME_SERVERS" | sed -e 's/,/\nnameserver /g' -e 's/^/nameserver /' >> "/tmp/resolv.conf.openvpn"
else
  # Option 2: Try to parse foreign_option_ variables for DNS (pushed by VPN server)
  echo "[INFO] NAME_SERVERS not set, trying to use DNS from VPN (foreign_option_X)" | tee -a /tmp/openvpn.log
  dns_found=0
  for option_var_name in $(env | grep '^foreign_option_' | cut -d= -f1); do
    option_var_value=$(eval echo "\"\$$option_var_name\"")
    if echo "$option_var_value" | grep -q '^dhcp-option DNS'; then
      dns_server=$(echo "$option_var_value" | cut -d' ' -f3)
      echo "nameserver $dns_server" >> "/tmp/resolv.conf.openvpn"
      echo "[INFO] Added DNS server from VPN: $dns_server" | tee -a /tmp/openvpn.log
      dns_found=1
    fi
  done
  if [ $dns_found -eq 0 ]; then
      echo "[WARN] No DNS servers pushed by VPN, and NAME_SERVERS not set. Using fallbacks." | tee -a /tmp/openvpn.log
      echo "nameserver 1.1.1.1" >> "/tmp/resolv.conf.openvpn" # Cloudflare
      echo "nameserver 8.8.8.8" >> "/tmp/resolv.conf.openvpn" # Google
  fi
fi

# Atomically replace resolv.conf
# Check if /tmp/resolv.conf.openvpn has content beyond the initial comment
if [ $(grep -cv '^#' /tmp/resolv.conf.openvpn) -gt 0 ]; then
  cp "/tmp/resolv.conf.openvpn" "/etc/resolv.conf"
  echo "Updated /etc/resolv.conf" | tee -a /tmp/openvpn.log
else
  echo "[WARN] /tmp/resolv.conf.openvpn was empty or only comments. Not updating /etc/resolv.conf." | tee -a /tmp/openvpn.log
fi

# Create a flag file to indicate the 'up' script has completed
# This helps the main vpn-setup.sh script to know when tun0 is likely configured
echo "OpenVPN UP script completed. Interface: $dev" > /tmp/openvpn_up_complete
# Record which remote we actually connected to; it is not necessarily the first.
echo "$trusted_ip $trusted_port" > /tmp/openvpn_connected_remote
echo "[INFO] OpenVPN UP script for $dev completed (flag file created)." | tee -a /tmp/openvpn.log
exit 0
EOF

  cat << 'EOF' > /etc/openvpn/restore-resolv.sh
#!/bin/bash
# Script to restore original resolv.conf
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
rm -f /tmp/openvpn_up_complete /tmp/openvpn_connected_remote
echo "[INFO] OpenVPN DOWN script for $dev completed (flag file removed)." | tee -a /tmp/openvpn.log
exit 0
EOF

  chmod +x /etc/openvpn/update-resolv.sh /etc/openvpn/restore-resolv.sh

  # Modify OVPN config on the fly for auth-user-pass and script security
  TEMP_OVPN_CONFIG="/tmp/config.ovpn"
  cp "$OVPN_CONFIG_FILE" "$TEMP_OVPN_CONFIG"
  
  # BUG FIX: Ensure the config file ends with a newline before appending
  echo "[INFO] Ensuring OpenVPN config ends with newline before modifications..."
  if [ -s "$TEMP_OVPN_CONFIG" ]; then
    # Check if file ends with newline, if not add one
    if [ "$(tail -c1 "$TEMP_OVPN_CONFIG" | wc -l)" -eq 0 ]; then
      echo "" >> "$TEMP_OVPN_CONFIG"
      echo "[INFO] Added missing newline to end of OpenVPN config"
    fi
  fi
  
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

  echo "[INFO] OpenVPN config modifications completed. Final config:"
  echo "[DEBUG] Last 10 lines of modified config:"
  tail -10 "$TEMP_OVPN_CONFIG"

  # The firewall is locked down (see the flush below); open it for the VPN servers only.
  if vpn_remotes_need_dns "$TEMP_OVPN_CONFIG"; then
    bootstrap_allow_dns
  fi
  vpn_allow_remotes "$TEMP_OVPN_CONFIG" append -m comment --comment "$BOOTSTRAP_TAG"

  echo "[INFO] Starting OpenVPN client..."
  rm -f /tmp/openvpn_connected_remote
  # Using exec to replace the shell process with openvpn is not suitable here as we need to run commands after it.
  # Run OpenVPN in the background. s6 will manage its lifecycle if needed as part of this init script.
  # shellcheck disable=SC2086 # Word splitting is intentional for VPN_OPTIONS
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
          echo "[ERROR] Specified VPN_CONFIG (for WireGuard) = $VPN_CONFIG not found inside the container."
          report_missing_vpn_config "$(dirname "$VPN_CONFIG")"
          exit 1
      fi
  else
      # Try to find the first .conf file in /config/wireguard
      WG_CONF_FOUND=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
      if [ -z "$WG_CONF_FOUND" ]; then
          echo "[ERROR] No WireGuard configuration file specified via VPN_CONFIG and none found in /config/wireguard."
          report_missing_vpn_config /config/wireguard
          exit 1
      else
          WG_CONFIG="$WG_CONF_FOUND"
          echo "[INFO] Automatically selected WireGuard config: $WG_CONFIG"
          # Update VPN_INTERFACE_FILE based on found config, if VPN_CONFIG was not explicitly set
          basename "$WG_CONFIG" .conf > "$VPN_INTERFACE_FILE"
      fi
  fi
  INTERFACE_NAME=$(cat "$VPN_INTERFACE_FILE")
  # The firewall is locked down (see the flush below); open it for the peers only.
  if vpn_wg_endpoints_need_dns "$WG_CONFIG"; then
    bootstrap_allow_dns
  fi
  vpn_allow_wg_endpoints "$WG_CONFIG" append -m comment --comment "$BOOTSTRAP_TAG"
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
  elif ! awk '$1 == "nameserver" && $2 !~ /^127\./ { found = 1 } END { exit !found }' /etc/resolv.conf 2>/dev/null; then
    # Still Docker's embedded DNS server, which is closed once the kill switch is
    # built. Same fallback as the OpenVPN up script.
    echo "[WARN] No DNS set by the WireGuard config or NAME_SERVERS. Using 1.1.1.1 and 8.8.8.8 through the tunnel."
    if [ ! -f "/tmp/resolv.conf.backup" ]; then
      if [ -f "/etc/resolv.conf" ]; then cp "/etc/resolv.conf" "/tmp/resolv.conf.backup"; fi
    fi
    printf '# Generated by vpn-setup.sh for WireGuard (fallback)\nnameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /tmp/resolv.conf.wireguard
    cp "/tmp/resolv.conf.wireguard" "/etc/resolv.conf"
  fi
}

# Fail closed if this script aborts.
#
# Everything from the flush below until the strict policies are re-applied runs with the
# firewall wide open, so the tunnel handshake can get out. If the script dies anywhere in
# that window - a VPN_CONFIG that does not resolve, rejected credentials, a tunnel that
# never gets an IP - it used to leave the container with empty chains and ACCEPT policies
# while Transmission was already up and listening: no VPN, and no kill switch either.
# Observed in the wild in #36, where a bind mount pointed at the wrong host directory.
#
# This trap is the only thing that protects a failed setup, so do not assume s6 will
# catch it. A non-zero /etc/cont-init.d script only stops the container when
# S6_BEHAVIOUR_IF_STAGE2_FAILS=2, and that variable is set neither here nor in
# lscr.io/linuxserver/transmission (verified against the image config for
# 4.1.3-r0-ls362), so the default applies and the container stays up. That matches
# what #33 and #36 both showed: setup aborted and the container kept running and
# logging for minutes.
#
# Lock the firewall down instead. Loopback only: nothing reaches the network until setup
# succeeds. That deliberately takes the web UI down too - a container that failed to build
# its kill switch should not look reachable and healthy - but `docker logs` and
# `docker exec` are unaffected, so the error above is still there to read.
# shellcheck disable=SC2329  # invoked indirectly, via the EXIT trap below.
fail_closed_on_abort() {
  local rc=$?
  [ "$rc" -eq 0 ] && return 0

  echo "[ERROR] vpn-setup.sh aborted (exit $rc) before the kill switch was in place."
  echo "[ERROR] Locking the firewall down: nothing leaves this container until VPN setup"
  echo "[ERROR] succeeds. Fix the error reported above and restart the container."

  iptables -P INPUT   DROP 2>/dev/null || true
  iptables -P OUTPUT  DROP 2>/dev/null || true
  iptables -P FORWARD DROP 2>/dev/null || true
  iptables -F INPUT   2>/dev/null || true
  iptables -F OUTPUT  2>/dev/null || true
  iptables -F FORWARD 2>/dev/null || true
  iptables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
  # Docker's embedded DNS server would forward from the host; see the kill switch.
  iptables -A OUTPUT -o lo -d 127.0.0.11 -j DROP 2>/dev/null || true
  iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

  ip6tables -P INPUT   DROP 2>/dev/null || true
  ip6tables -P OUTPUT  DROP 2>/dev/null || true
  ip6tables -P FORWARD DROP 2>/dev/null || true
  ip6tables -F INPUT   2>/dev/null || true
  ip6tables -F OUTPUT  2>/dev/null || true
  ip6tables -F FORWARD 2>/dev/null || true
  ip6tables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
  ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

  # The completion flag is not removed at the top of this script, so an in-place re-run
  # by vpn-monitor's attempt_vpn_restart() would otherwise leave a stale flag from the
  # previous successful run claiming that setup finished.
  rm -f /tmp/vpn_setup_complete

  echo "[ERROR] Firewall locked down (loopback only)."
  return "$rc"
}
trap fail_closed_on_abort EXIT

# Flush iptables BEFORE bringing the VPN tunnel up, and keep it locked down.
#  - wg-quick / OpenVPN configs commonly include PostUp / up hooks that install
#    iptables rules (typical with provider-supplied configs). Flushing AFTER the
#    tunnel is up would wipe those rules, so flush BEFORE.
#  - The policies stay DROP. This used to reset them to ACCEPT so the handshake
#    could get out, which opened everything while the tunnel came up: at boot,
#    where Transmission can already be running, and on every vpn-monitor restart,
#    where the tunnel routes are gone and the default route is eth0. Now only the
#    VPN servers are allowed out (added by start_openvpn / start_wireguard), plus
#    replies to inbound web UI and metrics connections so probes keep passing.
#    Those rules are tagged and removed once the real kill switch is built below.
iptables -P INPUT  DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP
iptables -F INPUT
iptables -F FORWARD
iptables -F OUTPUT
# Only this script's own mangle rules (CONNMARK for replies on eth0) are removed,
# so a rerun does not duplicate them. nat is left alone; see SETUP_TAG.
delete_tagged mangle "$SETUP_TAG" PREROUTING OUTPUT
ip6tables -P INPUT DROP   2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP  2>/dev/null || true
ip6tables -F INPUT        2>/dev/null || true
ip6tables -F FORWARD      2>/dev/null || true
ip6tables -F OUTPUT       2>/dev/null || true
ip6tables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
iptables -A INPUT  -i lo -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
iptables -A OUTPUT -o lo -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
iptables -A INPUT  -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
iptables -A INPUT  -i eth0 -p tcp --dport 9091 -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
if [ "${METRICS_ENABLED,,}" = "true" ]; then
  iptables -A INPUT -i eth0 -p tcp --dport "${METRICS_PORT:-9099}" -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
fi
# Replies to those inbound connections only; nothing the container starts itself.
iptables -A OUTPUT -o eth0 -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -m comment --comment "$BOOTSTRAP_TAG" -j ACCEPT
echo "[INFO] Flushed iptables; only the VPN servers are allowed out until the tunnel is up."

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

# Set default policies
# NB: iptables is no longer flushed here. The flush happens before the
# tunnel is brought up so PostUp hooks survive (see earlier in this script).
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP # Changed to DROP by default for stronger killswitch
echo "[INFO] Set default iptables policies (INPUT/FORWARD/OUTPUT DROP)."

# IPv6 killswitch. Without this, IPv6 traffic egresses on eth0 outside the
# tunnel if the host pushes an IPv6 default route, which is a real leak in
# any IPv6-capable environment. Soft-fail with || true on hosts where the
# kernel ip6tables module is absent (e.g. CONFIG_IP6_NF_IPTABLES=n).
ip6tables -P INPUT DROP   2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP  2>/dev/null || true
ip6tables -F INPUT        2>/dev/null || true
ip6tables -F FORWARD      2>/dev/null || true
ip6tables -F OUTPUT       2>/dev/null || true
ip6tables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
ip6tables -A INPUT  -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
echo "[INFO] IPv6 killswitch applied (drop all except loopback + established)."

# Docker's embedded DNS server is only for resolving the VPN servers. From Docker
# 28 it forwards to the host's nameservers from the host's network namespace, so a
# lookup through it would bypass the kill switch and the tunnel.
iptables -A OUTPUT -o lo -d 127.0.0.11 -j DROP

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
echo "[INFO] Allowed loopback traffic."

# CRITICAL KILLSWITCH: Block all DNS except through VPN
# This prevents DNS leaks when VPN is down
iptables -A OUTPUT -p udp --dport 53 -o eth0 -j DROP
iptables -A OUTPUT -p tcp --dport 53 -o eth0 -j DROP
echo "[INFO] Blocked DNS queries on eth0 (killswitch protection)."

# Allow established and related connections (standard rule)
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
# Established traffic may leave through the tunnel, but on eth0 only as replies to
# inbound connections (web UI, metrics, Privoxy). A connection opened through the
# tunnel stays ESTABLISHED after the tunnel's routes are gone, and would otherwise
# follow the default route out of eth0.
iptables -A OUTPUT ! -o eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -m conntrack --ctstate RELATED,ESTABLISHED --ctdir REPLY -j ACCEPT
# For FORWARD chain as well, if container were to act as a router for others (not typical for this use case but good practice)
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "[INFO] Allowed established/related connections."

# Allow Transmission UI access from host (Docker for Mac via 127.0.0.1 proxies to eth0 IP)
iptables -A INPUT -i eth0 -p tcp --dport 9091 -j ACCEPT
echo "[INFO] Added iptables rule to allow Transmission UI on eth0:9091."

# Allow metrics server access if enabled
if [ "${METRICS_ENABLED,,}" = "true" ]; then
  iptables -A INPUT -i eth0 -p tcp --dport "${METRICS_PORT:-9099}" -j ACCEPT
  echo "[INFO] Added iptables rule to allow metrics server on eth0:${METRICS_PORT:-9099}."
fi

# BitTorrent peer port: reachable through the tunnel, never on eth0.
#
# This block used to ACCEPT $TRANSMISSION_PEER_PORT on eth0, which contradicted
# the kill switch's intent that peer traffic only ever crosses the VPN
# interface: any peer able to route to the container's eth0 address reached the
# client off-tunnel. The container refuses to start without a VPN client (see
# the VPN_CLIENT check above), so there was no non-VPN deployment of this image
# that the eth0 ACCEPT was serving.
#
# The rules are asserted through the shared helper, which prefers the live PIA
# forwarded port recorded in /tmp/pia_forwarded_port and falls back to
# $TRANSMISSION_PEER_PORT. That fallback matters on an in-place re-run of this
# script (vpn-monitor's auto-restart invokes it): the flush near the top wipes
# the PIA rules, and that in-place re-run bypasses s6-rc, so the
# pia-port-forward oneshot is not re-run to restore them. Without re-asserting
# here the forwarded port stays firewalled off until the container is recreated
# - inbound peers dropped while every log line reports success.
if [ -x /usr/local/bin/pia-pf-firewall.sh ]; then
  # Never fatal: having no peer port at all is normal (first boot, before PIA
  # port forwarding has run) and this script runs under `set -e`. The helper
  # logs its own ERROR if a rule is configured but cannot be installed.
  /usr/local/bin/pia-pf-firewall.sh apply "$VPN_INTERFACE" || true
fi

# Policy routing for Transmission UI & Privoxy when accessed from host
# This ensures replies to connections hitting eth0 go back out via eth0 gateway, not VPN tunnel
echo "[INFO] Adding CONNMARK policy routing for UI access (mark 0x1, table 100)"

if [ -n "$ETH0_IP" ]; then
  echo "[INFO] Using specific eth0 IP $ETH0_IP for PREROUTING CONNMARK rules."
  # 1. On incoming connections to Transmission on eth0, mark the connection
  iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 9091 -m comment --comment "$SETUP_TAG" -j CONNMARK --set-mark 0x1
else
  echo "[WARN] ETH0_IP not found. Using less specific -i eth0 for PREROUTING CONNMARK rule for Transmission."
  iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 9091 -m comment --comment "$SETUP_TAG" -j CONNMARK --set-mark 0x1
fi

# 2. Restore mark on packets belonging to these connections in OUTPUT chain
iptables -t mangle -A OUTPUT -p tcp --sport 9091 -m comment --comment "$SETUP_TAG" -j CONNMARK --restore-mark
# 3. Create a routing rule to use table 100 if mark is 0x1
ip rule add fwmark 0x1 lookup 100 priority 1000 2>/dev/null || true
# 4. Add a default route to table 100 via "$ETH0_GATEWAY" dev eth0 table 100
ip route add default via "$ETH0_GATEWAY" dev eth0 table 100 2>/dev/null || true

echo "[INFO] CONNMARK rules for Transmission UI (port 9091) applied."

# Add CONNMARK rules for metrics server if enabled
if [ "${METRICS_ENABLED,,}" = "true" ]; then
  if [ -n "$ETH0_IP" ]; then
    echo "[INFO] Adding CONNMARK rules for metrics server on port ${METRICS_PORT:-9099} to $ETH0_IP"
    iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport "${METRICS_PORT:-9099}" -m comment --comment "$SETUP_TAG" -j CONNMARK --set-mark 0x1
  else
    echo "[WARN] ETH0_IP not found, using less specific -i eth0 for PREROUTING CONNMARK rule for metrics server."
    iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport "${METRICS_PORT:-9099}" -m comment --comment "$SETUP_TAG" -j CONNMARK --set-mark 0x1
  fi
  iptables -t mangle -A OUTPUT -p tcp --sport "${METRICS_PORT:-9099}" -m comment --comment "$SETUP_TAG" -j CONNMARK --restore-mark
  echo "[INFO] CONNMARK rules for metrics server (port ${METRICS_PORT:-9099}) applied."
fi

# VPN is up, redirect all other OUTPUT traffic through VPN interface
# This is the main "kill switch" part.
# All OUTPUT not matching previous rules (like loopback, PBR for UI)
# and not going to LAN_NETWORK, will be forced via VPN.

# If LAN_NETWORK is set, allow traffic to it without VPN
if [ -n "$LAN_NETWORK" ]; then
  echo "[INFO] LAN_NETWORK ($LAN_NETWORK) is set. Adding route and iptables exception."
  # Add route for LAN_NETWORK to go via eth0's gateway.
  # Use `replace`, not `add`: on a container restart within the same pod
  # network namespace, this route already exists from the prior run, and
  # `ip route add` would fail with "File exists". Under `set -e` that
  # aborts the script before the LAN/VPN ACCEPT rules and the final
  # /tmp/vpn_setup_complete flag are written, leaving the kill switch stuck
  # in its most restrictive state and vpn-monitor waiting forever.
  ip route replace "$LAN_NETWORK" via "$ETH0_GATEWAY" dev eth0
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

# KILL SWITCH FIX: Allow OpenVPN/WireGuard traffic to VPN server before applying kill switch
if [ "${VPN_CLIENT,,}" = "openvpn" ] && [ -f "$OVPN_CONFIG_FILE" ]; then
  # Every remote, not just the first: a fallback remote without an exception can
  # never connect. Hostnames resolve through the tunnel, which is up by now and
  # already allowed above, so no DNS is opened on eth0.
  vpn_allow_remotes "$OVPN_CONFIG_FILE" append
elif [ "${VPN_CLIENT,,}" = "wireguard" ] && [ -f "$WG_CONFIG" ]; then
  # Every peer endpoint, the same way.
  vpn_allow_wg_endpoints "$WG_CONFIG" append
fi

# The permanent rules are all in place; drop the bootstrap ones.
bootstrap_clear

# Strict killswitch: Drop ALL traffic not explicitly allowed
iptables -A OUTPUT -j DROP
echo "[INFO] Killswitch active: All non-VPN traffic blocked (except explicitly allowed rules)."

# Privoxy: Apply firewall and PBR rules if enabled (s6 will start the service)
if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
  echo "[INFO] Privoxy is enabled. Ensuring firewall and PBR rules for port ${PRIVOXY_PORT:-8118}."
  iptables -A INPUT -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j ACCEPT # Allow incoming to Privoxy

  if [ -n "$ETH0_IP" ]; then
    echo "[INFO] Adding CONNMARK rules for Privoxy on port ${PRIVOXY_PORT:-8118} to $ETH0_IP"
    iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport "${PRIVOXY_PORT:-8118}" -m comment --comment "$SETUP_TAG" -j CONNMARK --set-mark 0x1
  else
    echo "[WARN] ETH0_IP not found, using less specific -i eth0 for PREROUTING CONNMARK rule for Privoxy."
    iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -m comment --comment "$SETUP_TAG" -j CONNMARK --set-mark 0x1
  fi
  iptables -t mangle -A OUTPUT -p tcp --sport "${PRIVOXY_PORT:-8118}" -m comment --comment "$SETUP_TAG" -j CONNMARK --restore-mark # For replies
  echo "[INFO] CONNMARK rules for Privoxy (port ${PRIVOXY_PORT:-8118}) applied."
else
  echo "[INFO] Privoxy is disabled."
fi

# Create a flag file indicating VPN script completed successfully
# This is mostly for the healthcheck or external monitoring.
touch /tmp/vpn_setup_complete
echo "[INFO] FIXED VPN setup script finished. Container should now be routing traffic through VPN (if connection was successful)."
echo "[INFO] Final VPN interface: $(cat $VPN_INTERFACE_FILE)"
echo "[INFO] Transmission UI should be accessible on host port 9091."
if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
  echo "[INFO] Privoxy should be accessible on host port ${PRIVOXY_PORT:-8118}."
fi
date
echo "[INFO] --- End of FIXED vpn-setup.sh ---"

exit 0 
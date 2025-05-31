#!/command/with-contenv bash

# Script to initialize VPN connection
#
echo "[INFO] Starting NZBGet + VPN container"

# Default to openvpn if not specified
VPN_CLIENT=${VPN_CLIENT:-openvpn}
echo "[INFO] Selected VPN Client: $VPN_CLIENT"

if [ "$DEBUG" = "true" ] || [ "$DEBUG" = "yes" ]; then
  echo "[DEBUG] Debug mode enabled. Activating set -x."
  set -x
fi

# Function to write credentials to a file
write_creds() {
  local user=$1
  local pass=$2
  local creds_file="/config/openvpn/credentials" # Standardized path
  echo "[INFO] Writing credentials to $creds_file"
  echo "$user" > "$creds_file"
  echo "$pass" >> "$creds_file"
  chmod 600 "$creds_file"
}

# Function to find a single .ovpn or .conf file
find_single_config() {
  local dir=$1
  local ext1=$2
  local ext2=$3
  local files
  local count

  # Find files with the first extension
  files=$(find "$dir" -maxdepth 1 -name "*.$ext1" -print -quit)
  if [ -n "$files" ]; then
    count=$(find "$dir" -maxdepth 1 -name "*.$ext1" | wc -l)
    if [ "$count" -eq 1 ]; then
      echo "$files"
      return
    fi
    if [ "$count" -gt 1 ]; then
        echo "[ERROR] Multiple .$ext1 files found in $dir. Please specify one using VPN_CONFIG or WG_CONFIG_FILE." >&2
        exit 1
    fi
  fi

  # If no files with first extension, try second (if provided)
  if [ -n "$ext2" ]; then
    files=$(find "$dir" -maxdepth 1 -name "*.$ext2" -print -quit)
    if [ -n "$files" ]; then
      count=$(find "$dir" -maxdepth 1 -name "*.$ext2" | wc -l)
      if [ "$count" -eq 1 ]; then
        echo "$files"
        return
      fi
      if [ "$count" -gt 1 ]; then
          echo "[ERROR] Multiple .$ext2 files found in $dir. Please specify one using VPN_CONFIG or WG_CONFIG_FILE." >&2
          exit 1
      fi
    fi
  fi
  echo "" # Return empty if no single file found
}


##################################
### OpenVPN Specific Setup
##################################
if [ "$VPN_CLIENT" = "openvpn" ]; then
  echo "[INFO] Configuring OpenVPN..."
  LOWERCASE_CREDS_FILE="/config/openvpn/credentials" # Preferred lowercase filename
  ENV_FILE_PATH="/app/.env" # Path to a file for storing env vars if needed
  OVERRIDE_CREDS_TXT_FILE="/config/openvpn-credentials.txt" # user-provided .txt override
  LEGACY_UPPERCASE_CREDS_FILE="/config/openvpn/CREDENTIALS" # legacy support

  # Consistently use /config/openvpn/credentials
  # Order of credential precedence:
  # 1. VPN_USER & VPN_PASS (directly from env)
  # 2. /config/openvpn-credentials.txt (user override file)
  # 3. /config/openvpn/credentials (if it already exists and is populated, perhaps by user)
  # 4. /config/openvpn/CREDENTIALS (legacy uppercase)

  if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[INFO] Using VPN_USER and VPN_PASS from direct environment variables."
    write_creds "$VPN_USER" "$VPN_PASS"
  elif [ -f "$OVERRIDE_CREDS_TXT_FILE" ] && [ -s "$OVERRIDE_CREDS_TXT_FILE" ]; then
    echo "[INFO] Using credentials from $OVERRIDE_CREDS_TXT_FILE."
    # Ensure it has two lines
    if [ "$(wc -l < "$OVERRIDE_CREDS_TXT_FILE")" -ge 2 ]; then
      VPN_USER_FILE=$(head -n 1 "$OVERRIDE_CREDS_TXT_FILE")
      VPN_PASS_FILE=$(head -n 2 "$OVERRIDE_CREDS_TXT_FILE" | tail -n 1)
      write_creds "$VPN_USER_FILE" "$VPN_PASS_FILE"
    else
      echo "[WARN] $OVERRIDE_CREDS_TXT_FILE does not contain enough lines for username and password. Skipping."
    fi
  elif [ -f "$LOWERCASE_CREDS_FILE" ] && [ -s "$LOWERCASE_CREDS_FILE" ]; then
    echo "[INFO] Using existing $LOWERCASE_CREDS_FILE."
    # No action needed, file is already in place and populated
  elif [ -f "$LEGACY_UPPERCASE_CREDS_FILE" ] && [ -s "$LEGACY_UPPERCASE_CREDS_FILE" ]; then
    echo "[INFO] Using legacy $LEGACY_UPPERCASE_CREDS_FILE. Copying to $LOWERCASE_CREDS_FILE."
    # Ensure it has two lines before copying
    if [ "$(wc -l < "$LEGACY_UPPERCASE_CREDS_FILE")" -ge 2 ]; then
      VPN_USER_FILE=$(head -n 1 "$LEGACY_UPPERCASE_CREDS_FILE")
      VPN_PASS_FILE=$(head -n 2 "$LEGACY_UPPERCASE_CREDS_FILE" | tail -n 1)
      write_creds "$VPN_USER_FILE" "$VPN_PASS_FILE"
    else
      echo "[WARN] Legacy $LEGACY_UPPERCASE_CREDS_FILE does not contain enough lines. Skipping."
    fi
  else
    echo "[WARN] No VPN credentials provided or found. OpenVPN might fail if config requires auth."
  fi

  # Validate credentials file if it was supposed to be created
  if [ -f "$LOWERCASE_CREDS_FILE" ]; then
      if [ ! -s "$LOWERCASE_CREDS_FILE" ] || [ "$(wc -c < "$LOWERCASE_CREDS_FILE")" -le 1 ]; then # Check if empty or just newline
          echo "[WARN] $LOWERCASE_CREDS_FILE is empty or invalid. OpenVPN might fail if auth is needed."
      fi
  else
      # This case might occur if only VPN_USER was set, or file operations failed.
      echo "[WARN] $LOWERCASE_CREDS_FILE was not created. OpenVPN might fail if auth is needed."
  fi

  OPENVPN_CONFIG_DIR="/config/openvpn"
  SELECTED_OPENVPN_CONFIG="$VPN_CONFIG" # From ENV var

  if [ -z "$SELECTED_OPENVPN_CONFIG" ]; then
      echo "[INFO] VPN_CONFIG is not set. Trying to find a single .ovpn or .conf file in $OPENVPN_CONFIG_DIR"
      SELECTED_OPENVPN_CONFIG=$(find_single_config "$OPENVPN_CONFIG_DIR" "ovpn" "conf")
      if [ -z "$SELECTED_OPENVPN_CONFIG" ]; then
          echo "[ERROR] No OpenVPN config file found in $OPENVPN_CONFIG_DIR, and VPN_CONFIG is not set. Cannot start OpenVPN."
          exit 1
      else
          echo "[INFO] Automatically selected OpenVPN config: $SELECTED_OPENVPN_CONFIG"
      fi
  elif [[ ! -f "$SELECTED_OPENVPN_CONFIG" ]]; then
      # If VPN_CONFIG is set but doesn't include path, prepend default dir
      if [[ ! "$SELECTED_OPENVPN_CONFIG" == /* ]]; then
          SELECTED_OPENVPN_CONFIG="${OPENVPN_CONFIG_DIR}/${SELECTED_OPENVPN_CONFIG}"
      fi
      if [[ ! -f "$SELECTED_OPENVPN_CONFIG" ]]; then
          echo "[ERROR] OpenVPN config file '$SELECTED_OPENVPN_CONFIG' not found. Cannot start OpenVPN."
          exit 1
      fi
  fi

  TEMP_OPENVPN_CONFIG_MODIFIED="/tmp/openvpn_modified.conf"

  echo "[INFO] Preparing OpenVPN temp config $TEMP_OPENVPN_CONFIG_MODIFIED from $SELECTED_OPENVPN_CONFIG"

  # Ensure auth-user-pass uses the standardized credentials file and remove existing ones
  {
    echo "auth-user-pass /config/openvpn/credentials"
    # Comment out existing auth-user-pass lines in the user's config
    sed 's/^[[:space:]]*auth-user-pass.*/# &/' "$SELECTED_OPENVPN_CONFIG"
  } > "$TEMP_OPENVPN_CONFIG_MODIFIED"

  # Ensure script-security 2 and up/down scripts are set
  if ! grep -q "script-security" "$TEMP_OPENVPN_CONFIG_MODIFIED"; then
    echo "script-security 2" >> "$TEMP_OPENVPN_CONFIG_MODIFIED"
  fi
  if ! grep -q "up /etc/openvpn/update-resolv.sh" "$TEMP_OPENVPN_CONFIG_MODIFIED"; then
    echo "up /etc/openvpn/update-resolv.sh" >> "$TEMP_OPENVPN_CONFIG_MODIFIED"
  fi
  if ! grep -q "down /etc/openvpn/restore-resolv.sh" "$TEMP_OPENVPN_CONFIG_MODIFIED"; then
    echo "down /etc/openvpn/restore-resolv.sh" >> "$TEMP_OPENVPN_CONFIG_MODIFIED"
  fi

  # Create up/down scripts for OpenVPN
  mkdir -p /etc/openvpn
  cat << EOF > /etc/openvpn/update-resolv.sh
#!/bin/bash 
# Script to update resolv.conf with DNS servers from OpenVPN
exec &> /tmp/openvpn_script.log
set -x
echo "--- OpenVPN UP script started ---"
date
env # Log environment to see what OpenVPN provides

# Backup original resolv.conf if not already backed up
if [ ! -f "/tmp/resolv.conf.backup" ]; then
  if [ -f "/etc/resolv.conf" ]; then # Only backup if original exists
    cp "/etc/resolv.conf" "/tmp/resolv.conf.backup"
    echo "Backed up /etc/resolv.conf to /tmp/resolv.conf.backup"
  else
    echo "Original /etc/resolv.conf not found, cannot backup." 
  fi
fi

# Start with an empty temp resolv.conf
> "/tmp/resolv.conf.openvpn"

# Option 1: Use NAME_SERVERS if provided from parent environment
if [ -n "$NAME_SERVERS" ]; then
  echo "[INFO] Using NAME_SERVERS: $NAME_SERVERS" | tee -a /tmp/openvpn.log
  echo "# Generated by OpenVPN update-resolv.sh using NAME_SERVERS" > "/tmp/resolv.conf.openvpn"
  
  # Use sed to transform comma-separated list directly to nameserver lines
  # The first sed expression handles multiple IPs by replacing commas with newline + "nameserver "
  # The second sed expression prepends "nameserver " to the very first IP
  echo "$NAME_SERVERS" | sed -e 's/,/\nnameserver /g' -e 's/^/nameserver /' >> "/tmp/resolv.conf.openvpn"
  
else
  # Option 2: Try to parse foreign_option_ variables for DNS (pushed by VPN server)
  echo "[INFO] NAME_SERVERS not set, trying to parse foreign_option_X for DNS" | tee -a /tmp/openvpn.log
  dns_found=0
  for item in $(env | grep '^foreign_option_'); do # Use 'item' to avoid conflict if 'option' is special
    option_value=$(echo "$item" | cut -d '=' -f 2-) # Get value after first '='
    if echo "$option_value" | grep -q "^dhcp-option DNS"; then
      dns_ip=$(echo "$option_value" | awk '{print $3}') # Assumes format 'dhcp-option DNS x.x.x.x'
      if [ -n "$dns_ip" ]; then # Ensure dns_ip is not empty
        if [ "$dns_found" -eq 0 ]; then # First DNS server found
          echo "# Generated by OpenVPN update-resolv.sh from PUSH_REPLY" > "/tmp/resolv.conf.openvpn"
          dns_found=1
        fi
        echo "nameserver $dns_ip" >> "/tmp/resolv.conf.openvpn"
        echo "Found pushed DNS server: $dns_ip" | tee -a /tmp/openvpn.log
      fi
    fi
  done

  # Option 3: Fallback to default DNS if none pushed or provided from NAME_SERVERS
  if [ "$dns_found" -eq 0 ] && [ -z "$NAME_SERVERS" ]; then # Check -z for NAME_SERVERS here
    echo "[INFO] No DNS servers pushed by VPN or provided by NAME_SERVERS. Using fallbacks 1.1.1.1, 8.8.8.8" | tee -a /tmp/openvpn.log
    # Ensure temp file is empty or only has the header before adding fallbacks
    echo "# Generated by OpenVPN update-resolv.sh using fallbacks" > "/tmp/resolv.conf.openvpn"
    echo "nameserver 1.1.1.1" >> "/tmp/resolv.conf.openvpn"
    echo "nameserver 8.8.8.8" >> "/tmp/resolv.conf.openvpn"
  fi
fi

# Apply the new resolv.conf only if the temp file has content
if [ -s "/tmp/resolv.conf.openvpn" ]; then
  cat "/tmp/resolv.conf.openvpn" > "/etc/resolv.conf"
  echo "Applied new /etc/resolv.conf:" | tee -a /tmp/openvpn.log
  cat "/etc/resolv.conf" | tee -a /tmp/openvpn.log
else
  echo "[WARN] Temporary DNS config /tmp/resolv.conf.openvpn is empty. Not overwriting /etc/resolv.conf." | tee -a /tmp/openvpn.log
fi

echo "Signaling OpenVPN UP script completion."
touch /tmp/openvpn_up_complete

echo "--- OpenVPN UP script finished ---"
exit 0
EOF
  chmod +x /etc/openvpn/update-resolv.sh

  cat << EOF > /etc/openvpn/restore-resolv.sh
#!/bin/bash 
# Script to restore resolv.conf after OpenVPN disconnects
exec &> /tmp/openvpn_script.log
set -x
echo "--- OpenVPN DOWN script started ---"
date

if [ -f "/tmp/resolv.conf.backup" ]; then
  echo "Restoring /etc/resolv.conf from /tmp/resolv.conf.backup" | tee -a /tmp/openvpn.log
  cat "/tmp/resolv.conf.backup" > "/etc/resolv.conf"
  rm "/tmp/resolv.conf.backup"
  echo "Applied restored /etc/resolv.conf:" | tee -a /tmp/openvpn.log
  cat "/etc/resolv.conf" | tee -a /tmp/openvpn.log
else
  echo "/tmp/resolv.conf.backup not found, cannot restore." | tee -a /tmp/openvpn.log
fi
echo "--- OpenVPN DOWN script finished ---"
exit 0
EOF
  chmod +x /etc/openvpn/restore-resolv.sh

  echo "[INFO] Starting OpenVPN client (config $TEMP_OPENVPN_CONFIG_MODIFIED, options: $VPN_OPTIONS)"
  # Start OpenVPN in daemon mode
  # Log to /tmp/openvpn.log (appended by up/down scripts)
  openvpn --config "$TEMP_OPENVPN_CONFIG_MODIFIED" \
          --daemon \
          --verb 4 \
          --writepid /run/openvpn.pid \
          --log /tmp/openvpn.log \
          $VPN_OPTIONS

  # Wait for the OpenVPN UP script to signal completion via the flag file
  echo "[INFO] Waiting up to 30 seconds for OpenVPN UP script to complete (waits for /tmp/openvpn_up_complete)..."
  VPN_UP_FLAG_FILE="/tmp/openvpn_up_complete"
  for i in $(seq 1 30); do
    if [ -f "$VPN_UP_FLAG_FILE" ]; then
      echo "[INFO] OpenVPN UP script completed (flag file found)."
      break
    fi
    echo "[DEBUG] Waiting for $VPN_UP_FLAG_FILE... (Attempt $i/30)"
    sleep 1
  done

  if [ ! -f "$VPN_UP_FLAG_FILE" ]; then
    echo "[ERROR] OpenVPN UP script did not complete in time (flag file $VPN_UP_FLAG_FILE not found)."
    echo "[ERROR] Check /tmp/openvpn.log and /tmp/openvpn_script.log for errors."
    # Optionally, dump logs here
    cat /tmp/openvpn.log 2>/dev/null || echo "No /tmp/openvpn.log"
    cat /tmp/openvpn_script.log 2>/dev/null || echo "No /tmp/openvpn_script.log"
    exit 1 # Exit if VPN didn't come up properly
  fi

  # At this point, update-resolv.sh should have run.
  # We assume the VPN interface will be tun0 for OpenVPN.
  VPN_INTERFACE="tun0"
  echo "[INFO] Assuming OpenVPN interface is $VPN_INTERFACE after UP script completion."

  # Verify the interface exists and has an IP address
  if ! ip addr show "$VPN_INTERFACE" | grep -q "inet "; then
    echo "[ERROR] OpenVPN interface $VPN_INTERFACE does not have an IPv4 address or is not UP."
    ip addr
    exit 1
  fi
  rm -f "$VPN_UP_FLAG_FILE" # Clean up flag file

##################################
### WireGuard Specific Setup
##################################
elif [ "$VPN_CLIENT" = "wireguard" ]; then
  echo "[INFO] Configuring WireGuard..."
  WG_CONFIG_DIR="/config/wireguard"
  SELECTED_WG_CONFIG="$WG_CONFIG_FILE" # From ENV

  if [ -z "$SELECTED_WG_CONFIG" ]; then
      echo "[INFO] WG_CONFIG_FILE is not set. Trying to find a single .conf file in $WG_CONFIG_DIR"
      SELECTED_WG_CONFIG=$(find_single_config "$WG_CONFIG_DIR" "conf" "") # Only .conf for wireguard
      if [ -z "$SELECTED_WG_CONFIG" ]; then
          echo "[ERROR] No WireGuard config file found in $WG_CONFIG_DIR, and WG_CONFIG_FILE is not set. Cannot start WireGuard."
          exit 1
      else
          echo "[INFO] Automatically selected WireGuard config: $SELECTED_WG_CONFIG"
      fi
  elif [[ ! -f "$SELECTED_WG_CONFIG" ]]; then
      # If WG_CONFIG_FILE is set but doesn't include path, prepend default dir
      if [[ ! "$SELECTED_WG_CONFIG" == /* ]]; then
          SELECTED_WG_CONFIG="${WG_CONFIG_DIR}/${SELECTED_WG_CONFIG}"
      fi
      if [[ ! -f "$SELECTED_WG_CONFIG" ]]; then
          echo "[ERROR] WireGuard config file '$SELECTED_WG_CONFIG' not found. Cannot start WireGuard."
          exit 1
      fi
  fi

  # Extract interface name from config filename (e.g., /config/wireguard/wg0.conf -> wg0)
  WG_INTERFACE=$(basename "$SELECTED_WG_CONFIG" .conf)
  echo "[INFO] WireGuard interface name: $WG_INTERFACE"

  echo "[INFO] Starting WireGuard client (config $SELECTED_WG_CONFIG)"
  wg-quick up "$SELECTED_WG_CONFIG"
  # No daemon mode for wg-quick, it exits after setting up.
  # We'll rely on the interface staying up.
  # TODO: Add check to see if wg-quick up was successful.
  # For now, assume it worked if the command didn't exit with error.
  # Save interface name for healthcheck
  VPN_INTERFACE="$WG_INTERFACE"
  VPN_LOG_FILE="/tmp/wireguard.log" # wg-quick logs to journal/dmesg by default
                                    # For basic logging, we can touch a file or redirect wg show
  wg show "$WG_INTERFACE" > "$VPN_LOG_FILE" 2>&1

else
  echo "[ERROR] Invalid VPN_CLIENT: $VPN_CLIENT. Supported: openvpn, wireguard."
  exit 1
fi

# --- Common VPN Post-Connection Steps ---
echo "[INFO] VPN Interface name is: $VPN_INTERFACE"
echo "$VPN_INTERFACE" > /tmp/vpn_interface_name # For healthcheck script
echo "[INFO] Waiting 5s for $VPN_INTERFACE to settle..."
sleep 5

echo "[INFO] Adding CONNMARK policy routing for NZBGet UI access (mark 0x1, table 100)"
ETH0_IP=$(ip -4 addr show dev eth0 | awk '/inet/ {print $2}' | cut -d/ -f1)

if [ -z "$ETH0_IP" ]; then
    echo "[WARN] Could not determine IP address of eth0. CONNMARK Policy routing for NZBGet UI might not work."
    # As a fallback, if ETH0_IP isn't found, the original PREROUTING -i eth0 -j MARK rule might be tried
    # but CONNMARK on OUTPUT without a reliable PREROUTING CONNMARK set won't work well.
    # For now, we'll proceed, and if ETH0_IP is empty, the -d "" will fail gracefully or match nothing.
fi

iptables -t mangle -F PREROUTING # Flush existing rules
iptables -t mangle -F OUTPUT     # Flush existing rules

# 1. On incoming packets to NZBGet on eth0, set the connection mark based on the destination IP and port.
#    This mark will be associated with the entire connection.
if [ -n "$ETH0_IP" ]; then
    echo "[INFO] eth0 IP address is $ETH0_IP. Applying CONNMARK rules."
    iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 6789 -j CONNMARK --set-mark 0x1
else
    echo "[INFO] ETH0_IP not found. Attempting PREROUTING rule with -i eth0 for CONNMARK."
    iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 6789 -j CONNMARK --set-mark 0x1
fi

# 2. For locally generated reply packets from NZBGet (source port 6789),
#    restore the connection mark to the packet mark. This packet mark (fwmark)
#    will then be used by the ip rule.
#    No need to filter by destination IP here, as OUTPUT chain is for locally generated packets.
#    The sport filter should be specific enough.
iptables -t mangle -A OUTPUT -p tcp --sport 6789 -j CONNMARK --restore-mark

# IP rule: acts on the packet mark (fwmark) restored by CONNMARK on OUTPUT
ip rule flush pref 100
ip rule add fwmark 0x1 lookup 100 pref 100

ETH0_GATEWAY=$(ip route show dev eth0 | grep '^default via' | awk '{print $3}')
if [ -n "$ETH0_GATEWAY" ]; then
    echo "[INFO] Using eth0 gateway $ETH0_GATEWAY for policy routing table 100"
    ip route flush table 100
    ip route add default via "$ETH0_GATEWAY" dev eth0 table 100
else
    echo "[WARN] Could not determine eth0 gateway. Policy routing for NZBGet UI might not work."
fi

# Allow LAN access by routing specified LAN_NETWORK via eth0 (pre-VPN default route)
if [ -n "$LAN_NETWORK" ]; then
  echo "[INFO] Adding route to LAN_NETWORK: $LAN_NETWORK"
  ip route add "$LAN_NETWORK" dev eth0
fi

echo "[INFO] VPN setup script finished. Container should now be routing traffic through VPN (if connection was successful)."

# Turn off debug mode if it was enabled by the script
if [ "$DEBUG" = "true" ] || [ "$DEBUG" = "yes" ]; then
  set +x
fi

# End of script. s6 will continue with other init scripts and then start services.
exit 0
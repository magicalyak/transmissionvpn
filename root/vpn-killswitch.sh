#!/command/with-contenv bash
# Enhanced VPN Kill Switch Script
# Implements strict iptables rules to prevent any IP leaks
# Called by vpn-setup.sh and vpn-monitor service

set -e

# Configuration
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
KILLSWITCH_STATUS="/tmp/killswitch_status"

log() {
    echo "[KILLSWITCH] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

get_vpn_interface() {
    if [ -f "$VPN_INTERFACE_FILE" ]; then
        cat "$VPN_INTERFACE_FILE"
    else
        # Try to detect
        if ip link show tun0 >/dev/null 2>&1; then
            echo "tun0"
        elif ip link show wg0 >/dev/null 2>&1; then
            echo "wg0"
        else
            echo ""
        fi
    fi
}

apply_strict_killswitch() {
    local vpn_if="$1"
    local vpn_server="$2"
    local vpn_port="$3"
    local vpn_proto="${4:-udp}"

    log "Applying strict kill switch rules"

    # Set default policies to DROP - nothing gets through by default
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    log "Default policies set to DROP"

    # Clear all existing rules
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X 2>/dev/null || true

    log "Cleared existing firewall rules"

    # === INPUT CHAIN ===
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT

    # Allow established and related connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow Transmission WebUI access (port 9091)
    iptables -A INPUT -i eth0 -p tcp --dport 9091 -j ACCEPT

    # Allow metrics if enabled
    if [ "${METRICS_ENABLED,,}" = "true" ]; then
        iptables -A INPUT -i eth0 -p tcp --dport "${METRICS_PORT:-9099}" -j ACCEPT
    fi

    # Allow Privoxy if enabled
    if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
        iptables -A INPUT -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j ACCEPT
    fi

    # Allow from LAN if configured
    if [ -n "$LAN_NETWORK" ]; then
        iptables -A INPUT -i eth0 -s "$LAN_NETWORK" -j ACCEPT
        log "Allowed input from LAN: $LAN_NETWORK"
    fi

    # === OUTPUT CHAIN ===
    # Allow loopback
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established and related connections
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # CRITICAL: Block ALL DNS queries on non-VPN interfaces to prevent DNS leaks
    iptables -A OUTPUT -p udp --dport 53 ! -o "$vpn_if" -j DROP
    iptables -A OUTPUT -p tcp --dport 53 ! -o "$vpn_if" -j DROP
    log "DNS leak prevention: Blocked port 53 on all non-VPN interfaces"

    # Allow VPN server connection (for establishing/maintaining VPN)
    if [ -n "$vpn_server" ] && [ -n "$vpn_port" ]; then
        iptables -A OUTPUT -o eth0 -d "$vpn_server" -p "$vpn_proto" --dport "$vpn_port" -j ACCEPT
        log "Allowed VPN server connection: $vpn_server:$vpn_port/$vpn_proto"

        # Temporary DNS for VPN hostname resolution (will be removed after connection)
        iptables -I OUTPUT 1 -o eth0 -p udp --dport 53 -m comment --comment "temp-vpn-dns" -j ACCEPT
        iptables -I OUTPUT 1 -o eth0 -p tcp --dport 53 -m comment --comment "temp-vpn-dns" -j ACCEPT
    fi

    # Allow all traffic through VPN interface
    if [ -n "$vpn_if" ] && ip link show "$vpn_if" >/dev/null 2>&1; then
        iptables -A OUTPUT -o "$vpn_if" -j ACCEPT
        log "Allowed all traffic through VPN interface: $vpn_if"
    fi

    # Allow Transmission UI responses
    iptables -A OUTPUT -o eth0 -p tcp --sport 9091 -j ACCEPT

    # Allow metrics responses if enabled
    if [ "${METRICS_ENABLED,,}" = "true" ]; then
        iptables -A OUTPUT -o eth0 -p tcp --sport "${METRICS_PORT:-9099}" -j ACCEPT
    fi

    # Allow Privoxy responses if enabled
    if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
        iptables -A OUTPUT -o eth0 -p tcp --sport "${PRIVOXY_PORT:-8118}" -j ACCEPT
    fi

    # Allow to LAN if configured
    if [ -n "$LAN_NETWORK" ]; then
        iptables -A OUTPUT -o eth0 -d "$LAN_NETWORK" -j ACCEPT
        log "Allowed output to LAN: $LAN_NETWORK"
    fi

    # === POLICY-BASED ROUTING FOR LAN-ACCESSIBLE SERVICES ===
    # Get eth0 gateway and IP for policy routing
    local eth0_gateway=$(ip route | grep default | grep eth0 | awk '{print $3}')
    if [ -z "$eth0_gateway" ]; then
        eth0_gateway=$(ip route show dev eth0 | awk '/default via/ {print $3}')
    fi
    local eth0_ip=$(ip -4 addr show dev eth0 | awk '/inet/ {print $2}' | cut -d/ -f1)

    if [ -n "$eth0_gateway" ]; then
        log "Setting up policy-based routing for LAN services via gateway: $eth0_gateway"

        # Ensure routing table 100 exists with route to eth0 gateway
        if ! ip route show table 100 | grep -q "default via $eth0_gateway"; then
            ip route add default via "$eth0_gateway" dev eth0 table 100 2>/dev/null || \
                ip route replace default via "$eth0_gateway" dev eth0 table 100
            log "Added/updated route in table 100: default via $eth0_gateway dev eth0"
        fi

        # Ensure fwmark rule exists for table 100
        if ! ip rule list | grep -q "fwmark 0x1 lookup 100"; then
            ip rule add fwmark 0x1 lookup 100 priority 1000
            log "Added ip rule for fwmark 0x1 -> table 100"
        fi

        # CONNMARK rules for Transmission UI (port 9091)
        if [ -n "$eth0_ip" ]; then
            iptables -t mangle -A PREROUTING -d "$eth0_ip" -p tcp --dport 9091 -j CONNMARK --set-mark 0x1
        else
            iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 9091 -j CONNMARK --set-mark 0x1
        fi
        iptables -t mangle -A OUTPUT -p tcp --sport 9091 -j CONNMARK --restore-mark
        log "Applied CONNMARK rules for Transmission UI (port 9091)"

        # CONNMARK rules for metrics if enabled
        if [ "${METRICS_ENABLED,,}" = "true" ]; then
            if [ -n "$eth0_ip" ]; then
                iptables -t mangle -A PREROUTING -d "$eth0_ip" -p tcp --dport "${METRICS_PORT:-9099}" -j CONNMARK --set-mark 0x1
            else
                iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport "${METRICS_PORT:-9099}" -j CONNMARK --set-mark 0x1
            fi
            iptables -t mangle -A OUTPUT -p tcp --sport "${METRICS_PORT:-9099}" -j CONNMARK --restore-mark
            log "Applied CONNMARK rules for metrics (port ${METRICS_PORT:-9099})"
        fi

        # CONNMARK rules for Privoxy if enabled
        if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
            if [ -n "$eth0_ip" ]; then
                iptables -t mangle -A PREROUTING -d "$eth0_ip" -p tcp --dport "${PRIVOXY_PORT:-8118}" -j CONNMARK --set-mark 0x1
            else
                iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j CONNMARK --set-mark 0x1
            fi
            iptables -t mangle -A OUTPUT -p tcp --sport "${PRIVOXY_PORT:-8118}" -j CONNMARK --restore-mark
            log "Applied CONNMARK rules for Privoxy (port ${PRIVOXY_PORT:-8118})"
        fi
    else
        log "WARNING: Could not determine eth0 gateway, skipping policy-based routing setup"
    fi

    # === FORWARD CHAIN ===
    # Allow established connections
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # If container acts as router (unusual for this use case)
    if [ -n "$vpn_if" ] && ip link show "$vpn_if" >/dev/null 2>&1; then
        iptables -A FORWARD -i "$vpn_if" -j ACCEPT
        iptables -A FORWARD -o "$vpn_if" -j ACCEPT
    fi

    # === BitTorrent Port Handling ===
    # If peer port is configured, ensure it only works through VPN
    if [ -n "$TRANSMISSION_PEER_PORT" ]; then
        # Block peer port on eth0 completely
        iptables -I INPUT 1 -i eth0 -p tcp --dport "$TRANSMISSION_PEER_PORT" -j DROP
        iptables -I INPUT 1 -i eth0 -p udp --dport "$TRANSMISSION_PEER_PORT" -j DROP

        # Only allow through VPN
        if [ -n "$vpn_if" ]; then
            iptables -A INPUT -i "$vpn_if" -p tcp --dport "$TRANSMISSION_PEER_PORT" -j ACCEPT
            iptables -A INPUT -i "$vpn_if" -p udp --dport "$TRANSMISSION_PEER_PORT" -j ACCEPT
        fi
        log "BitTorrent port $TRANSMISSION_PEER_PORT restricted to VPN only"
    fi

    # Log the final rules count
    local input_rules=$(iptables -L INPUT -n | wc -l)
    local output_rules=$(iptables -L OUTPUT -n | wc -l)
    local forward_rules=$(iptables -L FORWARD -n | wc -l)

    log "Kill switch applied - Rules: INPUT=$input_rules OUTPUT=$output_rules FORWARD=$forward_rules"
    echo "active" > "$KILLSWITCH_STATUS"

    # Remove temporary DNS rules after a delay (for VPN connection)
    (
        sleep 10
        iptables -D OUTPUT -o eth0 -p udp --dport 53 -m comment --comment "temp-vpn-dns" -j ACCEPT 2>/dev/null || true
        iptables -D OUTPUT -o eth0 -p tcp --dport 53 -m comment --comment "temp-vpn-dns" -j ACCEPT 2>/dev/null || true
        log "Removed temporary DNS rules for VPN connection"
    ) &
}

emergency_killswitch() {
    log "EMERGENCY: Applying emergency kill switch - blocking ALL traffic"

    # Clear everything and block all
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X 2>/dev/null || true

    # Set policies to DROP
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # Only allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow Transmission UI for management
    iptables -A INPUT -i eth0 -p tcp --dport 9091 -j ACCEPT
    iptables -A OUTPUT -o eth0 -p tcp --sport 9091 -j ACCEPT

    echo "emergency" > "$KILLSWITCH_STATUS"
    log "Emergency kill switch active - only loopback and UI access allowed"
}

verify_killswitch() {
    log "Verifying kill switch configuration"

    # Check default policies
    local input_policy=$(iptables -S | grep "^-P INPUT" | awk '{print $3}')
    local output_policy=$(iptables -S | grep "^-P OUTPUT" | awk '{print $3}')
    local forward_policy=$(iptables -S | grep "^-P FORWARD" | awk '{print $3}')

    if [ "$input_policy" != "DROP" ] || [ "$output_policy" != "DROP" ] || [ "$forward_policy" != "DROP" ]; then
        log "WARNING: Default policies not set to DROP!"
        log "  INPUT: $input_policy, OUTPUT: $output_policy, FORWARD: $forward_policy"
        return 1
    fi

    # Check for DNS leak prevention
    if ! iptables -L OUTPUT -n | grep -q "dpt:53.*DROP"; then
        log "WARNING: DNS leak prevention rules not found!"
        return 1
    fi

    # Check VPN interface rules
    local vpn_if=$(get_vpn_interface)
    if [ -n "$vpn_if" ]; then
        if ! iptables -L OUTPUT -n | grep -q "$vpn_if.*ACCEPT"; then
            log "WARNING: VPN interface $vpn_if not properly configured!"
            return 1
        fi
    fi

    log "Kill switch verification: PASSED"
    return 0
}

# Main execution
case "${1:-apply}" in
    apply)
        VPN_INTERFACE=$(get_vpn_interface)
        VPN_SERVER="${2:-}"
        VPN_PORT="${3:-}"
        VPN_PROTO="${4:-udp}"
        apply_strict_killswitch "$VPN_INTERFACE" "$VPN_SERVER" "$VPN_PORT" "$VPN_PROTO"
        ;;

    emergency)
        emergency_killswitch
        ;;

    verify)
        verify_killswitch
        exit $?
        ;;

    status)
        if [ -f "$KILLSWITCH_STATUS" ]; then
            echo "Kill switch status: $(cat $KILLSWITCH_STATUS)"
        else
            echo "Kill switch status: unknown"
        fi

        echo "Current firewall policies:"
        iptables -S | grep "^-P"

        echo "DNS leak prevention:"
        iptables -L OUTPUT -n | grep "dpt:53" || echo "  No DNS rules found"

        echo "VPN interface: $(get_vpn_interface)"
        ;;

    *)
        echo "Usage: $0 [apply|emergency|verify|status]"
        echo "  apply    - Apply kill switch with VPN configuration"
        echo "  emergency - Apply emergency kill switch (block all)"
        echo "  verify   - Verify kill switch is properly configured"
        echo "  status   - Show current kill switch status"
        exit 1
        ;;
esac
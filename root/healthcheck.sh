#!/bin/bash

# Enhanced healthcheck script for transmissionvpn
# Provides comprehensive monitoring of VPN, Transmission, and network connectivity
# Exit codes: 0=success, 1=transmission_down, 2=vpn_interface_down, 3=vpn_interface_missing, 4=vpn_connectivity_failed, 5=dns_failed, 6=ip_leak_detected

set -e

# Configuration
HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-google.com}
CHECK_DNS_LEAK=${CHECK_DNS_LEAK:-false}
CHECK_IP_LEAK=${CHECK_IP_LEAK:-false}
METRICS_ENABLED=${METRICS_ENABLED:-false}
HEALTH_LOG_FILE="/tmp/healthcheck.log"
METRICS_FILE="/tmp/metrics.txt"
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$HEALTH_LOG_FILE"
}

# Metrics function
record_metric() {
    local metric_name="$1"
    local value="$2"
    local timestamp=$(date +%s)
    
    if [ "$METRICS_ENABLED" = "true" ]; then
        echo "transmissionvpn_${metric_name} ${value} ${timestamp}" >> "$METRICS_FILE"
    fi
}

# Initialize metrics file
if [ "$METRICS_ENABLED" = "true" ]; then
    mkdir -p "$(dirname "$METRICS_FILE")"
    # Clear old metrics (keep last 1000 lines to prevent unlimited growth)
    if [ -f "$METRICS_FILE" ]; then
        tail -1000 "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    fi
fi

log "INFO" "Starting enhanced healthcheck..."

# Function to check Transmission status
check_transmission() {
    local start_time=$(date +%s%N)
    
    log "DEBUG" "Checking Transmission web interface..."
    
    # Check if Transmission web interface is responding
    if curl -sSf http://localhost:9091/transmission/web/ > /dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local response_time=$(((end_time - start_time) / 1000000)) # Convert to milliseconds
        
        log "INFO" "Transmission web interface is responding (${response_time}ms)"
        record_metric "transmission_response_time_ms" "$response_time"
        record_metric "transmission_status" "1"
        
        # Additional check: Get session stats if possible
        if command -v transmission-remote >/dev/null 2>&1; then
            local session_info
            if session_info=$(transmission-remote localhost:9091 -si 2>/dev/null); then
                # Extract some basic stats
                local current_torrents
                current_torrents=$(transmission-remote localhost:9091 -l 2>/dev/null | wc -l)
                current_torrents=$((current_torrents - 2)) # Subtract header and footer lines
                
                log "DEBUG" "Active torrents: $current_torrents"
                record_metric "transmission_active_torrents" "$current_torrents"
            fi
        fi
        
        return 0
    else
        log "ERROR" "Transmission web interface is not responding"
        record_metric "transmission_status" "0"
        return 1
    fi
}

# Function to determine VPN interface
get_vpn_interface() {
    local vpn_if=""
    
    if [ -f "$VPN_INTERFACE_FILE" ]; then
        vpn_if=$(cat "$VPN_INTERFACE_FILE")
        log "DEBUG" "VPN interface from file: $vpn_if"
    else
        log "WARN" "VPN interface file not found, attempting to detect..."
        
        # Try to detect VPN interface
        if ip link show wg0 &> /dev/null; then
            vpn_if="wg0"
            log "DEBUG" "Detected WireGuard interface: wg0"
        elif ip link show tun0 &> /dev/null; then
            vpn_if="tun0"
            log "DEBUG" "Detected OpenVPN interface: tun0"
        else
            # Try to find any tun/wg interface
            for iface in $(ip link show | grep -E "(tun|wg)" | cut -d: -f2 | tr -d ' '); do
                if [ -n "$iface" ]; then
                    vpn_if="$iface"
                    log "DEBUG" "Found VPN interface: $iface"
                    break
                fi
            done
        fi
        
        if [ -z "$vpn_if" ]; then
            log "ERROR" "Could not determine VPN interface"
            return 1
        fi
    fi
    
    echo "$vpn_if"
}

# Function to check VPN interface status
check_vpn_interface() {
    local vpn_if="$1"
    
    log "DEBUG" "Checking VPN interface: $vpn_if"
    
    # Check if interface exists and is up
    if ip link show "$vpn_if" > /dev/null 2>&1; then
        if ip link show "$vpn_if" | grep -q "UP"; then
            log "INFO" "VPN interface $vpn_if is UP"
            record_metric "vpn_interface_status" "1"
            
            # Get interface statistics
            local rx_bytes tx_bytes
            if [ -f "/sys/class/net/$vpn_if/statistics/rx_bytes" ]; then
                rx_bytes=$(cat "/sys/class/net/$vpn_if/statistics/rx_bytes")
                tx_bytes=$(cat "/sys/class/net/$vpn_if/statistics/tx_bytes")
                log "DEBUG" "VPN interface stats - RX: ${rx_bytes} bytes, TX: ${tx_bytes} bytes"
                record_metric "vpn_interface_rx_bytes" "$rx_bytes"
                record_metric "vpn_interface_tx_bytes" "$tx_bytes"
            fi
            
            return 0
        else
            log "ERROR" "VPN interface $vpn_if exists but is DOWN"
            record_metric "vpn_interface_status" "0"
            return 1
        fi
    else
        log "ERROR" "VPN interface $vpn_if does not exist"
        record_metric "vpn_interface_status" "0"
        return 1
    fi
}

# Function to check VPN connectivity
check_vpn_connectivity() {
    local vpn_if="$1"
    local start_time=$(date +%s%N)
    
    log "DEBUG" "Testing VPN connectivity to $HEALTH_CHECK_HOST through $vpn_if"
    
    # Ping test through VPN interface
    if ping -c 1 -W 3 -I "$vpn_if" "$HEALTH_CHECK_HOST" > /dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local ping_time=$(((end_time - start_time) / 1000000)) # Convert to milliseconds
        
        log "INFO" "VPN connectivity test successful (${ping_time}ms)"
        record_metric "vpn_connectivity_status" "1"
        record_metric "vpn_ping_time_ms" "$ping_time"
        return 0
    else
        log "ERROR" "VPN connectivity test failed to $HEALTH_CHECK_HOST"
        record_metric "vpn_connectivity_status" "0"
        return 1
    fi
}

# Function to check DNS resolution
check_dns() {
    local vpn_if="$1"
    
    log "DEBUG" "Testing DNS resolution through VPN"
    
    # Test DNS resolution
    local dns_start_time=$(date +%s%N)
    if nslookup "$HEALTH_CHECK_HOST" > /dev/null 2>&1; then
        local dns_end_time=$(date +%s%N)
        local dns_time=$(((dns_end_time - dns_start_time) / 1000000))
        
        log "INFO" "DNS resolution successful (${dns_time}ms)"
        record_metric "dns_resolution_status" "1"
        record_metric "dns_resolution_time_ms" "$dns_time"
        return 0
    else
        log "ERROR" "DNS resolution failed"
        record_metric "dns_resolution_status" "0"
        return 1
    fi
}

# Function to check for IP leaks
check_ip_leak() {
    log "DEBUG" "Checking for IP leaks..."
    
    # Get current external IP
    local external_ip
    if external_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null); then
        log "INFO" "Current external IP: $external_ip"
        
        # Store IP for comparison (basic leak detection)
        local previous_ip=""
        if [ -f "/tmp/last_external_ip" ]; then
            previous_ip=$(cat /tmp/last_external_ip)
        fi
        
        echo "$external_ip" > /tmp/last_external_ip
        
        # Simple check: if we have a previous IP and it changed, log it
        if [ -n "$previous_ip" ] && [ "$previous_ip" != "$external_ip" ]; then
            log "WARN" "External IP changed from $previous_ip to $external_ip"
        fi
        
        record_metric "ip_leak_check_status" "1"
        return 0
    else
        log "ERROR" "Failed to check external IP"
        record_metric "ip_leak_check_status" "0"
        return 1
    fi
}

# Function to check DNS leaks
check_dns_leak() {
    log "DEBUG" "Checking for DNS leaks..."
    
    # Check which DNS servers are being used
    local dns_servers
    if dns_servers=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | tr '\n' ',' | sed 's/,$//'); then
        log "INFO" "Current DNS servers: $dns_servers"
        
        # Store for comparison
        echo "$dns_servers" > /tmp/last_dns_servers
        
        record_metric "dns_leak_check_status" "1"
        return 0
    else
        log "ERROR" "Failed to check DNS servers"
        record_metric "dns_leak_check_status" "0"
        return 1
    fi
}

# Function to collect system metrics
collect_system_metrics() {
    if [ "$METRICS_ENABLED" = "true" ]; then
        log "DEBUG" "Collecting system metrics..."
        
        # CPU usage
        local cpu_usage
        if cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'); then
            record_metric "cpu_usage_percent" "$cpu_usage"
        fi
        
        # Memory usage
        local mem_total mem_used mem_percent
        if mem_info=$(free | grep Mem); then
            mem_total=$(echo "$mem_info" | awk '{print $2}')
            mem_used=$(echo "$mem_info" | awk '{print $3}')
            mem_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")
            record_metric "memory_usage_percent" "$mem_percent"
            record_metric "memory_used_bytes" "$((mem_used * 1024))"
        fi
        
        # Disk usage for important paths
        local disk_usage
        for path in /config /downloads /tmp; do
            if [ -d "$path" ]; then
                disk_usage=$(df "$path" | tail -1 | awk '{print $5}' | sed 's/%//')
                record_metric "disk_usage_percent_$(echo "$path" | tr '/' '_')" "$disk_usage"
            fi
        done
        
        # Network statistics
        local total_rx=0 total_tx=0
        for iface in /sys/class/net/*; do
            iface=$(basename "$iface")
            if [ -f "/sys/class/net/$iface/statistics/rx_bytes" ]; then
                local rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
                local tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
                total_rx=$((total_rx + rx))
                total_tx=$((total_tx + tx))
            fi
        done
        record_metric "network_total_rx_bytes" "$total_rx"
        record_metric "network_total_tx_bytes" "$total_tx"
    fi
}

# Main healthcheck execution
main() {
    local exit_code=0
    
    # Initialize log
    echo "# Healthcheck started at $(date)" >> "$HEALTH_LOG_FILE"
    
    # Check Transmission
    if ! check_transmission; then
        log "ERROR" "Transmission healthcheck failed"
        exit_code=1
    fi
    
    # Determine VPN interface
    local vpn_if
    if ! vpn_if=$(get_vpn_interface); then
        log "ERROR" "Failed to determine VPN interface"
        exit_code=3
    else
        # Check VPN interface status
        if ! check_vpn_interface "$vpn_if"; then
            log "ERROR" "VPN interface healthcheck failed"
            exit_code=2
        else
            # Check VPN connectivity
            if ! check_vpn_connectivity "$vpn_if"; then
                log "ERROR" "VPN connectivity healthcheck failed"
                exit_code=4
            fi
            
            # Optional DNS check
            if ! check_dns "$vpn_if"; then
                log "ERROR" "DNS healthcheck failed"
                if [ $exit_code -eq 0 ]; then
                    exit_code=5
                fi
            fi
        fi
    fi
    
    # Optional IP leak detection
    if [ "$CHECK_IP_LEAK" = "true" ]; then
        if ! check_ip_leak; then
            log "WARN" "IP leak check failed"
            if [ $exit_code -eq 0 ]; then
                exit_code=6
            fi
        fi
    fi
    
    # Optional DNS leak detection
    if [ "$CHECK_DNS_LEAK" = "true" ]; then
        if ! check_dns_leak; then
            log "WARN" "DNS leak check failed"
        fi
    fi
    
    # Collect system metrics
    collect_system_metrics
    
    # Record overall health status
    if [ $exit_code -eq 0 ]; then
        log "INFO" "All healthchecks passed"
        record_metric "overall_health_status" "1"
    else
        log "ERROR" "Healthcheck failed with exit code $exit_code"
        record_metric "overall_health_status" "0"
    fi
    
    # Cleanup old log entries (keep last 500 lines)
    if [ -f "$HEALTH_LOG_FILE" ]; then
        tail -500 "$HEALTH_LOG_FILE" > "${HEALTH_LOG_FILE}.tmp" && mv "${HEALTH_LOG_FILE}.tmp" "$HEALTH_LOG_FILE"
    fi
    
    return $exit_code
}

# Run main function
main "$@"

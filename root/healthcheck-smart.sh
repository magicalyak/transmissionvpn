#!/bin/bash

# Smart healthcheck script for transmissionvpn
# Provides monitoring of both Transmission AND VPN with configurable behavior
# Exit codes: 0=success, 1=transmission_down, 2=vpn_down, 3=both_down
#
# Environment variables to control behavior:
# - VPN_HEALTH_REQUIRED=true/false (default: true) - Whether VPN failure should fail health
# - VPN_GRACE_PERIOD=300 (default: 300 seconds) - Grace period for VPN reconnection
# - HEALTH_CHECK_HOST=google.com (default) - Host to test VPN connectivity

set -e

# Configuration
HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-google.com}
VPN_HEALTH_REQUIRED=${VPN_HEALTH_REQUIRED:-true}
VPN_GRACE_PERIOD=${VPN_GRACE_PERIOD:-300}  # 5 minutes grace period
CHECK_DNS_LEAK=${CHECK_DNS_LEAK:-false}
CHECK_IP_LEAK=${CHECK_IP_LEAK:-false}
METRICS_ENABLED=${METRICS_ENABLED:-false}
HEALTH_LOG_FILE="/tmp/healthcheck.log"
METRICS_FILE="/tmp/metrics.txt"
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
VPN_DOWN_TIMESTAMP_FILE="/tmp/vpn_down_timestamp"

# Logging function that only outputs to stderr and log file, not stdout
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$HEALTH_LOG_FILE" >&2
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
    if [ -f "$METRICS_FILE" ]; then
        tail -1000 "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    fi
fi

log "INFO" "Starting smart healthcheck (VPN_HEALTH_REQUIRED=$VPN_HEALTH_REQUIRED, GRACE_PERIOD=${VPN_GRACE_PERIOD}s)..."

# Function to check Transmission status (CRITICAL - must pass)
check_transmission() {
    log "DEBUG" "Checking Transmission daemon status..."
    
    # Check if transmission-daemon process is running
    if ! pgrep -f "transmission-daemon" > /dev/null; then
        log "ERROR" "Transmission daemon process not found"
        record_metric "transmission_daemon_status" "0"
        return 1
    fi
    
    log "DEBUG" "Transmission daemon process is running"
    record_metric "transmission_daemon_status" "1"
    
    # Check if web interface is responding
    local web_start_time=$(date +%s%N)
    if curl -sf --max-time 5 http://127.0.0.1:9091/transmission/web/ > /dev/null 2>&1; then
        local web_end_time=$(date +%s%N)
        local web_response_time=$(((web_end_time - web_start_time) / 1000000))
        
        log "INFO" "Transmission web interface is responding (${web_response_time}ms)"
        record_metric "transmission_web_status" "1"
        record_metric "transmission_web_response_time_ms" "$web_response_time"
        return 0
    else
        log "ERROR" "Transmission web interface is not responding"
        record_metric "transmission_web_status" "0"
        return 1
    fi
}

# Function to get VPN interface
get_vpn_interface() {
    local vpn_if=""
    
    if [ -f "$VPN_INTERFACE_FILE" ]; then
        vpn_if=$(cat "$VPN_INTERFACE_FILE")
        log "DEBUG" "VPN interface from file: $vpn_if"
    else
        log "DEBUG" "VPN interface file not found, attempting to detect..."
        
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
            log "WARN" "Could not determine VPN interface"
            return 1
        fi
    fi
    
    echo "$vpn_if"
}

# Function to check VPN interface status
check_vpn_interface() {
    local vpn_if="$1"
    
    log "DEBUG" "Checking VPN interface: $vpn_if"
    
    if ip link show "$vpn_if" > /dev/null 2>&1; then
        if ip link show "$vpn_if" | grep -q "UP"; then
            # Check if interface has an IP address
            if ip addr show "$vpn_if" | grep -q "inet "; then
                log "INFO" "VPN interface $vpn_if is UP and has IP address"
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
                log "WARN" "VPN interface $vpn_if is UP but has no IP address"
                record_metric "vpn_interface_status" "0"
                return 1
            fi
        else
            log "WARN" "VPN interface $vpn_if exists but is DOWN"
            record_metric "vpn_interface_status" "0"
            return 1
        fi
    else
        log "WARN" "VPN interface $vpn_if does not exist"
        record_metric "vpn_interface_status" "0"
        return 1
    fi
}

# Function to check VPN connectivity
check_vpn_connectivity() {
    local vpn_if="$1"
    local start_time=$(date +%s%N)
    
    log "DEBUG" "Testing VPN connectivity to $HEALTH_CHECK_HOST through $vpn_if"
    
    if ping -c 1 -W 3 -I "$vpn_if" "$HEALTH_CHECK_HOST" > /dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local ping_time=$(((end_time - start_time) / 1000000))
        
        log "INFO" "VPN connectivity test successful (${ping_time}ms)"
        record_metric "vpn_connectivity_status" "1"
        record_metric "vpn_ping_time_ms" "$ping_time"
        return 0
    else
        log "WARN" "VPN connectivity test failed to $HEALTH_CHECK_HOST"
        record_metric "vpn_connectivity_status" "0"
        return 1
    fi
}

# Function to handle VPN grace period
check_vpn_grace_period() {
    local current_time=$(date +%s)
    
    if [ -f "$VPN_DOWN_TIMESTAMP_FILE" ]; then
        local vpn_down_time=$(cat "$VPN_DOWN_TIMESTAMP_FILE")
        local down_duration=$((current_time - vpn_down_time))
        
        if [ $down_duration -lt $VPN_GRACE_PERIOD ]; then
            log "INFO" "VPN is down but within grace period (${down_duration}s/${VPN_GRACE_PERIOD}s)"
            record_metric "vpn_grace_period_remaining" "$((VPN_GRACE_PERIOD - down_duration))"
            return 0  # Still in grace period
        else
            log "WARN" "VPN has been down for ${down_duration}s, exceeding grace period of ${VPN_GRACE_PERIOD}s"
            record_metric "vpn_grace_period_remaining" "0"
            return 1  # Grace period exceeded
        fi
    else
        # First time VPN is detected as down, record timestamp
        echo "$current_time" > "$VPN_DOWN_TIMESTAMP_FILE"
        log "INFO" "VPN down detected, starting grace period of ${VPN_GRACE_PERIOD}s"
        record_metric "vpn_grace_period_remaining" "$VPN_GRACE_PERIOD"
        return 0  # Just started grace period
    fi
}

# Function to clear VPN down timestamp when VPN is back up
clear_vpn_down_timestamp() {
    if [ -f "$VPN_DOWN_TIMESTAMP_FILE" ]; then
        rm -f "$VPN_DOWN_TIMESTAMP_FILE"
        log "INFO" "VPN is back up, cleared grace period timer"
    fi
    record_metric "vpn_grace_period_remaining" "0"
}

# Function to collect system metrics
collect_system_metrics() {
    if [ "$METRICS_ENABLED" = "true" ]; then
        # CPU usage
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr -d ' ')
        if [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            record_metric "system_cpu_usage_percent" "$cpu_usage"
        fi
        
        # Memory usage
        local mem_info=$(free | grep Mem)
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        local mem_used=$(echo "$mem_info" | awk '{print $3}')
        if [ -n "$mem_total" ] && [ -n "$mem_used" ] && [ "$mem_total" -gt 0 ]; then
            local mem_usage_percent=$((mem_used * 100 / mem_total))
            record_metric "system_memory_usage_percent" "$mem_usage_percent"
            record_metric "system_memory_total_bytes" "$((mem_total * 1024))"
            record_metric "system_memory_used_bytes" "$((mem_used * 1024))"
        fi
        
        # Disk usage for key directories
        for dir in "/config" "/downloads" "/watch"; do
            if [ -d "$dir" ]; then
                local disk_usage=$(df "$dir" | tail -1 | awk '{print $5}' | tr -d '%')
                if [[ "$disk_usage" =~ ^[0-9]+$ ]]; then
                    local dir_name=$(basename "$dir")
                    record_metric "disk_usage_${dir_name}_percent" "$disk_usage"
                fi
            fi
        done
    fi
}

# Main function
main() {
    local exit_code=0
    local transmission_ok=false
    local vpn_ok=false
    
    # Initialize log
    echo "# Smart healthcheck started at $(date)" >> "$HEALTH_LOG_FILE"
    
    # Check Transmission (CRITICAL - always required)
    if check_transmission; then
        log "INFO" "Transmission is healthy"
        transmission_ok=true
        record_metric "transmission_health_status" "1"
    else
        log "ERROR" "Transmission is unhealthy"
        transmission_ok=false
        record_metric "transmission_health_status" "0"
        exit_code=1
    fi
    
    # Check VPN status
    local vpn_if
    if vpn_if=$(get_vpn_interface); then
        log "INFO" "VPN interface detected: $vpn_if"
        
        # Check VPN interface and connectivity
        if check_vpn_interface "$vpn_if" && check_vpn_connectivity "$vpn_if"; then
            log "INFO" "VPN is healthy"
            vpn_ok=true
            record_metric "vpn_health_status" "1"
            clear_vpn_down_timestamp
        else
            log "WARN" "VPN is unhealthy"
            vpn_ok=false
            record_metric "vpn_health_status" "0"
            
            # Handle VPN failure based on configuration
            if [ "$VPN_HEALTH_REQUIRED" = "true" ]; then
                if check_vpn_grace_period; then
                    log "INFO" "VPN unhealthy but within grace period - not failing health check"
                else
                    log "ERROR" "VPN unhealthy and grace period exceeded - failing health check"
                    if [ $exit_code -eq 0 ]; then
                        exit_code=2  # VPN failure
                    else
                        exit_code=3  # Both Transmission and VPN failure
                    fi
                fi
            else
                log "INFO" "VPN unhealthy but VPN_HEALTH_REQUIRED=false - not failing health check"
            fi
        fi
    else
        log "WARN" "No VPN interface detected"
        vpn_ok=false
        record_metric "vpn_health_status" "0"
        
        if [ "$VPN_HEALTH_REQUIRED" = "true" ]; then
            log "ERROR" "No VPN interface found and VPN_HEALTH_REQUIRED=true - failing health check"
            if [ $exit_code -eq 0 ]; then
                exit_code=2  # VPN failure
            else
                exit_code=3  # Both Transmission and VPN failure
            fi
        else
            log "INFO" "No VPN interface found but VPN_HEALTH_REQUIRED=false - not failing health check"
        fi
    fi
    
    # Collect system metrics
    collect_system_metrics
    
    # Record overall health status
    if [ $exit_code -eq 0 ]; then
        log "INFO" "Overall health check PASSED"
        record_metric "overall_health_status" "1"
    else
        case $exit_code in
            1) log "ERROR" "Health check FAILED - Transmission unhealthy" ;;
            2) log "ERROR" "Health check FAILED - VPN unhealthy" ;;
            3) log "ERROR" "Health check FAILED - Both Transmission and VPN unhealthy" ;;
        esac
        record_metric "overall_health_status" "0"
    fi
    
    # Summary log
    log "INFO" "Health Summary: Transmission=$($transmission_ok && echo "OK" || echo "FAIL"), VPN=$($vpn_ok && echo "OK" || echo "FAIL"), Exit Code=$exit_code"
    
    # Cleanup old log entries (keep last 500 lines)
    if [ -f "$HEALTH_LOG_FILE" ]; then
        tail -500 "$HEALTH_LOG_FILE" > "${HEALTH_LOG_FILE}.tmp" && mv "${HEALTH_LOG_FILE}.tmp" "$HEALTH_LOG_FILE"
    fi
    
    exit $exit_code
}

# Run main function
main "$@" 
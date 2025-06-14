#!/bin/bash

# Enhanced healthcheck script for transmissionvpn - TRANSMISSION-FOCUSED VERSION
# Provides monitoring of Transmission with optional VPN status reporting
# Exit codes: 0=success, 1=transmission_down
#
# This version prioritizes Transmission functionality over VPN status
# VPN status is reported but doesn't cause health failure

set -e

# Configuration
HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-google.com}
CHECK_DNS_LEAK=${CHECK_DNS_LEAK:-false}
CHECK_IP_LEAK=${CHECK_IP_LEAK:-false}
METRICS_ENABLED=${METRICS_ENABLED:-false}
HEALTH_LOG_FILE="/tmp/healthcheck.log"
METRICS_FILE="/tmp/metrics.txt"
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"

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

log "INFO" "Starting Transmission-focused healthcheck..."

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

# Main function
main() {
    local exit_code=0
    
    # Initialize log
    echo "# Healthcheck started at $(date)" >> "$HEALTH_LOG_FILE"
    
    # Check Transmission (CRITICAL - determines health status)
    if ! check_transmission; then
        log "ERROR" "Transmission healthcheck failed - container will be marked unhealthy"
        exit_code=1
    else
        log "INFO" "Transmission is healthy"
        record_metric "overall_health_status" "1"
    fi
    
    # Cleanup old log entries (keep last 500 lines)
    if [ -f "$HEALTH_LOG_FILE" ]; then
        tail -500 "$HEALTH_LOG_FILE" > "${HEALTH_LOG_FILE}.tmp" && mv "${HEALTH_LOG_FILE}.tmp" "$HEALTH_LOG_FILE"
    fi
    
    exit $exit_code
}

# Run main function
main "$@" 
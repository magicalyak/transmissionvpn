#!/bin/bash

# transmissionvpn monitoring and notification script
# This script monitors the health of transmissionvpn container and sends notifications

set -e

# Configuration
CONTAINER_NAME="${CONTAINER_NAME:-transmissionvpn}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
NOTIFICATION_LEVEL="${NOTIFICATION_LEVEL:-error}"  # debug, info, warn, error
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
LOG_FILE="${LOG_FILE:-/tmp/transmissionvpn_monitor.log}"

# Notification functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

send_webhook() {
    local title="$1"
    local message="$2"
    local level="$3"
    local color="$4"
    
    if [ -n "$WEBHOOK_URL" ]; then
        local payload=$(cat <<EOF
{
    "title": "$title",
    "message": "$message",
    "level": "$level",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "container": "$CONTAINER_NAME"
}
EOF
)
        
        if curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" >/dev/null; then
            log "DEBUG" "Webhook notification sent successfully"
        else
            log "ERROR" "Failed to send webhook notification"
        fi
    fi
}

send_discord_notification() {
    local title="$1"
    local message="$2"
    local level="$3"
    local color="$4"
    
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        local embed_color
        case "$level" in
            "error") embed_color=15158332 ;;  # Red
            "warn") embed_color=16776960 ;;   # Yellow
            "info") embed_color=3447003 ;;    # Blue
            *) embed_color=9936031 ;;         # Gray
        esac
        
        local payload=$(cat <<EOF
{
    "embeds": [{
        "title": "$title",
        "description": "$message",
        "color": $embed_color,
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "fields": [
            {
                "name": "Container",
                "value": "$CONTAINER_NAME",
                "inline": true
            },
            {
                "name": "Level",
                "value": "$level",
                "inline": true
            }
        ]
    }]
}
EOF
)
        
        if curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null; then
            log "DEBUG" "Discord notification sent successfully"
        else
            log "ERROR" "Failed to send Discord notification"
        fi
    fi
}

send_slack_notification() {
    local title="$1"
    local message="$2"
    local level="$3"
    local color="$4"
    
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local slack_color
        case "$level" in
            "error") slack_color="danger" ;;
            "warn") slack_color="warning" ;;
            "info") slack_color="good" ;;
            *) slack_color="#439FE0" ;;
        esac
        
        local payload=$(cat <<EOF
{
    "attachments": [{
        "color": "$slack_color",
        "title": "$title",
        "text": "$message",
        "ts": $(date +%s),
        "fields": [
            {
                "title": "Container",
                "value": "$CONTAINER_NAME",
                "short": true
            },
            {
                "title": "Level",
                "value": "$level",
                "short": true
            }
        ]
    }]
}
EOF
)
        
        if curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$SLACK_WEBHOOK_URL" >/dev/null; then
            log "DEBUG" "Slack notification sent successfully"
        else
            log "ERROR" "Failed to send Slack notification"
        fi
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    local level="$3"
    
    # Check if we should send notifications for this level
    local send_notification=false
    case "$NOTIFICATION_LEVEL" in
        "debug") send_notification=true ;;
        "info") [[ "$level" =~ ^(info|warn|error)$ ]] && send_notification=true ;;
        "warn") [[ "$level" =~ ^(warn|error)$ ]] && send_notification=true ;;
        "error") [[ "$level" = "error" ]] && send_notification=true ;;
    esac
    
    if [ "$send_notification" = "true" ]; then
        send_webhook "$title" "$message" "$level"
        send_discord_notification "$title" "$message" "$level"
        send_slack_notification "$title" "$message" "$level"
    fi
}

# Health check functions
check_container_status() {
    if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        return 0
    else
        return 1
    fi
}

get_container_health() {
    if docker inspect "$CONTAINER_NAME" --format='{{.State.Health.Status}}' 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_container_health() {
    local health_status
    if health_status=$(get_container_health); then
        case "$health_status" in
            "healthy") return 0 ;;
            "unhealthy") return 1 ;;
            "starting") return 2 ;;
            *) return 3 ;;
        esac
    else
        return 4
    fi
}

get_external_ip() {
    if docker exec "$CONTAINER_NAME" curl -s --max-time 10 ifconfig.me 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_vpn_connection() {
    local external_ip
    if external_ip=$(get_external_ip); then
        echo "$external_ip"
        return 0
    else
        return 1
    fi
}

get_transmission_stats() {
    local stats
    if stats=$(docker exec "$CONTAINER_NAME" transmission-remote localhost:9091 -si 2>/dev/null); then
        echo "$stats"
        return 0
    else
        return 1
    fi
}

# State tracking
STATE_FILE="/tmp/transmissionvpn_monitor_state"

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        # Initialize state
        LAST_CONTAINER_STATUS="unknown"
        LAST_HEALTH_STATUS="unknown"
        LAST_EXTERNAL_IP=""
        LAST_NOTIFICATION_TIME=0
    fi
}

save_state() {
    cat > "$STATE_FILE" <<EOF
LAST_CONTAINER_STATUS="$1"
LAST_HEALTH_STATUS="$2"
LAST_EXTERNAL_IP="$3"
LAST_NOTIFICATION_TIME="$4"
EOF
}

# Monitoring logic
monitor_container() {
    local current_time=$(date +%s)
    local container_status="stopped"
    local health_status="unknown"
    local external_ip=""
    
    log "DEBUG" "Starting monitoring check..."
    
    # Check if container is running
    if check_container_status; then
        container_status="running"
        log "DEBUG" "Container is running"
        
        # Check health status
        local health_exit_code
        check_container_health
        health_exit_code=$?
        
        case $health_exit_code in
            0) health_status="healthy" ;;
            1) health_status="unhealthy" ;;
            2) health_status="starting" ;;
            3) health_status="no_healthcheck" ;;
            4) health_status="unknown" ;;
        esac
        
        log "DEBUG" "Container health status: $health_status"
        
        # Check VPN connection
        if external_ip=$(check_vpn_connection); then
            log "DEBUG" "External IP: $external_ip"
        else
            log "WARN" "Failed to get external IP"
            external_ip="unavailable"
        fi
        
    else
        log "ERROR" "Container is not running"
        container_status="stopped"
    fi
    
    # Load previous state
    load_state
    
    # Check for status changes and send notifications
    local send_notification=false
    local notification_title=""
    local notification_message=""
    local notification_level="info"
    
    # Container status change
    if [ "$container_status" != "$LAST_CONTAINER_STATUS" ]; then
        send_notification=true
        if [ "$container_status" = "running" ]; then
            notification_title="📦 Container Started"
            notification_message="transmissionvpn container is now running"
            notification_level="info"
        else
            notification_title="🚨 Container Stopped"
            notification_message="transmissionvpn container has stopped"
            notification_level="error"
        fi
    fi
    
    # Health status change
    if [ "$health_status" != "$LAST_HEALTH_STATUS" ] && [ "$container_status" = "running" ]; then
        send_notification=true
        case "$health_status" in
            "healthy")
                notification_title="✅ Health Check Passed"
                notification_message="Container health check is now passing"
                notification_level="info"
                ;;
            "unhealthy")
                notification_title="🚨 Health Check Failed"
                notification_message="Container health check is failing"
                notification_level="error"
                ;;
            "starting")
                notification_title="🔄 Container Starting"
                notification_message="Container is starting up"
                notification_level="info"
                ;;
        esac
    fi
    
    # IP address change (potential VPN server change or leak)
    if [ -n "$external_ip" ] && [ "$external_ip" != "unavailable" ] && [ "$external_ip" != "$LAST_EXTERNAL_IP" ] && [ -n "$LAST_EXTERNAL_IP" ]; then
        send_notification=true
        notification_title="🌐 IP Address Changed"
        notification_message="External IP changed from $LAST_EXTERNAL_IP to $external_ip"
        notification_level="warn"
    fi
    
    # Rate limiting: don't send same type of notification too frequently (5 minutes)
    local time_since_last=$((current_time - LAST_NOTIFICATION_TIME))
    if [ $time_since_last -lt 300 ] && [ "$send_notification" = "true" ]; then
        log "DEBUG" "Rate limiting notification (last sent ${time_since_last}s ago)"
        send_notification=false
    fi
    
    # Send notification if needed
    if [ "$send_notification" = "true" ]; then
        log "INFO" "Sending notification: $notification_title"
        send_notification "$notification_title" "$notification_message" "$notification_level"
        current_time=$(date +%s)
    fi
    
    # Save current state
    save_state "$container_status" "$health_status" "$external_ip" "$current_time"
    
    log "DEBUG" "Monitoring check completed"
}

# Metrics collection
collect_metrics() {
    if [ "$METRICS_ENABLED" = "true" ]; then
        log "DEBUG" "Collecting monitoring metrics..."
        
        local metrics_file="/tmp/monitor_metrics.txt"
        local timestamp=$(date +%s)
        
        # Container running status
        if check_container_status; then
            echo "transmissionvpn_monitor_container_running 1 $timestamp" >> "$metrics_file"
        else
            echo "transmissionvpn_monitor_container_running 0 $timestamp" >> "$metrics_file"
        fi
        
        # Health status
        local health_exit_code
        check_container_health
        health_exit_code=$?
        echo "transmissionvpn_monitor_health_status $health_exit_code $timestamp" >> "$metrics_file"
        
        # External IP check
        if get_external_ip >/dev/null 2>&1; then
            echo "transmissionvpn_monitor_external_ip_check 1 $timestamp" >> "$metrics_file"
        else
            echo "transmissionvpn_monitor_external_ip_check 0 $timestamp" >> "$metrics_file"
        fi
        
        # Keep metrics file from growing too large
        if [ -f "$metrics_file" ]; then
            tail -1000 "$metrics_file" > "${metrics_file}.tmp" && mv "${metrics_file}.tmp" "$metrics_file"
        fi
    fi
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Monitor transmissionvpn container health and send notifications.

Options:
    -h, --help                  Show this help message
    -c, --container NAME        Container name (default: transmissionvpn)
    -i, --interval SECONDS      Check interval (default: 60)
    -l, --level LEVEL          Notification level: debug,info,warn,error (default: error)
    -w, --webhook URL          Generic webhook URL for notifications
    -d, --discord URL          Discord webhook URL
    -s, --slack URL            Slack webhook URL
    --once                     Run once and exit (don't loop)
    --test                     Send test notifications

Examples:
    # Monitor with Discord notifications
    $0 --discord https://discord.com/api/webhooks/...

    # Monitor with 30 second interval, warn level
    $0 --interval 30 --level warn

    # Run once to check status
    $0 --once

    # Test notifications
    $0 --test --discord https://discord.com/api/webhooks/...

Environment Variables:
    CONTAINER_NAME             Container name to monitor
    CHECK_INTERVAL             Check interval in seconds
    WEBHOOK_URL                Generic webhook URL
    DISCORD_WEBHOOK_URL        Discord webhook URL
    SLACK_WEBHOOK_URL          Slack webhook URL
    NOTIFICATION_LEVEL         Notification level
    METRICS_ENABLED            Enable metrics collection (true/false)
EOF
}

# Command line argument parsing
RUN_ONCE=false
TEST_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -l|--level)
            NOTIFICATION_LEVEL="$2"
            shift 2
            ;;
        -w|--webhook)
            WEBHOOK_URL="$2"
            shift 2
            ;;
        -d|--discord)
            DISCORD_WEBHOOK_URL="$2"
            shift 2
            ;;
        -s|--slack)
            SLACK_WEBHOOK_URL="$2"
            shift 2
            ;;
        --once)
            RUN_ONCE=true
            shift
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        *)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# Test mode
if [ "$TEST_MODE" = "true" ]; then
    log "INFO" "Testing notifications..."
    send_notification "🧪 Test Notification" "This is a test notification from transmissionvpn monitor" "info"
    exit 0
fi

# Main execution
log "INFO" "Starting transmissionvpn monitor (container: $CONTAINER_NAME, interval: ${CHECK_INTERVAL}s)"

if [ "$RUN_ONCE" = "true" ]; then
    monitor_container
    collect_metrics
    exit 0
fi

# Continuous monitoring loop
while true; do
    monitor_container
    collect_metrics
    sleep "$CHECK_INTERVAL"
done 
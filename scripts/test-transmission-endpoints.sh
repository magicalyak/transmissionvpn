#!/bin/bash

# Transmission Health and Metrics Testing Script
# This script tests all available endpoints for monitoring Transmission

set -e

CONTAINER_NAME="transmissionvpn"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Testing Transmission Health and Metrics Endpoints"
echo "===================================================="

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}❌ FAIL${NC}: $message"
    else
        echo -e "${BLUE}ℹ️  INFO${NC}: $message"
    fi
}

echo ""
echo "1. Basic Transmission Web UI Health Check"
echo "----------------------------------------"

# Test 1: Basic web UI health check
echo "Command: curl -sf http://localhost:9091/transmission/web/"
if curl -sf --max-time 5 http://localhost:9091/transmission/web/ > /dev/null 2>&1; then
    print_status "PASS" "Transmission web UI is responding"
else
    print_status "FAIL" "Transmission web UI is not responding"
fi

echo ""
echo "2. Transmission RPC API Health Check"
echo "-----------------------------------"

# Test 2: RPC API session check (this will return session ID error, but proves API is responding)
echo "Command: curl -s http://localhost:9091/transmission/rpc"
RPC_RESPONSE=$(curl -s --max-time 5 http://localhost:9091/transmission/rpc 2>/dev/null || echo "")
if echo "$RPC_RESPONSE" | grep -q "X-Transmission-Session-Id"; then
    print_status "PASS" "Transmission RPC API is responding"
    echo "Response: $(echo "$RPC_RESPONSE" | head -1)"
else
    print_status "FAIL" "Transmission RPC API is not responding"
fi

echo ""
echo "3. Built-in Prometheus Metrics (if enabled)"
echo "------------------------------------------"

# Test 3: Prometheus metrics endpoint
echo "Command: curl -s http://localhost:9099/metrics"
if curl -sf --max-time 5 http://localhost:9099/metrics > /dev/null 2>&1; then
    print_status "PASS" "Prometheus metrics endpoint is accessible"
    
    echo ""
    echo "📊 Available Metrics:"
    echo "-------------------"
    
    # Show key metrics
    METRICS=$(curl -s --max-time 5 http://localhost:9099/metrics 2>/dev/null || echo "")
    
    if echo "$METRICS" | grep -q "transmission_session_stats"; then
        print_status "INFO" "Transmission session stats available"
        echo "$METRICS" | grep "transmission_session_stats" | head -5
    fi
    
    if echo "$METRICS" | grep -q "transmission_free_space"; then
        print_status "INFO" "Transmission free space metrics available"
        echo "$METRICS" | grep "transmission_free_space"
    fi
    
    if echo "$METRICS" | grep -q "transmissionvpn_"; then
        print_status "INFO" "TransmissionVPN health metrics available"
        echo "$METRICS" | grep "transmissionvpn_" | head -3
    fi
    
else
    print_status "FAIL" "Prometheus metrics endpoint not accessible"
    echo "Note: Enable with TRANSMISSION_EXPORTER_ENABLED=true"
fi

echo ""
echo "4. Container Health Metrics (Internal)"
echo "-------------------------------------"

# Test 4: Internal health metrics (if container is accessible)
echo "Command: docker exec $CONTAINER_NAME cat /tmp/metrics.txt"
if docker exec "$CONTAINER_NAME" test -f /tmp/metrics.txt 2>/dev/null; then
    print_status "PASS" "Internal health metrics file exists"
    echo ""
    echo "📈 Recent Health Metrics:"
    echo "------------------------"
    docker exec "$CONTAINER_NAME" tail -10 /tmp/metrics.txt 2>/dev/null || echo "Could not read metrics"
else
    print_status "INFO" "Internal health metrics not enabled"
    echo "Note: Enable with METRICS_ENABLED=true"
fi

echo ""
echo "5. Health Check Logs"
echo "------------------"

# Test 5: Health check logs
echo "Command: docker exec $CONTAINER_NAME tail -5 /tmp/healthcheck.log"
if docker exec "$CONTAINER_NAME" test -f /tmp/healthcheck.log 2>/dev/null; then
    print_status "PASS" "Health check logs available"
    echo ""
    echo "📝 Recent Health Check Logs:"
    echo "----------------------------"
    docker exec "$CONTAINER_NAME" tail -5 /tmp/healthcheck.log 2>/dev/null || echo "Could not read logs"
else
    print_status "INFO" "Health check logs not found"
fi

echo ""
echo "6. Manual Health Check Execution"
echo "-------------------------------"

# Test 6: Run health check manually
echo "Command: docker exec $CONTAINER_NAME /root/healthcheck-smart.sh"
if docker exec "$CONTAINER_NAME" /root/healthcheck-smart.sh > /dev/null 2>&1; then
    print_status "PASS" "Smart health check passed"
else
    EXIT_CODE=$?
    case $EXIT_CODE in
        1) print_status "FAIL" "Health check failed - Transmission unhealthy" ;;
        2) print_status "FAIL" "Health check failed - VPN unhealthy" ;;
        3) print_status "FAIL" "Health check failed - Both Transmission and VPN unhealthy" ;;
        *) print_status "FAIL" "Health check failed - Unknown error (exit code: $EXIT_CODE)" ;;
    esac
fi

echo ""
echo "7. VPN Status Check"
echo "-----------------"

# Test 7: VPN interface check
echo "Command: docker exec $CONTAINER_NAME ip addr show tun0"
if docker exec "$CONTAINER_NAME" ip addr show tun0 > /dev/null 2>&1; then
    VPN_IP=$(docker exec "$CONTAINER_NAME" ip addr show tun0 | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    print_status "PASS" "VPN interface (tun0) is up with IP: $VPN_IP"
else
    print_status "INFO" "VPN interface (tun0) not found - checking for WireGuard (wg0)"
    if docker exec "$CONTAINER_NAME" ip addr show wg0 > /dev/null 2>&1; then
        VPN_IP=$(docker exec "$CONTAINER_NAME" ip addr show wg0 | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        print_status "PASS" "VPN interface (wg0) is up with IP: $VPN_IP"
    else
        print_status "FAIL" "No VPN interface found (tun0/wg0)"
    fi
fi

echo ""
echo "8. External IP Check (VPN Verification)"
echo "--------------------------------------"

# Test 8: External IP check
echo "Command: docker exec $CONTAINER_NAME curl -s --max-time 10 ifconfig.me"
EXTERNAL_IP=$(docker exec "$CONTAINER_NAME" curl -s --max-time 10 ifconfig.me 2>/dev/null || echo "")
if [ -n "$EXTERNAL_IP" ]; then
    print_status "PASS" "External IP accessible: $EXTERNAL_IP"
    echo "Note: Verify this is your VPN provider's IP, not your real IP"
else
    print_status "FAIL" "Could not determine external IP"
fi

echo ""
echo "9. Transmission Statistics via RPC"
echo "---------------------------------"

# Test 9: Get session stats via RPC (requires session ID)
echo "Getting Transmission session statistics..."

# First get session ID
SESSION_ID=$(curl -s http://localhost:9091/transmission/rpc 2>/dev/null | grep -o 'X-Transmission-Session-Id: [^<]*' | cut -d' ' -f2 || echo "")

if [ -n "$SESSION_ID" ]; then
    print_status "PASS" "Got session ID: $SESSION_ID"
    
    # Get session stats
    echo "Command: curl with session-get RPC call"
    STATS=$(curl -s -H "X-Transmission-Session-Id: $SESSION_ID" \
        -H "Content-Type: application/json" \
        -d '{"method":"session-stats"}' \
        http://localhost:9091/transmission/rpc 2>/dev/null || echo "")
    
    if echo "$STATS" | grep -q '"result":"success"'; then
        print_status "PASS" "Session statistics retrieved successfully"
        echo ""
        echo "📊 Transmission Statistics:"
        echo "--------------------------"
        echo "$STATS" | python3 -m json.tool 2>/dev/null || echo "$STATS"
    else
        print_status "FAIL" "Could not retrieve session statistics"
    fi
else
    print_status "FAIL" "Could not get session ID for RPC calls"
fi

echo ""
echo "🎯 Quick Reference Commands"
echo "=========================="
echo ""
echo "# Basic health check"
echo "curl -sf http://localhost:9091/transmission/web/"
echo ""
echo "# Prometheus metrics (if enabled)"
echo "curl -s http://localhost:9099/metrics"
echo ""
echo "# Get specific metrics"
echo "curl -s http://localhost:9099/metrics | grep transmission_session_stats"
echo "curl -s http://localhost:9099/metrics | grep transmission_free_space"
echo "curl -s http://localhost:9099/metrics | grep transmissionvpn_"
echo ""
echo "# Manual health checks"
echo "docker exec $CONTAINER_NAME /root/healthcheck-smart.sh"
echo "docker exec $CONTAINER_NAME /root/healthcheck-fixed.sh"
echo "docker exec $CONTAINER_NAME /root/healthcheck.sh"
echo ""
echo "# Check logs"
echo "docker exec $CONTAINER_NAME tail -10 /tmp/healthcheck.log"
echo "docker exec $CONTAINER_NAME tail -10 /tmp/metrics.txt"
echo ""
echo "# VPN status"
echo "docker exec $CONTAINER_NAME ip addr show tun0"
echo "docker exec $CONTAINER_NAME curl -s ifconfig.me"
echo ""
echo "# Container health status"
echo "docker ps --format 'table {{.Names}}\t{{.Status}}'"
echo "docker inspect --format='{{.State.Health.Status}}' $CONTAINER_NAME" 
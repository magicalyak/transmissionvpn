#!/bin/bash

# TransmissionVPN Fixes Verification Script
# This script verifies that all applied fixes are working correctly

set -e

CONTAINER_NAME="transmissionvpn"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 TransmissionVPN Fixes Verification"
echo "====================================="

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}❌ FAIL${NC}: $message"
    else
        echo -e "${YELLOW}ℹ️  INFO${NC}: $message"
    fi
}

# Check if container exists
echo ""
echo "1. Container Status Check"
echo "------------------------"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_status "PASS" "Container '$CONTAINER_NAME' exists"
    
    # Check if container is running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_status "PASS" "Container '$CONTAINER_NAME' is running"
        
        # Check container health
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no-healthcheck")
        if [ "$HEALTH_STATUS" = "healthy" ]; then
            print_status "PASS" "Container health status: $HEALTH_STATUS"
        elif [ "$HEALTH_STATUS" = "no-healthcheck" ]; then
            print_status "INFO" "No healthcheck configured"
        else
            print_status "FAIL" "Container health status: $HEALTH_STATUS"
        fi
    else
        print_status "FAIL" "Container '$CONTAINER_NAME' is not running"
        echo "Please start the container first: docker-compose up -d"
        exit 1
    fi
else
    print_status "FAIL" "Container '$CONTAINER_NAME' does not exist"
    echo "Please create the container first: docker-compose up -d"
    exit 1
fi

# Check Transmission functionality
echo ""
echo "2. Transmission Functionality Check"
echo "----------------------------------"

# Check if Transmission web UI is accessible
if docker exec "$CONTAINER_NAME" curl -sf --max-time 5 http://127.0.0.1:9091/transmission/web/ > /dev/null 2>&1; then
    print_status "PASS" "Transmission web UI is responding"
else
    print_status "FAIL" "Transmission web UI is not responding"
fi

# Check if Transmission daemon is running
if docker exec "$CONTAINER_NAME" pgrep -f "transmission-daemon" > /dev/null 2>&1; then
    print_status "PASS" "Transmission daemon process is running"
else
    print_status "FAIL" "Transmission daemon process is not running"
fi

# Check VPN status (informational)
echo ""
echo "3. VPN Status Check (Informational)"
echo "----------------------------------"

# Check for VPN interface
VPN_INTERFACE=""
if docker exec "$CONTAINER_NAME" ip link show tun0 > /dev/null 2>&1; then
    VPN_INTERFACE="tun0"
    print_status "INFO" "OpenVPN interface (tun0) detected"
elif docker exec "$CONTAINER_NAME" ip link show wg0 > /dev/null 2>&1; then
    VPN_INTERFACE="wg0"
    print_status "INFO" "WireGuard interface (wg0) detected"
else
    print_status "INFO" "No VPN interface detected (tun0/wg0)"
fi

if [ -n "$VPN_INTERFACE" ]; then
    # Check if VPN interface is UP
    if docker exec "$CONTAINER_NAME" ip link show "$VPN_INTERFACE" | grep -q "UP"; then
        print_status "INFO" "VPN interface $VPN_INTERFACE is UP"
        
        # Check if VPN interface has an IP
        if docker exec "$CONTAINER_NAME" ip addr show "$VPN_INTERFACE" | grep -q "inet "; then
            VPN_IP=$(docker exec "$CONTAINER_NAME" ip addr show "$VPN_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            print_status "INFO" "VPN interface has IP: $VPN_IP"
        else
            print_status "INFO" "VPN interface is UP but has no IP address"
        fi
    else
        print_status "INFO" "VPN interface $VPN_INTERFACE exists but is DOWN"
    fi
fi

# Check external IP (to verify VPN is working)
EXTERNAL_IP=$(docker exec "$CONTAINER_NAME" curl -sf --max-time 10 ifconfig.me 2>/dev/null || echo "")
if [ -n "$EXTERNAL_IP" ]; then
    print_status "INFO" "External IP: $EXTERNAL_IP"
else
    print_status "INFO" "Could not determine external IP (may indicate VPN or connectivity issue)"
fi

# Check healthcheck script
echo ""
echo "4. Healthcheck Script Verification"
echo "----------------------------------"

# Check if fixed healthcheck exists
if docker exec "$CONTAINER_NAME" test -f /root/healthcheck-fixed.sh; then
    print_status "PASS" "Fixed healthcheck script exists"
    
    # Check if it's executable
    if docker exec "$CONTAINER_NAME" test -x /root/healthcheck-fixed.sh; then
        print_status "PASS" "Fixed healthcheck script is executable"
        
        # Run the healthcheck
        if docker exec "$CONTAINER_NAME" /root/healthcheck-fixed.sh > /dev/null 2>&1; then
            print_status "PASS" "Fixed healthcheck script runs successfully"
        else
            print_status "FAIL" "Fixed healthcheck script failed"
        fi
    else
        print_status "FAIL" "Fixed healthcheck script is not executable"
    fi
else
    print_status "FAIL" "Fixed healthcheck script does not exist"
fi

# Check metrics availability
echo ""
echo "5. Metrics Availability Check"
echo "-----------------------------"

# Check if metrics endpoint is accessible
if curl -sf --max-time 5 http://localhost:9099/metrics > /dev/null 2>&1; then
    print_status "PASS" "Metrics endpoint is accessible"
    
    # Check for specific Transmission metrics
    METRICS_OUTPUT=$(curl -sf --max-time 5 http://localhost:9099/metrics 2>/dev/null || echo "")
    if echo "$METRICS_OUTPUT" | grep -q "transmission_session_stats"; then
        print_status "PASS" "Transmission session stats metrics are available"
    else
        print_status "INFO" "Transmission session stats metrics not found"
    fi
    
    if echo "$METRICS_OUTPUT" | grep -q "transmission_free_space"; then
        print_status "PASS" "Transmission free space metrics are available"
    else
        print_status "INFO" "Transmission free space metrics not found"
    fi
else
    print_status "INFO" "Metrics endpoint not accessible (may not be enabled)"
fi

# Summary
echo ""
echo "6. Summary"
echo "----------"

# Check if all critical components are working
CRITICAL_CHECKS=0
CRITICAL_PASSED=0

# Transmission web UI
if docker exec "$CONTAINER_NAME" curl -sf --max-time 5 http://127.0.0.1:9091/transmission/web/ > /dev/null 2>&1; then
    CRITICAL_PASSED=$((CRITICAL_PASSED + 1))
fi
CRITICAL_CHECKS=$((CRITICAL_CHECKS + 1))

# Transmission daemon
if docker exec "$CONTAINER_NAME" pgrep -f "transmission-daemon" > /dev/null 2>&1; then
    CRITICAL_PASSED=$((CRITICAL_PASSED + 1))
fi
CRITICAL_CHECKS=$((CRITICAL_CHECKS + 1))

# Healthcheck script
if docker exec "$CONTAINER_NAME" /root/healthcheck-fixed.sh > /dev/null 2>&1; then
    CRITICAL_PASSED=$((CRITICAL_PASSED + 1))
fi
CRITICAL_CHECKS=$((CRITICAL_CHECKS + 1))

if [ $CRITICAL_PASSED -eq $CRITICAL_CHECKS ]; then
    print_status "PASS" "All critical checks passed ($CRITICAL_PASSED/$CRITICAL_CHECKS)"
    echo ""
    echo -e "${GREEN}🎉 TransmissionVPN fixes are working correctly!${NC}"
    echo ""
    echo "Next steps:"
    echo "- Access Transmission at: http://localhost:9091"
    echo "- Monitor health: docker exec $CONTAINER_NAME /root/healthcheck-fixed.sh"
    echo "- Check logs: docker logs $CONTAINER_NAME"
else
    print_status "FAIL" "Some critical checks failed ($CRITICAL_PASSED/$CRITICAL_CHECKS)"
    echo ""
    echo -e "${RED}⚠️  Some issues detected. Please check the failed items above.${NC}"
fi

echo ""
echo "For detailed logs:"
echo "- Container logs: docker logs $CONTAINER_NAME"
echo "- Health logs: docker exec $CONTAINER_NAME tail -10 /tmp/healthcheck.log"
echo "- VPN logs: docker exec $CONTAINER_NAME cat /tmp/openvpn.log" 
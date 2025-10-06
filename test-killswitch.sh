#!/bin/bash
# Kill Switch Test Script for transmissionvpn
# Tests the VPN kill switch to ensure it properly prevents IP leaks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Container name (can be overridden)
CONTAINER_NAME="${1:-transmissionvpn}"

echo "================================================"
echo "     VPN Kill Switch Verification Test"
echo "================================================"
echo ""

# Helper functions
log_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=true
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_info() {
    echo -e "ℹ $1"
}

# Check if container is running
echo "1. Checking container status..."
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    log_fail "Container '$CONTAINER_NAME' is not running"
    echo "   Please start the container first: docker-compose up -d"
    exit 1
else
    log_pass "Container is running"
fi

# Test 1: Check iptables default policies
echo ""
echo "2. Checking firewall default policies..."
POLICIES=$(docker exec "$CONTAINER_NAME" iptables -S | grep "^-P")

if echo "$POLICIES" | grep -q "INPUT DROP"; then
    log_pass "INPUT policy is DROP"
else
    log_fail "INPUT policy is not DROP"
    echo "   Current: $(echo "$POLICIES" | grep INPUT)"
fi

if echo "$POLICIES" | grep -q "FORWARD DROP"; then
    log_pass "FORWARD policy is DROP"
else
    log_fail "FORWARD policy is not DROP"
    echo "   Current: $(echo "$POLICIES" | grep FORWARD)"
fi

if echo "$POLICIES" | grep -q "OUTPUT DROP"; then
    log_pass "OUTPUT policy is DROP (strict kill switch)"
else
    log_warn "OUTPUT policy is not DROP"
    echo "   Current: $(echo "$POLICIES" | grep OUTPUT)"
    echo "   Note: Some configurations use ACCEPT with explicit DROP rules"
fi

# Test 2: Check DNS leak prevention
echo ""
echo "3. Checking DNS leak prevention..."
DNS_RULES=$(docker exec "$CONTAINER_NAME" iptables -L OUTPUT -n | grep "dpt:53" || true)

if [ -n "$DNS_RULES" ]; then
    if echo "$DNS_RULES" | grep -q "DROP"; then
        log_pass "DNS queries are blocked on non-VPN interfaces"
        echo "   Found $(echo "$DNS_RULES" | wc -l) DNS blocking rules"
    else
        log_warn "DNS rules found but not blocking"
    fi
else
    log_fail "No DNS leak prevention rules found"
fi

# Test 3: Check VPN interface
echo ""
echo "4. Checking VPN interface..."
VPN_IF=$(docker exec "$CONTAINER_NAME" sh -c 'cat /tmp/vpn_interface_name 2>/dev/null || echo "unknown"')

if [ "$VPN_IF" != "unknown" ]; then
    log_info "VPN interface: $VPN_IF"

    # Check if interface exists
    if docker exec "$CONTAINER_NAME" ip link show "$VPN_IF" >/dev/null 2>&1; then
        log_pass "VPN interface exists"

        # Check if it has an IP
        if docker exec "$CONTAINER_NAME" ip addr show "$VPN_IF" | grep -q "inet "; then
            log_pass "VPN interface has an IP address"
            VPN_IP=$(docker exec "$CONTAINER_NAME" ip addr show "$VPN_IF" | grep "inet " | awk '{print $2}')
            log_info "VPN IP: $VPN_IP"
        else
            log_fail "VPN interface has no IP address"
        fi

        # Check if traffic is allowed through VPN
        if docker exec "$CONTAINER_NAME" iptables -L OUTPUT -n | grep -q "$VPN_IF.*ACCEPT"; then
            log_pass "Traffic allowed through VPN interface"
        else
            log_fail "No rules allowing traffic through VPN interface"
        fi
    else
        log_fail "VPN interface $VPN_IF does not exist"
    fi
else
    log_fail "Could not determine VPN interface"
fi

# Test 4: Check external IP (if VPN is up)
echo ""
echo "5. Checking external IP..."
EXTERNAL_IP=$(docker exec "$CONTAINER_NAME" curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "FAILED")

if [ "$EXTERNAL_IP" != "FAILED" ]; then
    log_pass "External IP obtained: $EXTERNAL_IP"
    log_warn "Verify this is your VPN provider's IP, not your real IP!"
else
    log_info "Could not get external IP (this is expected if kill switch is active)"
fi

# Test 5: Simulate VPN failure
echo ""
echo "6. Testing VPN failure scenario..."
read -p "Do you want to simulate VPN failure? This will temporarily disable the VPN interface. (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Simulating VPN failure..."

    # Get current state
    BEFORE_STATUS=$(docker exec "$CONTAINER_NAME" sh -c 'pgrep transmission-daemon >/dev/null && echo "running" || echo "stopped"')
    log_info "Transmission status before: $BEFORE_STATUS"

    # Disable VPN interface
    docker exec "$CONTAINER_NAME" ip link set "$VPN_IF" down 2>/dev/null || true
    log_info "VPN interface disabled"

    # Wait for monitor to react
    log_info "Waiting 10 seconds for VPN monitor to react..."
    sleep 10

    # Check if traffic is blocked
    TEST_IP=$(docker exec "$CONTAINER_NAME" curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "BLOCKED")

    if [ "$TEST_IP" = "BLOCKED" ]; then
        log_pass "Internet access blocked when VPN is down (kill switch working!)"
    else
        log_fail "CRITICAL: Internet accessible without VPN! IP: $TEST_IP"
    fi

    # Check Transmission status
    AFTER_STATUS=$(docker exec "$CONTAINER_NAME" sh -c 'pgrep transmission-daemon >/dev/null && echo "running" || echo "stopped"')

    if [ "$AFTER_STATUS" = "stopped" ]; then
        log_pass "Transmission stopped when VPN failed"
    else
        log_warn "Transmission still running (check VPN_MAX_FAILURES setting)"
    fi

    # Try to restore VPN
    log_info "Attempting to restore VPN interface..."
    docker exec "$CONTAINER_NAME" ip link set "$VPN_IF" up 2>/dev/null || true
    echo "   You may need to restart the container to fully restore VPN"
fi

# Test 6: Check Transmission UI accessibility
echo ""
echo "7. Checking Transmission UI accessibility..."
UI_PORT=$(docker port "$CONTAINER_NAME" 9091 2>/dev/null | cut -d: -f2)

if [ -n "$UI_PORT" ]; then
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$UI_PORT/transmission/web/" | grep -q "200\|401"; then
        log_pass "Transmission UI is accessible on port $UI_PORT"
    else
        log_warn "Transmission UI not responding properly on port $UI_PORT"
    fi
else
    log_info "Transmission UI port not mapped to host"
fi

# Test 7: Check VPN monitor service
echo ""
echo "8. Checking VPN monitor service..."
if docker exec "$CONTAINER_NAME" sh -c 'ps aux | grep -q "[v]pn-monitor"'; then
    log_pass "VPN monitor service is running"

    # Check monitor configuration
    CHECK_INTERVAL=$(docker exec "$CONTAINER_NAME" sh -c 'echo $VPN_CHECK_INTERVAL')
    MAX_FAILURES=$(docker exec "$CONTAINER_NAME" sh -c 'echo $VPN_MAX_FAILURES')

    log_info "Monitor configuration:"
    log_info "  Check interval: ${CHECK_INTERVAL:-30} seconds"
    log_info "  Max failures: ${MAX_FAILURES:-3}"
else
    log_warn "VPN monitor service not found"
fi

# Test 8: Check for DNS leaks
echo ""
echo "9. Testing for DNS leaks..."
DNS_SERVERS=$(docker exec "$CONTAINER_NAME" cat /etc/resolv.conf | grep nameserver | awk '{print $2}')

log_info "DNS servers in use:"
echo "$DNS_SERVERS" | while read -r server; do
    echo "   - $server"
done

# Try DNS resolution
if docker exec "$CONTAINER_NAME" nslookup google.com >/dev/null 2>&1; then
    log_info "DNS resolution working"
else
    log_warn "DNS resolution not working (expected if VPN is down)"
fi

# Summary
echo ""
echo "================================================"
echo "                   SUMMARY"
echo "================================================"

if [ "$FAILED" = "true" ]; then
    echo -e "${RED}Some tests failed. Please review the results above.${NC}"
    echo ""
    echo "Common issues:"
    echo "- Ensure the container was built with the latest security updates"
    echo "- Check that VPN credentials are correctly configured"
    echo "- Verify VPN configuration files are in place"
    exit 1
else
    echo -e "${GREEN}All critical tests passed!${NC}"
    echo ""
    echo "Recommendations:"
    echo "1. Verify the external IP is from your VPN provider"
    echo "2. Test the kill switch by disconnecting the VPN"
    echo "3. Monitor logs: docker logs -f $CONTAINER_NAME"
    echo "4. Check kill switch status: docker exec $CONTAINER_NAME /root/vpn-killswitch.sh status"
fi

echo ""
echo "For detailed verification, see: docs/KILLSWITCH_VERIFICATION.md"
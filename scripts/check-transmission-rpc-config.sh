#!/bin/bash

echo "=== CHECKING TRANSMISSION RPC CONFIGURATION ==="
echo "Date: $(date)"
echo ""

CONTAINER_NAME="transmission"

echo "1. CHECKING TRANSMISSION CONFIGURATION FILE:"
echo "==========================================="
docker exec $CONTAINER_NAME cat /config/settings.json 2>/dev/null | grep -E "(rpc-|username|password)" || echo "Settings file not found or no RPC settings"
echo ""

echo "2. CHECKING ENVIRONMENT VARIABLES:"
echo "================================="
docker exec $CONTAINER_NAME env | grep -E "(TRANSMISSION_RPC|RPC)" || echo "No RPC environment variables"
echo ""

echo "3. CHECKING CURRENT EXPORTER CONFIGURATION:"
echo "=========================================="
docker exec $CONTAINER_NAME ps aux | grep transmission-exporter | grep -v grep || echo "Exporter not running"
echo ""

echo "4. TESTING RPC WITH DIFFERENT AUTHENTICATION:"
echo "============================================"
# Test without authentication
echo "Testing without auth:"
docker exec $CONTAINER_NAME curl -s http://127.0.0.1:9091/transmission/rpc -H "X-Transmission-Session-Id: test" 2>/dev/null | head -3

# Test with authentication from environment
echo -e "\nTesting with environment auth:"
RPC_USER=$(docker exec $CONTAINER_NAME env | grep TRANSMISSION_RPC_USERNAME | cut -d= -f2)
RPC_PASS=$(docker exec $CONTAINER_NAME env | grep TRANSMISSION_RPC_PASSWORD | cut -d= -f2)
echo "RPC User: $RPC_USER"
echo "RPC Pass: [MASKED]"

if [ -n "$RPC_USER" ] && [ -n "$RPC_PASS" ]; then
    docker exec $CONTAINER_NAME curl -s -u "$RPC_USER:$RPC_PASS" http://127.0.0.1:9091/transmission/rpc -H "X-Transmission-Session-Id: test" 2>/dev/null | head -3
else
    echo "No RPC credentials found in environment"
fi
echo ""

echo "5. CHECKING TRANSMISSION DAEMON STATUS:"
echo "======================================"
docker exec $CONTAINER_NAME ps aux | grep transmission-daemon | grep -v grep
echo ""

echo "6. TESTING EXPORTER WITH CORRECT CREDENTIALS:"
echo "============================================"
if [ -n "$RPC_USER" ] && [ -n "$RPC_PASS" ]; then
    echo "Starting test exporter with environment credentials..."
    docker exec $CONTAINER_NAME bash -c "
        /usr/local/bin/transmission-exporter \
            --webaddr=:9098 \
            --transmissionaddr=http://127.0.0.1:9091 \
            --transmissionusername='$RPC_USER' \
            --transmissionpassword='$RPC_PASS' &
        sleep 5
        curl -s http://127.0.0.1:9098/metrics | head -5 || echo 'Test exporter failed'
        pkill -f 'transmission-exporter.*9098'
    "
else
    echo "No credentials available for testing"
fi
echo ""

echo "7. RECOMMENDED EXPORTER COMMAND:"
echo "==============================="
if [ -n "$RPC_USER" ] && [ -n "$RPC_PASS" ]; then
    echo "/usr/local/bin/transmission-exporter \\"
    echo "    --webaddr=:9099 \\"
    echo "    --transmissionaddr=http://127.0.0.1:9091 \\"
    echo "    --transmissionusername='$RPC_USER' \\"
    echo "    --transmissionpassword='$RPC_PASS'"
else
    echo "Cannot determine correct credentials"
fi
echo ""

echo "=== RPC CONFIGURATION CHECK COMPLETE ===" 
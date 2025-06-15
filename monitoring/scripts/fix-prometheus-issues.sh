#!/bin/bash

# Fix Prometheus Issues Script
# Comprehensive troubleshooting and fixes for Prometheus monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TRANSMISSION_CONTAINER=${TRANSMISSION_CONTAINER:-transmission}
PROMETHEUS_CONTAINER=${PROMETHEUS_CONTAINER:-prometheus}
GRAFANA_CONTAINER=${GRAFANA_CONTAINER:-grafana}
METRICS_PORT=${METRICS_PORT:-9099}

echo -e "${BLUE}=== TransmissionVPN Prometheus Monitoring Fix ===${NC}"
echo "This script will diagnose and fix common Prometheus monitoring issues"
echo

# Function to check if container exists and is running
check_container() {
    local container_name=$1
    if docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${GREEN}✓${NC} Container $container_name is running"
        return 0
    elif docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${YELLOW}⚠${NC} Container $container_name exists but is not running"
        return 1
    else
        echo -e "${RED}✗${NC} Container $container_name does not exist"
        return 2
    fi
}

# Function to test endpoint
test_endpoint() {
    local url=$1
    local description=$2
    
    echo -n "Testing $description... "
    if curl -s --max-time 10 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Function to check network connectivity
check_network() {
    local from_container=$1
    local to_container=$2
    local port=$3
    
    echo -n "Testing network connectivity from $from_container to $to_container:$port... "
    if docker exec "$from_container" nc -z "$to_container" "$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

echo -e "${BLUE}1. Checking Container Status${NC}"
echo "================================"

# Check TransmissionVPN container
if ! check_container "$TRANSMISSION_CONTAINER"; then
    echo -e "${RED}Error: TransmissionVPN container is not running${NC}"
    echo "  Fix: Start the TransmissionVPN container first"
    echo "  Command: docker start $TRANSMISSION_CONTAINER"
    exit 1
fi

# Check Prometheus container
if ! check_container "$PROMETHEUS_CONTAINER"; then
    echo -e "${YELLOW}Warning: Prometheus container is not running${NC}"
    echo "  Fix: Start the monitoring stack"
    echo "  Command: cd monitoring/docker-compose && docker-compose up -d"
fi

# Check Grafana container
if ! check_container "$GRAFANA_CONTAINER"; then
    echo -e "${YELLOW}Warning: Grafana container is not running${NC}"
    echo "  Fix: Start the monitoring stack"
    echo "  Command: cd monitoring/docker-compose && docker-compose up -d"
fi

echo
echo -e "${BLUE}2. Checking TransmissionVPN Configuration${NC}"
echo "=========================================="

# Check if metrics are enabled
METRICS_ENABLED=$(docker exec $TRANSMISSION_CONTAINER printenv METRICS_ENABLED 2>/dev/null || echo "not_set")
METRICS_PORT_ENV=$(docker exec $TRANSMISSION_CONTAINER printenv METRICS_PORT 2>/dev/null || echo "not_set")
METRICS_INTERVAL=$(docker exec $TRANSMISSION_CONTAINER printenv METRICS_INTERVAL 2>/dev/null || echo "not_set")

echo "Current TransmissionVPN configuration:"
echo "  METRICS_ENABLED: $METRICS_ENABLED"
echo "  METRICS_PORT: $METRICS_PORT_ENV"
echo "  METRICS_INTERVAL: $METRICS_INTERVAL"

# Check if metrics are properly enabled
if [ "$METRICS_ENABLED" != "true" ]; then
    echo -e "${RED}✗${NC} Metrics are not enabled"
    echo "  Fix: Set METRICS_ENABLED=true for enhanced health monitoring"
    echo
    echo "Add this to your .env file or docker-compose.yml:"
    echo "---"
    cat << 'EOF'
# TransmissionVPN Metrics Configuration
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
EOF
    echo "---"
    echo
    echo "Then restart the container:"
    echo "  docker restart $TRANSMISSION_CONTAINER"
    echo
fi

echo
echo -e "${BLUE}3. Testing TransmissionVPN Endpoints${NC}"
echo "===================================="

# Get container IP for testing
TRANSMISSION_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TRANSMISSION_CONTAINER" 2>/dev/null || echo "unknown")
echo "TransmissionVPN container IP: $TRANSMISSION_IP"

# Test endpoints
if [ "$TRANSMISSION_IP" != "unknown" ] && [ "$TRANSMISSION_IP" != "" ]; then
    test_endpoint "http://$TRANSMISSION_IP:9091/transmission/web/" "Transmission Web UI"
    test_endpoint "http://$TRANSMISSION_IP:$METRICS_PORT/metrics" "Prometheus metrics endpoint"
    test_endpoint "http://$TRANSMISSION_IP:$METRICS_PORT/health" "Health endpoint"
    test_endpoint "http://$TRANSMISSION_IP:$METRICS_PORT/health/simple" "Simple health endpoint"
else
    echo -e "${YELLOW}⚠${NC} Cannot determine container IP, skipping direct endpoint tests"
fi

echo
echo -e "${BLUE}4. Checking Network Connectivity${NC}"
echo "================================="

# Check if Prometheus can reach TransmissionVPN
if check_container "$PROMETHEUS_CONTAINER" >/dev/null 2>&1; then
    check_network "$PROMETHEUS_CONTAINER" "$TRANSMISSION_CONTAINER" "9091"
    check_network "$PROMETHEUS_CONTAINER" "$TRANSMISSION_CONTAINER" "$METRICS_PORT"
else
    echo "Skipping network tests (Prometheus not running)"
fi

echo
echo -e "${BLUE}5. Checking Prometheus Configuration${NC}"
echo "===================================="

if check_container "$PROMETHEUS_CONTAINER" >/dev/null 2>&1; then
    echo "Checking Prometheus targets..."
    
    # Get Prometheus targets
    PROMETHEUS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$PROMETHEUS_CONTAINER" 2>/dev/null)
    if [ "$PROMETHEUS_IP" != "" ]; then
        if curl -s "http://$PROMETHEUS_IP:9090/api/v1/targets" | grep -q "$TRANSMISSION_CONTAINER"; then
            echo -e "${GREEN}✓${NC} TransmissionVPN target found in Prometheus configuration"
        else
            echo -e "${RED}✗${NC} TransmissionVPN target not found in Prometheus configuration"
            echo "  Fix: Check prometheus.yml configuration"
        fi
    fi
else
    echo "Prometheus not running, skipping configuration check"
fi

echo
echo -e "${BLUE}6. Generating Fix Commands${NC}"
echo "=========================="

echo "If you're still having issues, try these commands:"
echo
echo "# Restart TransmissionVPN with metrics enabled:"
echo "docker stop $TRANSMISSION_CONTAINER"
echo "docker run -d --name $TRANSMISSION_CONTAINER \\"
echo "  -e METRICS_ENABLED=true \\"
echo "  -e METRICS_PORT=$METRICS_PORT \\"
echo "  -e METRICS_INTERVAL=30 \\"
echo "  -p 9091:9091 \\"
echo "  -p $METRICS_PORT:$METRICS_PORT \\"
echo "  [other options] \\"
echo "  magicalyak/transmissionvpn:latest"
echo
echo "# Test endpoints manually:"
echo "curl http://localhost:9091/transmission/web/"
echo "curl http://localhost:$METRICS_PORT/metrics"
echo "curl http://localhost:$METRICS_PORT/health"
echo
echo "# Check Prometheus targets:"
echo "curl http://localhost:9090/api/v1/targets"
echo
echo "# View container logs:"
echo "docker logs $TRANSMISSION_CONTAINER"
echo "docker logs $PROMETHEUS_CONTAINER"

echo
echo -e "${BLUE}7. Quick Health Check${NC}"
echo "===================="

# Final health check
echo "Performing final health check..."

HEALTH_STATUS="unknown"
if [ "$TRANSMISSION_IP" != "unknown" ] && [ "$TRANSMISSION_IP" != "" ]; then
    if curl -s --max-time 5 "http://$TRANSMISSION_IP:$METRICS_PORT/health/simple" | grep -q "OK"; then
        HEALTH_STATUS="healthy"
        echo -e "${GREEN}✓${NC} TransmissionVPN health check: PASSED"
    else
        HEALTH_STATUS="unhealthy"
        echo -e "${RED}✗${NC} TransmissionVPN health check: FAILED"
    fi
else
    echo -e "${YELLOW}⚠${NC} Cannot perform health check (container IP unknown)"
fi

echo
echo -e "${BLUE}=== Summary ===${NC}"
if [ "$HEALTH_STATUS" = "healthy" ] && [ "$METRICS_ENABLED" = "true" ]; then
    echo -e "${GREEN}✓ All checks passed! Monitoring should be working.${NC}"
elif [ "$METRICS_ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠ Metrics are disabled. Enable with METRICS_ENABLED=true${NC}"
else
    echo -e "${RED}✗ Issues detected. Review the output above for fixes.${NC}"
fi

echo
echo "For more help, check:"
echo "  - Main README: https://github.com/magicalyak/transmissionvpn"
echo "  - Monitoring docs: monitoring/README.md"
echo "  - Health check options: HEALTHCHECK_OPTIONS.md" 
#!/bin/bash

# Fix Prometheus Issues Script for TransmissionVPN
# This script helps diagnose and fix common Prometheus monitoring issues

set -e

echo "=== TransmissionVPN Prometheus Troubleshooting ==="
echo

# Configuration
TRANSMISSION_CONTAINER="transmission"
PROMETHEUS_CONTAINER="prometheus"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if containers are running
check_containers() {
    print_status "Checking container status..."
    
    if docker ps --format "table {{.Names}}" | grep -q "^${TRANSMISSION_CONTAINER}$"; then
        print_status "✓ TransmissionVPN container is running"
    else
        print_error "✗ TransmissionVPN container is not running"
        echo "  Fix: Start the container with: docker start $TRANSMISSION_CONTAINER"
        return 1
    fi
    
    if docker ps --format "table {{.Names}}" | grep -q "^${PROMETHEUS_CONTAINER}$"; then
        print_status "✓ Prometheus container is running"
    else
        print_warning "⚠ Prometheus container is not running"
        echo "  Fix: Start monitoring stack with: cd monitoring && docker-compose up -d"
    fi
}

# Check network connectivity
check_network() {
    print_status "Checking network connectivity..."
    
    # Check if containers are on the same network
    TRANSMISSION_NETWORKS=$(docker inspect $TRANSMISSION_CONTAINER --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
    print_status "TransmissionVPN networks: $TRANSMISSION_NETWORKS"
    
    if docker ps --format "table {{.Names}}" | grep -q "^${PROMETHEUS_CONTAINER}$"; then
        PROMETHEUS_NETWORKS=$(docker inspect $PROMETHEUS_CONTAINER --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
        print_status "Prometheus networks: $PROMETHEUS_NETWORKS"
        
        # Test connectivity from Prometheus to TransmissionVPN
        if docker exec $PROMETHEUS_CONTAINER wget -q --spider --timeout=5 http://transmissionvpn:9099/metrics 2>/dev/null; then
            print_status "✓ Network connectivity: Prometheus can reach TransmissionVPN:9099"
        else
            print_error "✗ Network connectivity: Prometheus cannot reach TransmissionVPN:9099"
            echo "  Fix: Ensure both containers are on the same Docker network"
        fi
    fi
}

# Check metrics endpoints
check_metrics() {
    print_status "Checking metrics endpoints..."
    
    # Check built-in exporter endpoint
    if curl -s --connect-timeout 5 http://localhost:9099/metrics > /dev/null; then
        print_status "✓ Built-in Prometheus exporter responding on port 9099"
        
        # Check if we get actual metrics
        METRICS_COUNT=$(curl -s http://localhost:9099/metrics | grep -c "^transmission_" || echo "0")
        if [ "$METRICS_COUNT" -gt 0 ]; then
            print_status "✓ Found $METRICS_COUNT transmission metrics"
        else
            print_warning "⚠ Endpoint responding but no transmission metrics found"
        fi
    else
        print_error "✗ Built-in Prometheus exporter not responding on port 9099"
        echo "  Fix: Ensure TRANSMISSION_EXPORTER_ENABLED=true in your env file"
    fi
    
    # Check if external metrics server is running
    if curl -s --connect-timeout 5 http://localhost:8081/prometheus > /dev/null; then
        print_warning "⚠ External metrics server detected on port 8081"
        echo "  This might be conflicting with built-in metrics"
        echo "  Consider using only one metrics approach"
    fi
}

# Check environment configuration
check_env_config() {
    print_status "Checking environment configuration..."
    
    # Extract environment variables from running container
    EXPORTER_ENABLED=$(docker exec $TRANSMISSION_CONTAINER printenv TRANSMISSION_EXPORTER_ENABLED 2>/dev/null || echo "not_set")
    EXPORTER_PORT=$(docker exec $TRANSMISSION_CONTAINER printenv TRANSMISSION_EXPORTER_PORT 2>/dev/null || echo "not_set")
    METRICS_ENABLED=$(docker exec $TRANSMISSION_CONTAINER printenv METRICS_ENABLED 2>/dev/null || echo "not_set")
    
    print_status "Current configuration:"
    echo "  TRANSMISSION_EXPORTER_ENABLED: $EXPORTER_ENABLED"
    echo "  TRANSMISSION_EXPORTER_PORT: $EXPORTER_PORT"
    echo "  METRICS_ENABLED: $METRICS_ENABLED"
    
    # Check for issues
    if [ "$EXPORTER_ENABLED" != "true" ]; then
        print_error "✗ Built-in Prometheus exporter is disabled"
        echo "  Fix: Set TRANSMISSION_EXPORTER_ENABLED=true in your env file"
    fi
    
    if [ "$METRICS_ENABLED" != "true" ]; then
        print_warning "⚠ Internal health metrics are disabled"
        echo "  Fix: Set METRICS_ENABLED=true for enhanced health monitoring"
    fi
}

# Generate fixed configuration
generate_fixed_config() {
    print_status "Generating fixed configuration..."
    
    cat > transmission-fixed.env << 'EOF'
# Fixed TransmissionVPN Configuration for Prometheus Monitoring

# Enable built-in Prometheus exporter (REQUIRED for Prometheus integration)
TRANSMISSION_EXPORTER_ENABLED=true
TRANSMISSION_EXPORTER_PORT=9099

# Enable internal health metrics (RECOMMENDED for comprehensive monitoring)
METRICS_ENABLED=true

# Enable leak detection for security monitoring
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true

# Health check configuration
HEALTH_CHECK_HOST=8.8.8.8

# Add these to your existing transmission.env file
EOF
    
    print_status "✓ Created transmission-fixed.env with correct settings"
    print_status "Copy these settings to your existing transmission.env file"
}

# Test Prometheus scraping
test_prometheus_scraping() {
    if docker ps --format "table {{.Names}}" | grep -q "^${PROMETHEUS_CONTAINER}$"; then
        print_status "Testing Prometheus scraping..."
        
        # Check if targets are up
        if curl -s http://localhost:9090/api/v1/targets | grep -q "transmissionvpn"; then
            print_status "✓ Prometheus has TransmissionVPN targets configured"
            
            # Check target health
            UP_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job | contains("transmission")) | .health' 2>/dev/null | grep -c "up" || echo "0")
            TOTAL_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job | contains("transmission")) | .health' 2>/dev/null | wc -l || echo "0")
            
            print_status "Target health: $UP_TARGETS/$TOTAL_TARGETS targets up"
        else
            print_error "✗ No TransmissionVPN targets found in Prometheus"
            echo "  Fix: Check prometheus.yml configuration"
        fi
    else
        print_warning "⚠ Cannot test Prometheus scraping - Prometheus not running"
    fi
}

# Provide solution steps
provide_solutions() {
    print_status "=== SOLUTION STEPS ==="
    echo
    print_status "1. Update your transmission.env file:"
    echo "   Add these lines to /opt/containerd/env/transmission.env:"
    echo "   TRANSMISSION_EXPORTER_ENABLED=true"
    echo "   METRICS_ENABLED=true"
    echo "   CHECK_DNS_LEAK=true"
    echo "   CHECK_IP_LEAK=true"
    echo
    print_status "2. Restart the TransmissionVPN container:"
    echo "   docker restart $TRANSMISSION_CONTAINER"
    echo
    print_status "3. Update your Prometheus configuration:"
    echo "   Ensure prometheus.yml targets use container names, not localhost:"
    echo "   - targets: ['transmissionvpn:9099']  # Not localhost:9099"
    echo
    print_status "4. Restart Prometheus:"
    echo "   docker restart $PROMETHEUS_CONTAINER"
    echo
    print_status "5. Verify metrics are working:"
    echo "   curl http://localhost:9099/metrics | grep transmission_"
    echo "   curl http://localhost:9090/api/v1/targets"
    echo
}

# Main execution
main() {
    check_containers || exit 1
    check_network
    check_metrics
    check_env_config
    generate_fixed_config
    test_prometheus_scraping
    provide_solutions
    
    echo
    print_status "=== TROUBLESHOOTING COMPLETE ==="
    print_status "Follow the solution steps above to fix the issues"
}

# Run main function
main "$@" 
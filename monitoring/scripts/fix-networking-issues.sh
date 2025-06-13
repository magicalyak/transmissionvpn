#!/bin/bash

# Fix Docker Networking Issues for TransmissionVPN + Prometheus
# This script diagnoses and fixes container networking problems

set -e

echo "=== TransmissionVPN + Prometheus Networking Fix ==="
echo

# Configuration
TRANSMISSION_CONTAINER="transmission"
PROMETHEUS_CONTAINER="prometheus"
GRAFANA_CONTAINER="grafana"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_action() {
    echo -e "${BLUE}[ACTION]${NC} $1"
}

# Check container status
check_containers() {
    print_status "Checking container status..."
    
    for container in $TRANSMISSION_CONTAINER $PROMETHEUS_CONTAINER; do
        if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
            print_status "✓ Container $container is running"
        else
            print_error "✗ Container $container is not running"
            return 1
        fi
    done
}

# Check container networks
check_networks() {
    print_status "Analyzing container networks..."
    
    # Get networks for each container
    TRANSMISSION_NETWORKS=$(docker inspect $TRANSMISSION_CONTAINER --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "container_not_found")
    PROMETHEUS_NETWORKS=$(docker inspect $PROMETHEUS_CONTAINER --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "container_not_found")
    
    print_status "TransmissionVPN networks: $TRANSMISSION_NETWORKS"
    print_status "Prometheus networks: $PROMETHEUS_NETWORKS"
    
    # Check for common networks
    COMMON_NETWORKS=""
    for net in $TRANSMISSION_NETWORKS; do
        if echo "$PROMETHEUS_NETWORKS" | grep -q "$net"; then
            COMMON_NETWORKS="$COMMON_NETWORKS $net"
        fi
    done
    
    if [ -n "$COMMON_NETWORKS" ]; then
        print_status "✓ Containers share network(s): $COMMON_NETWORKS"
        return 0
    else
        print_error "✗ Containers are on different networks!"
        print_error "  TransmissionVPN: $TRANSMISSION_NETWORKS"
        print_error "  Prometheus: $PROMETHEUS_NETWORKS"
        return 1
    fi
}

# Test connectivity
test_connectivity() {
    print_status "Testing container connectivity..."
    
    # Test from Prometheus to TransmissionVPN
    if docker exec $PROMETHEUS_CONTAINER nslookup $TRANSMISSION_CONTAINER >/dev/null 2>&1; then
        print_status "✓ DNS resolution: Prometheus can resolve $TRANSMISSION_CONTAINER"
    else
        print_error "✗ DNS resolution: Prometheus cannot resolve $TRANSMISSION_CONTAINER"
        return 1
    fi
    
    # Test HTTP connectivity
    if docker exec $PROMETHEUS_CONTAINER wget -q --spider --timeout=5 http://$TRANSMISSION_CONTAINER:9099/metrics 2>/dev/null; then
        print_status "✓ HTTP connectivity: Prometheus can reach $TRANSMISSION_CONTAINER:9099"
    else
        print_error "✗ HTTP connectivity: Prometheus cannot reach $TRANSMISSION_CONTAINER:9099"
        return 1
    fi
}

# Get container IPs
get_container_ips() {
    print_status "Container IP addresses:"
    
    for container in $TRANSMISSION_CONTAINER $PROMETHEUS_CONTAINER; do
        IP=$(docker inspect $container --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "N/A")
        print_status "  $container: $IP"
    done
}

# Fix networking issues
fix_networking() {
    print_action "Attempting to fix networking issues..."
    
    # Option 1: Connect containers to the same network
    print_action "Creating/using transmissionvpn_default network..."
    
    # Create network if it doesn't exist
    if ! docker network ls --format "{{.Name}}" | grep -q "transmissionvpn_default"; then
        print_action "Creating transmissionvpn_default network..."
        docker network create transmissionvpn_default
    fi
    
    # Connect containers to the network
    for container in $TRANSMISSION_CONTAINER $PROMETHEUS_CONTAINER; do
        if ! docker inspect $container --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | grep -q "transmissionvpn_default"; then
            print_action "Connecting $container to transmissionvpn_default network..."
            docker network connect transmissionvpn_default $container || print_warning "Failed to connect $container (may already be connected)"
        else
            print_status "$container already connected to transmissionvpn_default"
        fi
    done
}

# Update Prometheus configuration
update_prometheus_config() {
    print_action "Checking Prometheus configuration..."
    
    # Check current config
    if docker exec $PROMETHEUS_CONTAINER cat /etc/prometheus/prometheus.yml | grep -q "transmission:9099"; then
        print_status "✓ Prometheus config uses correct hostname: transmission:9099"
    elif docker exec $PROMETHEUS_CONTAINER cat /etc/prometheus/prometheus.yml | grep -q "localhost:9099"; then
        print_error "✗ Prometheus config uses localhost:9099 instead of transmission:9099"
        print_action "You need to update your prometheus.yml file:"
        echo "  Change: - targets: ['localhost:9099']"
        echo "  To:     - targets: ['transmission:9099']"
        echo "  Then restart Prometheus: docker restart $PROMETHEUS_CONTAINER"
    else
        print_warning "⚠ Could not determine Prometheus target configuration"
    fi
}

# Provide solutions
provide_solutions() {
    print_status "=== SOLUTION OPTIONS ==="
    echo
    
    print_action "Option 1: Use Docker Compose (Recommended)"
    echo "Create a docker-compose.yml that includes both services:"
    cat << 'EOF'
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmission
    # ... your existing config ...
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    # ... your existing config ...
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge
EOF
    echo
    
    print_action "Option 2: Connect to Existing Network"
    echo "If TransmissionVPN is already running, connect Prometheus to its network:"
    echo "  docker network connect \$(docker inspect transmission --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{\$k}}{{end}}' | awk '{print \$1}') prometheus"
    echo
    
    print_action "Option 3: Use Host Networking"
    echo "Run Prometheus with --network=host (less secure):"
    echo "  docker run --network=host prom/prometheus"
    echo "  Then use localhost:9099 in prometheus.yml"
    echo
    
    print_action "Option 4: Use Container IP Address"
    TRANSMISSION_IP=$(docker inspect $TRANSMISSION_CONTAINER --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "CONTAINER_IP")
    echo "Update prometheus.yml to use IP address instead of hostname:"
    echo "  - targets: ['$TRANSMISSION_IP:9099']"
    echo
}

# Test final connectivity
test_final_connectivity() {
    print_status "Testing connectivity after fixes..."
    
    if test_connectivity; then
        print_status "✅ SUCCESS: Containers can now communicate!"
        
        # Test metrics endpoint
        print_status "Testing metrics endpoint..."
        if docker exec $PROMETHEUS_CONTAINER wget -qO- --timeout=5 http://$TRANSMISSION_CONTAINER:9099/metrics | head -5; then
            print_status "✅ Metrics endpoint is working!"
        fi
        
        return 0
    else
        print_error "❌ Connectivity issues persist"
        return 1
    fi
}

# Restart services
restart_services() {
    print_action "Restarting services to apply network changes..."
    
    # Reload Prometheus config
    if docker exec $PROMETHEUS_CONTAINER wget -qO- --post-data='' http://localhost:9090/-/reload 2>/dev/null; then
        print_status "✓ Prometheus configuration reloaded"
    else
        print_action "Restarting Prometheus container..."
        docker restart $PROMETHEUS_CONTAINER
    fi
}

# Main execution
main() {
    echo "Starting network diagnostics and fixes..."
    echo
    
    # Check prerequisites
    if ! check_containers; then
        print_error "Required containers are not running. Please start them first."
        exit 1
    fi
    
    # Analyze current state
    get_container_ips
    echo
    
    if check_networks && test_connectivity; then
        print_status "✅ Networking appears to be working correctly!"
        print_status "The issue might be elsewhere. Check:"
        echo "  1. Is TRANSMISSION_EXPORTER_ENABLED=true?"
        echo "  2. Is port 9099 exposed in the container?"
        echo "  3. Is the metrics endpoint responding: curl http://localhost:9099/metrics"
        exit 0
    fi
    
    # Attempt fixes
    echo
    fix_networking
    echo
    update_prometheus_config
    echo
    restart_services
    echo
    
    # Test results
    if test_final_connectivity; then
        print_status "🎉 Network issues have been resolved!"
        print_status "Prometheus should now be able to scrape TransmissionVPN metrics."
    else
        print_error "❌ Automatic fixes didn't resolve the issue."
        provide_solutions
    fi
}

# Run main function
main "$@" 
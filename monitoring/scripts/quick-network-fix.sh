#!/bin/bash

# Quick fix for TransmissionVPN + Prometheus networking issue
# Run this on your rocky.gamull.com server

echo "=== Quick Network Fix for TransmissionVPN + Prometheus ==="

# Check if containers exist
if ! docker ps | grep -q "transmission"; then
    echo "ERROR: transmission container not found"
    exit 1
fi

if ! docker ps | grep -q "prometheus"; then
    echo "ERROR: prometheus container not found"
    exit 1
fi

echo "✓ Both containers are running"

# Get the network that transmission is on
TRANSMISSION_NETWORK=$(docker inspect transmission --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | awk '{print $1}')
echo "TransmissionVPN is on network: $TRANSMISSION_NETWORK"

# Connect prometheus to the same network
echo "Connecting prometheus to $TRANSMISSION_NETWORK network..."
docker network connect $TRANSMISSION_NETWORK prometheus 2>/dev/null || echo "Already connected or failed"

# Test connectivity
echo "Testing connectivity..."
if docker exec prometheus nslookup transmission >/dev/null 2>&1; then
    echo "✅ SUCCESS: Prometheus can now resolve 'transmission' hostname"
else
    echo "❌ FAILED: Still can't resolve hostname"
    echo "Trying alternative approach..."
    
    # Get transmission IP
    TRANSMISSION_IP=$(docker inspect transmission --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | awk '{print $1}')
    echo "TransmissionVPN IP: $TRANSMISSION_IP"
    
    echo "You need to update your prometheus.yml to use IP instead of hostname:"
    echo "Change: - targets: ['transmission:9099']"
    echo "To:     - targets: ['$TRANSMISSION_IP:9099']"
    exit 1
fi

# Test HTTP connectivity
if docker exec prometheus wget -q --spider --timeout=5 http://transmission:9099/metrics 2>/dev/null; then
    echo "✅ SUCCESS: HTTP connectivity working"
else
    echo "❌ FAILED: HTTP connectivity not working"
    echo "Check if TransmissionVPN metrics are enabled:"
    echo "  docker exec transmission printenv | grep TRANSMISSION_EXPORTER_ENABLED"
    exit 1
fi

# Reload Prometheus
echo "Reloading Prometheus configuration..."
docker exec prometheus wget -qO- --post-data='' http://localhost:9090/-/reload 2>/dev/null || docker restart prometheus

echo "🎉 Network fix complete! Check Prometheus targets in a few seconds." 
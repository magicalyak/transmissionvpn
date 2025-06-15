#!/bin/bash

# Transmission Service Troubleshooting Script
# This script helps diagnose issues with the systemctl transmission service

echo "=== Transmission Service Troubleshooting ==="
echo "Date: $(date)"
echo "Host: $(hostname)"
echo ""

# Check systemctl service status
echo "1. SYSTEMCTL SERVICE STATUS:"
echo "================================"
sudo systemctl status transmission --no-pager -l
echo ""

# Check if service is enabled
echo "2. SERVICE ENABLED STATUS:"
echo "=========================="
sudo systemctl is-enabled transmission
echo ""

# Check service logs
echo "3. RECENT SERVICE LOGS:"
echo "======================"
sudo journalctl -u transmission --no-pager -n 50
echo ""

# Check wrapper script
echo "4. WRAPPER SCRIPT CHECK:"
echo "======================="
if [ -f "/opt/containerd/start-transmission-wrapper.sh" ]; then
    echo "✅ Wrapper script exists"
    ls -la /opt/containerd/start-transmission-wrapper.sh
    echo ""
    echo "Wrapper script permissions:"
    stat /opt/containerd/start-transmission-wrapper.sh
    echo ""
    echo "First 20 lines of wrapper script:"
    head -20 /opt/containerd/start-transmission-wrapper.sh
else
    echo "❌ Wrapper script NOT FOUND at /opt/containerd/start-transmission-wrapper.sh"
fi
echo ""

# Check environment file
echo "5. ENVIRONMENT FILE CHECK:"
echo "========================="
if [ -f "/opt/containerd/env/transmission.env" ]; then
    echo "✅ Environment file exists"
    ls -la /opt/containerd/env/transmission.env
    echo ""
    echo "Environment file contents (sensitive values masked):"
    sed 's/\(PASSWORD\|TOKEN\|KEY\|SECRET\)=.*/\1=***MASKED***/g' /opt/containerd/env/transmission.env
else
    echo "❌ Environment file NOT FOUND at /opt/containerd/env/transmission.env"
fi
echo ""

# Check Docker status
echo "6. DOCKER STATUS:"
echo "================"
sudo systemctl status docker --no-pager -l | head -10
echo ""
echo "Docker containers:"
sudo docker ps -a | grep -i transmission || echo "No transmission containers found"
echo ""

# Check ports
echo "7. PORT STATUS:"
echo "=============="
echo "Checking if ports 9091 and 9099 are listening:"
sudo netstat -tlnp | grep -E ':(9091|9099)' || echo "Ports 9091/9099 not listening"
echo ""
sudo ss -tlnp | grep -E ':(9091|9099)' || echo "Ports 9091/9099 not listening (ss check)"
echo ""

# Check firewall
echo "8. FIREWALL STATUS:"
echo "=================="
if command -v ufw >/dev/null 2>&1; then
    echo "UFW Status:"
    sudo ufw status
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "Firewalld Status:"
    sudo firewall-cmd --list-all
else
    echo "No common firewall tools found (ufw/firewalld)"
fi
echo ""

# Check disk space
echo "9. DISK SPACE:"
echo "============="
df -h /opt/containerd/ 2>/dev/null || df -h /
echo ""

# Test local connectivity
echo "10. LOCAL CONNECTIVITY TEST:"
echo "============================"
echo "Testing localhost:9091 (Transmission Web UI):"
curl -I http://localhost:9091/transmission/web/ 2>&1 | head -5
echo ""
echo "Testing localhost:9099 (Metrics endpoint):"
curl -s http://localhost:9099/metrics 2>&1 | head -5
echo ""

# Check container logs if container exists
echo "11. CONTAINER LOGS:"
echo "=================="
CONTAINER_ID=$(sudo docker ps -q --filter "name=transmission" 2>/dev/null)
if [ -n "$CONTAINER_ID" ]; then
    echo "✅ Transmission container found: $CONTAINER_ID"
    echo "Recent container logs:"
    sudo docker logs --tail 30 $CONTAINER_ID
else
    echo "❌ No running transmission container found"
    echo "Checking stopped containers:"
    sudo docker ps -a --filter "name=transmission" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
fi
echo ""

echo "=== TROUBLESHOOTING COMPLETE ==="
echo ""
echo "NEXT STEPS:"
echo "1. If service is failed/inactive: sudo systemctl start transmission"
echo "2. If wrapper script has issues: check permissions and syntax"
echo "3. If environment file missing: create it with proper settings"
echo "4. If ports not listening: check Docker port mapping in wrapper script"
echo "5. If firewall blocking: open ports 9091 and 9099"
echo ""
echo "To restart the service: sudo systemctl restart transmission"
echo "To view live logs: sudo journalctl -u transmission -f" 
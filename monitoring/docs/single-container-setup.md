# Single Container Health Metrics Setup

For users who want VPN and container health metrics **without additional containers**.

## 🎯 **Simple Solution: Enable Built-in Health Metrics**

Your TransmissionVPN container already has health monitoring built-in - it just needs to be enabled!

### 1. **Update Your Environment Variables**

Add these to your `/opt/containerd/env/transmission.env`:

```bash
# Enable built-in health metrics (THIS IS THE KEY!)
METRICS_ENABLED=true

# Enable health monitoring features
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true
HEALTH_CHECK_HOST=8.8.8.8

# Transmission metrics (already enabled)
TRANSMISSION_EXPORTER_ENABLED=true
TRANSMISSION_EXPORTER_PORT=9099
```

### 2. **Restart Your Container**

```bash
# Stop the container
docker stop transmission

# Start it again with your wrapper script
/opt/containerd/start-transmission-wrapper.sh
```

### 3. **Verify Health Metrics Are Working**

```bash
# Check internal metrics file
docker exec transmission cat /tmp/metrics.txt | head -10

# Check health logs
docker exec transmission cat /tmp/healthcheck.log | tail -10

# Run health check manually
docker exec transmission /root/healthcheck.sh
```

## 📊 **What You'll Get**

### **Built-in Health Metrics** (from `/tmp/metrics.txt`):
- `transmissionvpn_overall_health_status` - Overall health (1=healthy, 0=unhealthy)
- `transmissionvpn_transmission_status` - Transmission web UI status
- `transmissionvpn_vpn_interface_status` - VPN interface status
- `transmissionvpn_vpn_connectivity_status` - VPN connectivity test
- `transmissionvpn_dns_resolution_status` - DNS resolution status
- `transmissionvpn_ip_leak_check_status` - IP leak detection
- `transmissionvpn_cpu_usage_percent` - CPU usage
- `transmissionvpn_memory_usage_percent` - Memory usage
- `transmissionvpn_disk_usage_percent_*` - Disk usage for various paths

### **Transmission Metrics** (from `:9099/metrics`):
- All the transmission stats we already have

## 🔧 **Expose Health Metrics via HTTP**

To make the internal health metrics available to Prometheus, we can create a simple script that serves them:

### Option A: Simple Python Server (Recommended)

Create `/opt/scripts/health-metrics-bridge.py`:

```python
#!/usr/bin/env python3
"""
Simple bridge to expose TransmissionVPN internal health metrics via HTTP
"""
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            try:
                # Read internal metrics file
                with open('/tmp/metrics.txt', 'r') as f:
                    metrics = f.read()
                
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(metrics.encode())
            except:
                self.send_response(503)
                self.end_headers()
                self.wfile.write(b'# Health metrics not available\n')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), HealthHandler)
    print("Health metrics bridge running on port 8080")
    server.serve_forever()
```

### Option B: Simple Shell Script

Create `/opt/scripts/serve-health-metrics.sh`:

```bash
#!/bin/bash
# Simple HTTP server for health metrics

PORT=8080
echo "Starting health metrics server on port $PORT"

while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$(cat /tmp/metrics.txt 2>/dev/null || echo '# No metrics available')" | nc -l -p $PORT -q 1
done
```

## 🚀 **Single Container + External Prometheus**

### 1. **Run Your TransmissionVPN Container** (with health metrics enabled)

```bash
# Your existing setup with added environment variables
/opt/containerd/start-transmission-wrapper.sh
```

### 2. **Run Prometheus Separately** (if desired)

```bash
# Create prometheus.yml
cat > /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['localhost:9099']  # Transmission metrics
    scrape_interval: 15s

  - job_name: 'transmissionvpn-health'
    static_configs:
      - targets: ['localhost:8080']  # Health metrics (if using bridge)
    scrape_interval: 30s
EOF

# Run Prometheus
docker run -d \
  --name prometheus \
  --network host \
  -v /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:latest
```

## 🎯 **Minimal Setup (No Additional Containers)**

If you just want to see the health status without Prometheus:

```bash
# Enable health metrics in your container
# Add METRICS_ENABLED=true to transmission.env
# Restart container

# Check health status
docker exec transmission /root/healthcheck.sh

# View metrics
docker exec transmission cat /tmp/metrics.txt

# Monitor continuously
watch 'docker exec transmission cat /tmp/metrics.txt | grep -E "(status|health)"'
```

## 📋 **Summary**

**Simplest approach:**
1. Add `METRICS_ENABLED=true` to your transmission.env
2. Restart your container
3. Health metrics are now collected internally
4. Access via `docker exec transmission cat /tmp/metrics.txt`

**For Prometheus integration:**
1. Enable health metrics (above)
2. Optionally add a simple bridge script to expose metrics via HTTP
3. Configure Prometheus to scrape both endpoints

**No additional containers required!** ✅ 
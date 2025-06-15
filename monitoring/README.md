# TransmissionVPN Monitoring

**Complete monitoring solutions for TransmissionVPN with health checks, metrics, and beautiful dashboards.**

## 🎯 **Quick Start**

### **Option 1: Simple Setup (Recommended for most users)**
```bash
# Enable built-in metrics in your container
echo "METRICS_ENABLED=true" >> /path/to/your/transmission.env
docker restart transmission

# Access metrics
curl http://localhost:9099/metrics
curl http://localhost:9099/health
```

### **Option 2: Use with Existing Prometheus/Grafana**
```bash
# Enable metrics in your TransmissionVPN container
echo "METRICS_ENABLED=true" >> /path/to/your/transmission.env
docker restart transmission

# Add to your existing prometheus.yml
cat >> /path/to/your/prometheus.yml << 'EOF'
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['transmission:9099']  # or 'your-server-ip:9099'
    scrape_interval: 30s
    metrics_path: /metrics
EOF

# Restart Prometheus to load new config
docker restart prometheus  # or systemctl reload prometheus
```

### **Option 3: Advanced Monitoring Stack**
```bash
# Clone and start InfluxDB2 stack
cd monitoring/influxdb2
docker-compose up -d

# Access dashboards
open http://localhost:3001  # Grafana (admin/transmissionvpn123)
open http://localhost:8086  # InfluxDB2 (admin/transmissionvpn123)
```

## 📊 **Monitoring Options Comparison**

| Feature | Built-in Metrics | Existing Prometheus | InfluxDB2 Stack |
|---------|------------------|---------------------|-----------------|
| **Complexity** | ⭐ Simple | ⭐⭐ Easy | ⭐⭐⭐ Advanced |
| **Resource Usage** | Minimal | Minimal | Moderate |
| **Setup Time** | 1 minute | 2 minutes | 10 minutes |
| **Data Retention** | Session only | Your config | 365 days |
| **Query Language** | None | PromQL | Flux |
| **Dashboards** | None | Your existing | Beautiful |
| **Alerting** | None | Your existing | Advanced |
| **Integration** | Standalone | Seamless | New stack |
| **Best For** | Quick health checks | Existing infrastructure | New deployments |

## 🏗️ **Architecture Overview**

### **Built-in Metrics (Single Container)**
```
┌─────────────────────────┐
│   TransmissionVPN       │
│  ┌─────────────────────┐│
│  │ Transmission Daemon ││
│  └─────────────────────┘│
│  ┌─────────────────────┐│
│  │ Metrics Server      ││  :9099/metrics
│  │ (Python)            ││  :9099/health
│  └─────────────────────┘│
└─────────────────────────┘
```

### **InfluxDB2 Stack (Advanced)**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ TransmissionVPN │    │    Telegraf     │    │    InfluxDB2    │
│                 │───▶│   (Collector)   │───▶│   (Database)    │
│ :9099/metrics   │    │                 │    │   :8086         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                       ┌─────────────────┐             │
                       │     Grafana     │◀────────────┘
                       │  (Dashboards)   │
                       │     :3001       │
                       └─────────────────┘
```

## 🚀 **Setup Guides**

### **Built-in Metrics Setup**

1. **Enable metrics in your container:**
   ```bash
   # Add to your environment file
   METRICS_ENABLED=true
   METRICS_PORT=9099
   METRICS_INTERVAL=30
   ```

2. **Restart container:**
   ```bash
   docker restart transmission
   ```

3. **Verify metrics:**
   ```bash
   curl http://localhost:9099/metrics
   curl http://localhost:9099/health
   ```

### **InfluxDB2 Stack Setup**

1. **Navigate to monitoring directory:**
   ```bash
   cd monitoring/influxdb2
   ```

2. **Start the stack:**
   ```bash
   docker-compose up -d
   ```

3. **Access services:**
   - **Grafana**: http://localhost:3001 (admin/transmissionvpn123)
   - **InfluxDB2**: http://localhost:8086 (admin/transmissionvpn123)
   - **Chronograf**: http://localhost:8888

4. **View dashboards:**
   - TransmissionVPN Overview
   - TransmissionVPN Analytics

## 🔗 **Integration with Existing Prometheus/Grafana**

### **Prerequisites**
- Existing Prometheus server
- Existing Grafana instance
- Network connectivity between Prometheus and TransmissionVPN container

### **Step 1: Enable TransmissionVPN Metrics**

Add to your TransmissionVPN environment file:
```bash
# Enable built-in metrics server
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30

# Optional: Health check configuration
HEALTH_CHECK_TIMEOUT=10
EXTERNAL_IP_SERVICE=ifconfig.me
```

Restart your TransmissionVPN container:
```bash
docker restart transmission
```

### **Step 2: Configure Prometheus Scraping**

#### **Option A: Same Docker Network**
If Prometheus and TransmissionVPN are on the same Docker network:
```yaml
# Add to your prometheus.yml
scrape_configs:
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['transmission:9099']
    scrape_interval: 30s
    scrape_timeout: 10s
    metrics_path: /metrics
    honor_labels: true
```

#### **Option B: Different Networks/Hosts**
If running on different networks or hosts:
```yaml
# Add to your prometheus.yml
scrape_configs:
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['your-server-ip:9099']  # Replace with actual IP
    scrape_interval: 30s
    scrape_timeout: 10s
    metrics_path: /metrics
    honor_labels: true
```

#### **Option C: Docker Compose Integration**
If using Docker Compose, add TransmissionVPN to your monitoring stack:
```yaml
version: '3.8'
services:
  transmission:
    image: magicalyak/transmissionvpn:latest
    container_name: transmission
    # ... your existing config ...
    networks:
      - monitoring  # Add to monitoring network
    
  prometheus:
    # ... your existing prometheus config ...
    networks:
      - monitoring

networks:
  monitoring:
    external: true  # or create new network
```

### **Step 3: Reload Prometheus Configuration**

```bash
# Method 1: API reload (if enabled)
curl -X POST http://localhost:9090/-/reload

# Method 2: Container restart
docker restart prometheus

# Method 3: Service restart (if using systemd)
sudo systemctl reload prometheus
```

### **Step 4: Verify Metrics Collection**

1. **Check Prometheus targets:**
   - Open http://your-prometheus:9090/targets
   - Look for `transmissionvpn` job
   - Status should be "UP"

2. **Test metrics query:**
   ```promql
   # Check if metrics are being collected
   up{job="transmissionvpn"}
   
   # View transmission metrics
   transmission_session_stats_download_speed_bytes
   transmissionvpn_vpn_interface_status
   ```

### **Step 5: Import Grafana Dashboard**

#### **Option A: Use Pre-built Dashboard**
1. Download dashboard JSON from `monitoring/docker-compose/grafana/dashboards/`
2. In Grafana: **+** → **Import** → **Upload JSON file**
3. Select your Prometheus data source
4. Click **Import**

#### **Option B: Create Custom Dashboard**
Essential panels to include:
```promql
# System Health Status
transmissionvpn_transmission_status

# Transfer Speeds
rate(transmission_session_stats_downloaded_bytes[5m]) * 8  # Download speed in bits/sec
rate(transmission_session_stats_uploaded_bytes[5m]) * 8    # Upload speed in bits/sec

# Active Torrents
transmission_session_stats_torrents_active

# VPN Status
transmissionvpn_vpn_interface_status

# System Resources
transmissionvpn_memory_usage_percent
transmissionvpn_disk_usage_percent
```

### **Step 6: Set Up Alerting (Optional)**

Example Prometheus alerting rules:
```yaml
# alerts.yml
groups:
  - name: transmissionvpn
    rules:
      - alert: TransmissionDown
        expr: transmissionvpn_transmission_status == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Transmission daemon is down"
          description: "TransmissionVPN container transmission daemon has been down for more than 2 minutes"

      - alert: VPNDisconnected
        expr: transmissionvpn_vpn_interface_status == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "VPN connection lost"
          description: "TransmissionVPN VPN interface has been down for more than 5 minutes"

      - alert: HighDiskUsage
        expr: transmissionvpn_disk_usage_percent > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High disk usage in TransmissionVPN"
          description: "Disk usage is {{ $value }}% in TransmissionVPN downloads directory"
```

### **Troubleshooting Integration**

#### **Metrics not appearing in Prometheus**
```bash
# Check if metrics endpoint is accessible
curl http://your-server:9099/metrics

# Check Prometheus logs
docker logs prometheus | grep transmissionvpn

# Verify network connectivity
docker exec prometheus nslookup transmission  # if same network
```

#### **Dashboard shows no data**
```bash
# Verify data source configuration in Grafana
# Check time range (metrics are recent)
# Confirm metric names match (they may have changed)

# Test query in Prometheus first
curl 'http://localhost:9090/api/v1/query?query=up{job="transmissionvpn"}'
```

#### **Connection refused errors**
```bash
# Check if metrics are enabled
docker exec transmission printenv | grep METRICS

# Check if port is accessible
docker exec transmission netstat -tlnp | grep 9099

# Check firewall rules (if applicable)
sudo ufw status | grep 9099
```

## 📈 **Available Metrics**

### **Health Endpoint (`/health`)**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "system": {
    "hostname": "transmission-container",
    "platform": "Linux 5.4.0",
    "uptime": 86400,
    "load_average": [0.5, 0.3, 0.2],
    "memory": {
      "total": 8589934592,
      "available": 4294967296,
      "used": 4294967296,
      "percent": 50.0
    }
  },
  "vpn": {
    "interface": "tun0",
    "status": "connected",
    "local_ip": "10.8.0.2",
    "external_ip": "203.0.113.1",
    "dns_servers": ["10.8.0.1"]
  },
  "transmission": {
    "web_ui_accessible": true,
    "daemon_accessible": true,
    "version": "3.00",
    "active_torrents": 5,
    "download_speed": 1048576,
    "upload_speed": 524288
  }
}
```

### **Prometheus Metrics (`/metrics`)**
```
# System metrics
transmissionvpn_system_uptime_seconds 86400
transmissionvpn_system_load_average 0.5
transmissionvpn_memory_usage_percent 50.0
transmissionvpn_disk_usage_percent 75.0

# VPN metrics
transmissionvpn_vpn_interface_status 1
transmissionvpn_vpn_bytes_sent 1073741824
transmissionvpn_vpn_bytes_received 2147483648

# Transmission metrics
transmissionvpn_transmission_status 1
transmissionvpn_active_torrents 5
transmissionvpn_download_speed_bytes 1048576
transmissionvpn_upload_speed_bytes 524288
transmissionvpn_session_downloaded_bytes 10737418240
transmissionvpn_session_uploaded_bytes 5368709120
```

## 🎨 **Dashboard Features**

### **Overview Dashboard**
- **System Health**: Real-time status indicators with color coding
- **Transfer Speeds**: Live download/upload speeds with smooth animations
- **Torrent Activity**: Active torrents breakdown and status distribution
- **Resource Usage**: CPU, memory, and disk utilization gauges
- **VPN Monitoring**: Connection status and IP leak detection
- **Network Performance**: Latency, packet loss, and throughput metrics

### **Analytics Dashboard**
- **Historical Trends**: Long-term transfer patterns and usage analytics
- **Performance Analysis**: System resource trends over time
- **Network Analysis**: VPN performance and connectivity patterns
- **Error Tracking**: Failed connections, timeouts, and issues
- **Capacity Planning**: Storage usage trends and predictions

## 🔧 **Configuration**

### **Environment Variables**

| Variable | Default | Description |
|----------|---------|-------------|
| `METRICS_ENABLED` | `false` | Enable built-in metrics server |
| `METRICS_PORT` | `9099` | Port for metrics server |
| `METRICS_INTERVAL` | `30` | Metrics collection interval (seconds) |
| `HEALTH_CHECK_TIMEOUT` | `10` | Health check timeout (seconds) |
| `EXTERNAL_IP_SERVICE` | `ifconfig.me` | Service for external IP detection |
| `VPN_INTERFACE_NAME` | `tun0` | VPN interface name to monitor |

### **InfluxDB2 Configuration**

| Setting | Value | Description |
|---------|-------|-------------|
| **Organization** | `transmissionvpn` | InfluxDB organization |
| **Bucket** | `metrics` | Data storage bucket |
| **Retention** | `365d` | Data retention period |
| **Username** | `admin` | Default admin username |
| **Password** | `transmissionvpn123` | Default admin password |

## 🚨 **Troubleshooting**

### **Common Issues**

#### **Metrics not available**
```bash
# Check if metrics are enabled
docker exec transmission printenv | grep METRICS

# Check if metrics server is running
docker exec transmission netstat -tlnp | grep 9099

# Check logs
docker logs transmission | grep metrics
```

#### **Health check fails**
```bash
# Test health endpoint
curl -v http://localhost:9099/health

# Check container health
docker inspect transmission --format='{{.State.Health.Status}}'

# View health logs
docker inspect transmission --format='{{range .State.Health.Log}}{{.Output}}{{end}}'
```

#### **VPN metrics missing**
```bash
# Check VPN interface
docker exec transmission ip addr show tun0

# Test VPN connectivity
docker exec transmission curl -s ifconfig.me

# Check VPN logs
docker logs transmission | grep -i vpn
```

### **Performance Tuning**

#### **Reduce metrics collection frequency**
```bash
# Increase interval to reduce CPU usage
METRICS_INTERVAL=60  # Collect every minute instead of 30 seconds
```

#### **Optimize InfluxDB2 retention**
```bash
# Reduce retention for lower disk usage
# Edit monitoring/influxdb2/docker-compose.yml
# Change: --store-retention-policy-default-duration=365d
# To:     --store-retention-policy-default-duration=30d
```

## 📚 **Additional Documentation**

- **[Single Container Guide](docs/single-container-guide.md)** - Minimal setup without Docker Compose
- **[InfluxDB2 Setup](influxdb2/README.md)** - Detailed InfluxDB2 stack documentation
- **[Health Fix Guide](docs/PERMANENT_HEALTH_FIX.md)** - Fixing container health issues
- **[VPN Fix Guide](docs/VPN_FIX_GUIDE.md)** - VPN connectivity troubleshooting

## 🤝 **Support**

- **Issues**: Report bugs and feature requests on GitHub
- **Discussions**: Join community discussions for help and tips
- **Documentation**: Check the docs directory for detailed guides
- **Examples**: See EXAMPLES.md for configuration examples

---

**Choose your monitoring approach based on your needs:**
- **Just want health checks?** → Use built-in metrics
- **Have existing Prometheus/Grafana?** → Use integration guide above
- **Want a complete new stack?** → Use InfluxDB2 stack
- **Need advanced analytics?** → Use InfluxDB2 with Flux queries 
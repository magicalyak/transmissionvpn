# Monitoring Setup for TransmissionVPN

## 🎯 **Overview**

This directory contains monitoring configurations for TransmissionVPN using the **built-in custom metrics server** (v4.0.6-r11+).

### **✅ What's Included:**
- **Prometheus + Grafana** setup with Docker Compose
- **InfluxDB v2** integration for time-series data
- **Pre-configured dashboards** for Transmission metrics
- **Automated setup scripts** for quick deployment

---

## **🚀 Quick Start**

### **1. Enable Built-in Metrics**

Add to your `.env` file:
```bash
# Custom Metrics Server (v4.0.6-r11+)
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
```

### **2. Restart TransmissionVPN**
```bash
docker-compose restart transmissionvpn
```

### **3. Verify Metrics**
```bash
curl http://localhost:9099/metrics
curl http://localhost:9099/health
```

### **4. Deploy Monitoring Stack**
```bash
# Option A: Prometheus + Grafana
cd monitoring/docker-compose
docker-compose up -d

# Option B: InfluxDB v2 + Grafana  
cd monitoring/grafana-influx
docker-compose up -d
```

---

## **📊 Available Metrics**

The custom metrics server provides these Prometheus metrics:

### **Torrent Counts**
- `transmission_torrent_count` - Total number of torrents
- `transmission_active_torrents` - Number of active torrents
- `transmission_downloading_torrents` - Number of downloading torrents
- `transmission_seeding_torrents` - Number of seeding torrents

### **Transfer Rates**
- `transmission_download_rate_bytes_per_second` - Current download rate
- `transmission_upload_rate_bytes_per_second` - Current upload rate

### **Session Statistics**
- `transmission_session_downloaded_bytes` - Session downloaded bytes
- `transmission_session_uploaded_bytes` - Session uploaded bytes

### **System**
- `transmission_metrics_last_update_timestamp` - Last metrics update time

---

## **🔧 Configuration Options**

### **Environment Variables**
```bash
# Required
METRICS_ENABLED=true           # Enable custom metrics server
METRICS_PORT=9099             # Metrics endpoint port
METRICS_INTERVAL=30           # Update interval in seconds

# Optional
TRANSMISSION_RPC_USERNAME=admin
TRANSMISSION_RPC_PASSWORD=your_password
```

### **Prometheus Scrape Config**
```yaml
scrape_configs:
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['transmissionvpn:9099']
    scrape_interval: 30s
    metrics_path: /metrics
```

---

## **🏗️ Deployment Options**

### **Option 1: Prometheus + Grafana (Recommended)**
- **Location**: `monitoring/docker-compose/`
- **Services**: Prometheus, Grafana, AlertManager
- **Best for**: Production monitoring with alerting

### **Option 2: InfluxDB v2 + Grafana**
- **Location**: `monitoring/grafana-influx/`
- **Services**: InfluxDB v2, Grafana, Telegraf
- **Best for**: Time-series analysis and long-term storage

### **Option 3: External Monitoring**
- **Use case**: Existing Prometheus/Grafana setup
- **Setup**: Add scrape target to existing Prometheus config

---

## **🚨 Troubleshooting**

### **Metrics Not Available**
1. **Missing env vars**: Add `METRICS_ENABLED=true` to your `.env` file
2. **Container not updated**: Pull latest image `magicalyak/transmissionvpn:v4.0.6-r11`
3. **Port not exposed**: Ensure port 9099 is mapped in docker-compose.yml
4. **Firewall**: Check if port 9099 is accessible

### **Migration from transmission-exporter**
If upgrading from older versions:
```bash
# Old variables (remove these)
TRANSMISSION_EXPORTER_ENABLED=true  # Remove
TRANSMISSION_EXPORTER_PORT=9099     # Remove

# New variables (add these)
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
```

---

## **📈 Dashboard Examples**

### **Key Metrics to Monitor**
- **Active Torrents**: Track downloading/seeding activity
- **Transfer Rates**: Monitor bandwidth usage
- **Session Statistics**: Track total data transferred
- **System Health**: Monitor container and VPN status

### **Grafana Queries**
```promql
# Active torrents
transmission_active_torrents

# Download rate in MB/s
rate(transmission_session_downloaded_bytes[5m]) / 1024 / 1024

# Upload rate in MB/s  
rate(transmission_session_uploaded_bytes[5m]) / 1024 / 1024

# Total torrents by status
sum by (status) (transmission_torrent_count)
```

---

## **🔗 Related Documentation**

- **[Main README](../README.md)** - TransmissionVPN setup
- **[Release Notes](../RELEASE_NOTES_v4.0.6-r11.md)** - Custom metrics details
- **[Configuration Guide](../docs/ROCKY_SERVER_UPGRADE_GUIDE.md)** - Server upgrade guide

---

## **💡 Tips**

1. **Start simple**: Use built-in metrics first, add external monitoring later
2. **Monitor trends**: Focus on long-term patterns, not instant values
3. **Set alerts**: Configure alerts for VPN disconnections or failed downloads
4. **Regular cleanup**: Archive old metrics data to save storage space

The custom metrics server provides reliable, lightweight monitoring without the complexity of external exporters! 🚀 
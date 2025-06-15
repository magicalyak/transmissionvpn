# Release Notes - v4.0.6-r13

## 🚀 Enhanced Health Monitoring Release

This release significantly improves the health monitoring capabilities with a comprehensive health endpoint similar to nzbgetvpn's approach.

### ✨ New Features

**Enhanced Health Endpoint (`/health`)**
- **Comprehensive JSON Response**: Returns detailed system, VPN, and Transmission status
- **System Information**: Hostname, uptime, load average, memory usage, disk space
- **VPN Status**: Interface detection, IP addresses, external IP verification
- **Transmission Health**: Daemon status, web UI accessibility, RPC connectivity, response times
- **Status Levels**: `healthy`, `degraded`, `unhealthy`, `error` with issue tracking

**Additional Health Endpoints**
- **`/health/simple`**: Basic OK/Service Unavailable response for simple monitoring
- **`/health`**: Full JSON status (existing endpoint enhanced)

### 📊 **Monitoring Improvements**

**Updated Grafana Dashboard**
- **Status Overview**: Visual indicators for container, VPN, and web UI status
- **Better Layout**: Reorganized panels for improved readability
- **New Metrics**: Disk usage gauge, enhanced torrent activity tracking
- **Color Coding**: Red/green status indicators for quick health assessment

**Prometheus Configuration**
- **Simplified Setup**: Updated for single-container architecture
- **Better Targeting**: Cleaner scraping configuration
- **Health Scraping**: Separate job for health endpoint monitoring

### 🔍 **Health Response Example**

```json
{
  "timestamp": 1703123456,
  "status": "healthy",
  "version": "4.0.6-r13",
  "system": {
    "hostname": "transmission-container",
    "uptime_seconds": 86400,
    "load_average": [0.1, 0.2, 0.3],
    "memory": {
      "MemTotal": 8589934592,
      "MemAvailable": 4294967296
    },
    "disk": {
      "total_bytes": 1000000000000,
      "available_bytes": 500000000000,
      "usage_percent": 50
    }
  },
  "vpn": {
    "interface": "tun0",
    "status": "up",
    "ip_address": "10.8.0.2",
    "external_ip": "203.0.113.1",
    "connected": true
  },
  "transmission": {
    "web_ui_accessible": true,
    "rpc_accessible": true,
    "daemon_running": true,
    "response_time_ms": 45
  },
  "metrics": {
    "torrents": 5,
    "active_torrents": 2,
    "download_rate": 1048576,
    "upload_rate": 524288
  }
}
```

### 🛠️ **Technical Improvements**

**Metrics Server Enhancements**
- **System Monitoring**: Added comprehensive system information collection
- **VPN Detection**: Automatic detection of tun0/wg0 interfaces
- **External IP Checking**: Verification of VPN functionality
- **Error Handling**: Improved error handling and fallback responses

**Documentation Updates**
- **Monitoring Guide**: Updated with new endpoint examples
- **Dashboard Instructions**: Clear setup and customization guide
- **Troubleshooting**: Enhanced troubleshooting section

### 🔧 **Usage**

**Test the new endpoints:**
```bash
# Enhanced health data (JSON)
curl http://your-server:9099/health

# Simple health check (text)
curl http://your-server:9099/health/simple

# Prometheus metrics (unchanged)
curl http://your-server:9099/metrics
```

**Monitor with external tools:**
- **Uptime Kuma**: Use `/health/simple` endpoint
- **Nagios/Zabbix**: Parse JSON from `/health` endpoint
- **Custom Scripts**: Leverage detailed status information

### 🎯 **Benefits**

1. **Better Monitoring**: More detailed health information for troubleshooting
2. **nzbgetvpn Compatibility**: Similar health endpoint format for consistency
3. **Flexible Integration**: Multiple endpoint formats for different monitoring tools
4. **Visual Dashboards**: Improved Grafana dashboard with status indicators
5. **Proactive Alerts**: Better data for setting up monitoring alerts

### 📈 **Monitoring Stack**

The included monitoring stack (`monitoring/docker-compose/`) now provides:
- **Real-time Dashboards**: Visual status indicators and metrics
- **Historical Data**: Prometheus storage with 1-year retention
- **Alert Capabilities**: Foundation for custom alerting rules
- **Easy Setup**: Single command deployment

### 🔄 **Upgrade Notes**

- **Backward Compatible**: Existing `/metrics` endpoint unchanged
- **New Endpoints**: `/health` and `/health/simple` are new additions
- **Dashboard Update**: Import new dashboard for enhanced visuals
- **No Breaking Changes**: All existing functionality preserved

This release makes TransmissionVPN monitoring significantly more comprehensive and user-friendly, bringing it in line with modern container monitoring practices. 
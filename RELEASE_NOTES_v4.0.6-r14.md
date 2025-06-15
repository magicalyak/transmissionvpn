# Release Notes - v4.0.6-r14

## 🚀 **Major Features**

### InfluxDB2 Monitoring Stack
- **Complete InfluxDB2 integration** with Telegraf and Grafana
- **Advanced time-series analytics** with Flux query language
- **Comprehensive system monitoring** including CPU, memory, disk, network
- **Beautiful pre-built dashboards** with modern visualizations
- **365-day data retention** by default for long-term analysis

### Enhanced Health Endpoint
- **Comprehensive system information** including platform details, CPU info, network interfaces
- **Advanced VPN monitoring** with interface statistics, DNS servers, packet counters
- **Detailed Transmission status** including version, port test, protocol settings
- **Container information** with environment variables and configuration
- **Session statistics** for current and cumulative transfer data

### Monitoring Stack Comparison
- **Dual monitoring options**: Prometheus + Grafana (simple) and InfluxDB2 + Telegraf + Grafana (advanced)
- **Performance optimized** configurations for different use cases
- **Comprehensive documentation** with setup guides and troubleshooting

## 📊 **Enhanced Health Endpoint Response**

The `/health` endpoint now returns comprehensive status information similar to nzbgetvpn:

```json
{
  "timestamp": 1703123456,
  "iso_timestamp": "2023-12-21T10:17:36+00:00",
  "status": "healthy",
  "version": "4.0.6-r14",
  "service": "transmissionvpn",
  "uptime_seconds": 86400,
  "system": {
    "hostname": "transmission-container",
    "platform": {
      "system": "Linux",
      "release": "5.15.0",
      "version": "#1 SMP",
      "machine": "x86_64",
      "processor": "x86_64"
    },
    "uptime_seconds": 86400,
    "boot_time": 1703037036,
    "load_average": [0.1, 0.2, 0.3],
    "memory": {
      "total": 8589934592,
      "available": 4294967296,
      "used": 4294967296,
      "free": 2147483648,
      "percent": 50.0,
      "buffers": 134217728,
      "cached": 1073741824
    },
    "swap": {
      "total": 2147483648,
      "used": 0,
      "free": 2147483648,
      "percent": 0.0
    },
    "disk": {
      "total_bytes": 1000000000000,
      "used_bytes": 500000000000,
      "available_bytes": 500000000000,
      "usage_percent": 50.0
    },
    "cpu": {
      "count": 4,
      "usage_percent": 15.2,
      "frequency": {
        "current": 2400.0,
        "min": 800.0,
        "max": 3200.0
      }
    },
    "network_interfaces": {
      "eth0": {
        "ip": "172.17.0.2",
        "netmask": "255.255.0.0"
      },
      "tun0": {
        "ip": "10.8.0.2",
        "netmask": "255.255.255.0"
      }
    }
  },
  "vpn": {
    "interface": "tun0",
    "status": "up",
    "ip_address": "10.8.0.2",
    "external_ip": "203.0.113.1",
    "connected": true,
    "dns_servers": ["8.8.8.8", "1.1.1.1"],
    "stats": {
      "bytes_sent": 1048576000,
      "bytes_recv": 2097152000,
      "packets_sent": 1000000,
      "packets_recv": 1500000,
      "errin": 0,
      "errout": 0,
      "dropin": 0,
      "dropout": 0
    }
  },
  "transmission": {
    "web_ui_accessible": true,
    "rpc_accessible": true,
    "daemon_running": true,
    "response_time_ms": 45,
    "version": "3.00",
    "session_id": "abc123def456",
    "port_test": true,
    "blocklist_enabled": true,
    "blocklist_size": 500000,
    "queue_enabled": false,
    "speed_limit_enabled": false,
    "alt_speed_enabled": false,
    "encryption": "preferred",
    "peer_port": 51413,
    "peer_port_random": false,
    "dht_enabled": true,
    "lpd_enabled": true,
    "pex_enabled": true,
    "utp_enabled": true
  },
  "container": {
    "id": "transmission-container",
    "name": "transmission-container",
    "environment": {
      "TRANSMISSION_RPC_USERNAME": "admin",
      "TRANSMISSION_RPC_PASSWORD": "***REDACTED***",
      "VPN_CLIENT": "openvpn",
      "METRICS_ENABLED": "true",
      "METRICS_PORT": "9099"
    }
  },
  "metrics": {
    "torrents": 5,
    "active_torrents": 2,
    "downloading_torrents": 1,
    "seeding_torrents": 1,
    "paused_torrents": 3,
    "download_rate": 1048576,
    "upload_rate": 524288,
    "total_size": 10737418240,
    "total_downloaded": 5368709120,
    "total_uploaded": 2684354560,
    "last_update": 1703123450,
    "update_interval": 30
  },
  "session": {
    "current": {
      "downloaded_bytes": 1073741824,
      "uploaded_bytes": 536870912,
      "files_added": 5,
      "session_count": 1,
      "seconds_active": 3600
    },
    "cumulative": {
      "downloaded_bytes": 107374182400,
      "uploaded_bytes": 53687091200,
      "files_added": 500,
      "session_count": 100,
      "seconds_active": 360000
    }
  },
  "endpoints": {
    "metrics": "http://localhost:9099/metrics",
    "health": "http://localhost:9099/health",
    "health_simple": "http://localhost:9099/health/simple"
  }
}
```

## 🐳 **InfluxDB2 Monitoring Stack**

### Quick Start
```bash
cd monitoring/influxdb2
docker-compose up -d
```

**Access Points:**
- **Grafana**: http://localhost:3001 (admin/admin)
- **InfluxDB2**: http://localhost:8086 (admin/transmissionvpn123)
- **Chronograf**: http://localhost:8888

### Features
- **Comprehensive Metrics Collection**: System, VPN, Transmission, Docker, and network metrics
- **Advanced Analytics**: Detailed performance analysis with Flux queries
- **Beautiful Dashboards**: Two pre-built dashboards with modern visualizations
- **Long-term Storage**: 365-day retention for historical analysis
- **Real-time Monitoring**: 30-second collection intervals with live updates

### Dashboards

#### 1. TransmissionVPN Overview
- System health status indicators
- Real-time transfer speeds with smooth animations
- Torrent activity breakdown
- Resource utilization gauges
- VPN connection monitoring
- Network performance metrics

#### 2. Detailed Analytics
- Torrent status distribution (pie chart)
- Memory usage breakdown with stacked areas
- Container resource analysis
- Disk I/O operations monitoring
- DNS performance tracking
- Network error and packet loss analysis

## 🔧 **Technical Improvements**

### Enhanced Metrics Server
- **Added psutil dependency** for comprehensive system monitoring
- **Platform information** collection including OS details
- **Network interface detection** with automatic VPN interface identification
- **CPU frequency monitoring** with current, min, max values
- **Memory breakdown** including buffers and cached memory
- **Swap usage monitoring** for complete memory analysis

### Monitoring Infrastructure
- **Telegraf configuration** with comprehensive input plugins
- **Flux query optimization** for efficient data processing
- **Grafana provisioning** with automatic dashboard deployment
- **Network connectivity testing** with ping and DNS monitoring
- **Docker metrics collection** for container resource tracking

### Documentation Updates
- **Comprehensive monitoring guide** with stack comparison
- **InfluxDB2 setup documentation** with detailed configuration
- **Troubleshooting guides** for both monitoring stacks
- **Performance optimization** recommendations
- **Advanced usage examples** with custom queries

## 📈 **Monitoring Stack Comparison**

| Feature | Prometheus + Grafana | InfluxDB2 + Telegraf + Grafana |
|---------|---------------------|--------------------------------|
| **Setup Complexity** | Simple | Moderate |
| **Resource Usage** | Low | Medium |
| **Data Retention** | Configurable | 365 days default |
| **Query Language** | PromQL | Flux |
| **System Metrics** | Basic | Comprehensive |
| **Alerting** | Built-in | Advanced |
| **Scalability** | Good | Excellent |
| **Learning Curve** | Easy | Moderate |

## 🚨 **Enhanced Status Monitoring**

### Status Levels
- **healthy**: All systems operational
- **degraded**: Some issues but Transmission is running (warnings present)
- **unhealthy**: Critical issues, Transmission down
- **error**: Unable to determine status

### Issue Detection
- **Critical Issues** (status: unhealthy):
  - `transmission_daemon_down` - Transmission daemon not running
  - `web_ui_inaccessible` - Web UI not responding
  - `rpc_inaccessible` - RPC interface not accessible

- **Warnings** (status: degraded):
  - `vpn_disconnected` - VPN not connected
  - `disk_space_low` - Disk usage > 90%
  - `memory_usage_high` - Memory usage > 90%
  - `port_not_open` - Peer port not accessible

## 🔄 **Migration Guide**

### From Previous Versions
1. **Update container** to v4.0.6-r14
2. **Choose monitoring stack**:
   - Simple: Use existing Prometheus setup
   - Advanced: Deploy InfluxDB2 stack
3. **Update configuration** if needed
4. **Test endpoints** to verify functionality

### Environment Variables
No breaking changes to existing environment variables. New optional variables:
- `HEALTH_CHECK_TIMEOUT=10` - Health check timeout in seconds
- `EXTERNAL_IP_SERVICE=ifconfig.me` - Service for external IP detection

## 🛠 **Configuration Examples**

### Basic Setup
```env
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
```

### Advanced Setup with InfluxDB2
```env
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
HEALTH_CHECK_TIMEOUT=10
EXTERNAL_IP_SERVICE=ifconfig.me
```

### Monitoring Stack Selection
```bash
# Option 1: Prometheus + Grafana (Simple)
cd monitoring/docker-compose
docker-compose up -d

# Option 2: InfluxDB2 + Telegraf + Grafana (Advanced)
cd monitoring/influxdb2
docker-compose up -d
```

## 🔍 **Testing and Validation**

### Health Endpoint Testing
```bash
# Test all endpoints
curl http://localhost:9099/metrics
curl http://localhost:9099/health
curl http://localhost:9099/health/simple

# Validate JSON response
curl http://localhost:9099/health | jq '.status'
```

### Monitoring Stack Testing
```bash
# Prometheus stack
curl http://localhost:9090/targets
curl http://localhost:3000/api/health

# InfluxDB2 stack
curl http://localhost:8086/ping
curl http://localhost:3001/api/health
```

## 📚 **Documentation Updates**

### New Documentation
- `monitoring/influxdb2/README.md` - Comprehensive InfluxDB2 setup guide
- Enhanced `monitoring/README.md` - Stack comparison and selection guide
- Updated troubleshooting sections with new monitoring options

### Updated Scripts
- `monitoring/scripts/fix-prometheus-issues.sh` - Updated for METRICS_* variables
- Enhanced health check scripts with new status detection

## 🐛 **Bug Fixes**

- **Fixed TRANSMISSION_EXPORTER references** in monitoring scripts
- **Updated variable names** throughout codebase for consistency
- **Improved error handling** in health endpoint
- **Enhanced network detection** for VPN interfaces
- **Fixed memory calculation** in system monitoring

## ⚡ **Performance Optimizations**

- **Optimized psutil usage** for system monitoring
- **Reduced health check frequency** options
- **Efficient Flux queries** for InfluxDB2
- **Streamlined dashboard rendering** with proper aggregation
- **Network timeout optimizations** for external IP detection

## 🔐 **Security Enhancements**

- **Sensitive data redaction** in container environment variables
- **Secure token handling** in InfluxDB2 configuration
- **Network isolation** options for monitoring stacks
- **Health endpoint rate limiting** considerations

## 🎯 **Recommendations**

### For New Users
- Start with **Prometheus + Grafana** for simplicity
- Enable basic metrics with `METRICS_ENABLED=true`
- Use default configuration for initial setup

### For Advanced Users
- Deploy **InfluxDB2 + Telegraf + Grafana** for comprehensive monitoring
- Customize Telegraf configuration for specific needs
- Implement custom alerting rules

### For Production
- Use InfluxDB2 stack for long-term data retention
- Implement proper backup strategies
- Monitor resource usage and optimize collection intervals

## 🔗 **Related Resources**

- [Main README](README.md) - TransmissionVPN configuration
- [Monitoring Guide](monitoring/README.md) - Complete monitoring setup
- [InfluxDB2 Setup](monitoring/influxdb2/README.md) - Detailed InfluxDB2 guide
- [Health Check Options](HEALTHCHECK_OPTIONS.md) - Health monitoring configuration

---

**Upgrade Command:**
```bash
docker pull magicalyak/transmissionvpn:v4.0.6-r14
docker stop transmission
docker rm transmission
# Recreate with your existing configuration
```

**Note**: This release maintains full backward compatibility while adding powerful new monitoring capabilities. Choose the monitoring stack that best fits your needs and expertise level. 
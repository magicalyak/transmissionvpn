# TransmissionVPN Monitoring

This directory contains comprehensive monitoring configurations for TransmissionVPN with multiple backend options.

## 🎯 **Monitoring Options**

Choose the monitoring stack that best fits your needs:

### 1. **Prometheus + Grafana** (Recommended for simplicity)
- **Location**: `docker-compose/`
- **Best for**: Simple setup, Prometheus ecosystem integration
- **Features**: Real-time metrics, basic alerting, lightweight

### 2. **InfluxDB2 + Telegraf + Grafana** (Recommended for advanced users)
- **Location**: `influxdb2/`
- **Best for**: Advanced analytics, long-term storage, comprehensive monitoring
- **Features**: Time-series optimization, advanced querying, detailed system metrics

## 🚀 **Quick Start**

### Option 1: Prometheus Stack
```bash
cd monitoring/docker-compose
docker-compose up -d
```
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090

### Option 2: InfluxDB2 Stack
```bash
cd monitoring/influxdb2
docker-compose up -d
```
- Grafana: http://localhost:3001 (admin/admin)
- InfluxDB2: http://localhost:8086 (admin/transmissionvpn123)
- Chronograf: http://localhost:8888

## 📊 **TransmissionVPN Metrics Server**

The main TransmissionVPN container includes a built-in custom metrics server that provides:

- **Prometheus metrics** at `/metrics` endpoint
- **Enhanced health data** at `/health` endpoint (JSON format like nzbgetvpn)
- **Simple health check** at `/health/simple` endpoint (plain text OK/Service Unavailable)

### Enable Metrics in TransmissionVPN

```env
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
```

### Test Endpoints

```bash
# Prometheus metrics
curl http://your-server:9099/metrics

# Enhanced health data (JSON)
curl http://your-server:9099/health

# Simple health check
curl http://your-server:9099/health/simple
```

## 📈 **Available Metrics**

### Transmission Metrics
- `transmission_torrent_count` - Total number of torrents
- `transmission_active_torrents` - Number of active torrents
- `transmission_downloading_torrents` - Number of downloading torrents
- `transmission_seeding_torrents` - Number of seeding torrents
- `transmission_download_rate_bytes_per_second` - Current download rate
- `transmission_upload_rate_bytes_per_second` - Current upload rate
- `transmission_session_downloaded_bytes` - Session downloaded bytes
- `transmission_session_uploaded_bytes` - Session uploaded bytes

### System & VPN Metrics
- `transmissionvpn_container_running` - Container status (1=running, 0=down)
- `transmissionvpn_vpn_connected` - VPN connection status (1=connected, 0=disconnected)
- `transmissionvpn_web_ui_up` - Web UI accessibility (1=up, 0=down)
- `transmissionvpn_external_ip_reachable` - External IP check (1=reachable, 0=unreachable)
- `transmissionvpn_disk_usage_percent` - Disk usage percentage
- `transmissionvpn_disk_available_bytes` - Available disk space

## 🔍 **Enhanced Health Endpoint**

The `/health` endpoint returns comprehensive status information similar to nzbgetvpn:

```json
{
  "timestamp": 1703123456,
  "iso_timestamp": "2023-12-21T10:17:36+00:00",
  "status": "healthy",
  "version": "4.0.6-r13",
  "service": "transmissionvpn",
  "uptime_seconds": 86400,
  "system": {
    "hostname": "transmission-container",
    "platform": {
      "system": "Linux",
      "release": "5.15.0",
      "machine": "x86_64"
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

### Status Values
- `healthy` - All systems operational
- `degraded` - Some issues but Transmission is running (warnings present)
- `unhealthy` - Critical issues, Transmission down
- `error` - Unable to determine status

### Issues and Warnings
- **Critical Issues** (status: unhealthy):
  - `transmission_daemon_down` - Transmission daemon not running
  - `web_ui_inaccessible` - Web UI not responding
  - `rpc_inaccessible` - RPC interface not accessible

- **Warnings** (status: degraded):
  - `vpn_disconnected` - VPN not connected
  - `disk_space_low` - Disk usage > 90%
  - `memory_usage_high` - Memory usage > 90%
  - `port_not_open` - Peer port not accessible

## 🐳 **Monitoring Stack Comparison**

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

### Prometheus Stack Features
- ✅ Simple setup and configuration
- ✅ Native Prometheus metrics support
- ✅ Built-in alerting with Alertmanager
- ✅ Large ecosystem and community
- ✅ Efficient for application metrics
- ❌ Limited system metrics collection
- ❌ Basic time-series functions

### InfluxDB2 Stack Features
- ✅ Comprehensive system monitoring
- ✅ Advanced time-series analytics
- ✅ Powerful Flux query language
- ✅ Built-in data processing
- ✅ Excellent for IoT and system metrics
- ✅ Beautiful pre-built dashboards
- ❌ More complex setup
- ❌ Higher resource requirements

## 📊 **Dashboard Features**

### Prometheus Dashboards
- **Main Dashboard**: System status, transfer speeds, torrent activity
- **Status Indicators**: Red/green status for container, VPN, web UI
- **Resource Monitoring**: Disk usage gauge, basic system metrics

### InfluxDB2 Dashboards
- **Overview Dashboard**: Comprehensive system health with beautiful visualizations
- **Analytics Dashboard**: Deep-dive performance analysis and trends
- **Advanced Metrics**: Memory breakdown, network analysis, container stats
- **Interactive Elements**: Drill-down capabilities, time range selection

## 🔧 **Configuration**

### Network Configuration

Update target configurations based on your setup:

#### For Same Docker Network
```yaml
# Prometheus
- targets: ['transmissionvpn:9099']

# Telegraf
urls = ["http://transmissionvpn:9099/metrics"]
```

#### For External TransmissionVPN
```yaml
# Prometheus
- targets: ['your-server.com:9099']

# Telegraf
urls = ["http://your-server.com:9099/metrics"]
```

### Environment Variables

Configure TransmissionVPN metrics:

```env
# Enable metrics collection
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30

# Health check configuration
HEALTH_CHECK_TIMEOUT=10
EXTERNAL_IP_SERVICE=ifconfig.me
```

## 🚨 **Troubleshooting**

### Common Issues

#### 1. Metrics Not Appearing
```bash
# Check if metrics are enabled
docker logs transmission | grep -i metrics

# Verify endpoint accessibility
curl http://your-server:9099/metrics
curl http://your-server:9099/health

# Check monitoring stack logs
docker logs prometheus  # or telegraf
docker logs grafana
```

#### 2. VPN Status Not Updating
```bash
# Check VPN interface
docker exec transmission ip addr show

# Test external IP detection
docker exec transmission curl -s ifconfig.me

# Verify health endpoint
curl http://your-server:9099/health | jq '.vpn'
```

#### 3. Dashboard Not Loading
```bash
# Check data source configuration
# Prometheus: http://localhost:9090/targets
# InfluxDB2: Check connection in Grafana data sources

# Verify network connectivity
docker exec grafana curl http://prometheus:9090/api/v1/query?query=up
# or
docker exec grafana-influx curl http://influxdb:8086/ping
```

### Performance Optimization

#### Reduce Collection Frequency
```env
# TransmissionVPN
METRICS_INTERVAL=60  # Increase from 30 seconds

# Prometheus
scrape_interval: 60s  # In prometheus.yml

# Telegraf
interval = "60s"  # In telegraf.conf
```

#### Optimize Storage
```yaml
# Prometheus retention
- '--storage.tsdb.retention.time=30d'

# InfluxDB2 retention
DOCKER_INFLUXDB_INIT_RETENTION=30d
```

## 📚 **Advanced Usage**

### Custom Metrics

Add custom metrics to the TransmissionVPN metrics server by modifying `scripts/transmission-metrics-server.py`.

### External Integration

Both monitoring stacks support:
- External Prometheus federation
- Remote write to external systems
- API access for custom applications
- Webhook notifications

### Backup and Monitoring

```bash
# Backup Prometheus data
docker run --rm -v prometheus-data:/data -v $(pwd):/backup alpine tar czf /backup/prometheus-backup.tar.gz /data

# Backup InfluxDB2 data
docker exec influxdb2 influx backup /tmp/backup
docker cp influxdb2:/tmp/backup ./influxdb-backup
```

## 🔗 **Related Documentation**

- [Main README](../README.md) - TransmissionVPN configuration
- [InfluxDB2 Setup](influxdb2/README.md) - Detailed InfluxDB2 monitoring guide
- [Environment Variables](../README.md#environment-variables) - All available options
- [Health Check Options](../HEALTHCHECK_OPTIONS.md) - Health monitoring configuration

## 🆘 **Support**

For monitoring-specific issues:

1. Check the appropriate stack's logs
2. Verify network connectivity between services
3. Ensure TransmissionVPN metrics are enabled
4. Review the troubleshooting sections above
5. Consult the official documentation for Prometheus, InfluxDB2, or Grafana

---

**Choose Your Stack**: 
- **New users**: Start with Prometheus + Grafana for simplicity
- **Advanced users**: Use InfluxDB2 + Telegraf + Grafana for comprehensive monitoring
- **Both**: Run both stacks on different ports for comparison 
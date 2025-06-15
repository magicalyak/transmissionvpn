# TransmissionVPN InfluxDB2 Monitoring Stack

This directory contains a complete monitoring solution for TransmissionVPN using InfluxDB2, Telegraf, and Grafana - providing comprehensive metrics collection, storage, and visualization.

## 🎯 **Overview**

The InfluxDB2 monitoring stack offers:

- **InfluxDB2** - Time-series database for metrics storage with 365-day retention
- **Telegraf** - Comprehensive metrics collection agent
- **Grafana** - Beautiful dashboards and visualization
- **Chronograf** - InfluxDB management interface (optional)

### Key Features

- 📊 **Comprehensive Metrics**: System, VPN, Transmission, Docker, and network metrics
- 🎨 **Beautiful Dashboards**: Pre-built Grafana dashboards with modern visualizations
- 🔍 **Deep Analytics**: Detailed performance analysis and trend monitoring
- 🚨 **Health Monitoring**: Real-time status tracking and alerting capabilities
- 📈 **Long-term Storage**: 365-day data retention for historical analysis

## 🚀 **Quick Start**

### 1. Start the Monitoring Stack

```bash
cd monitoring/influxdb2
docker-compose up -d
```

### 2. Access the Interfaces

- **Grafana**: http://localhost:3001 (admin/admin)
- **InfluxDB2**: http://localhost:8086 (admin/transmissionvpn123)
- **Chronograf**: http://localhost:8888 (optional)

### 3. Configure TransmissionVPN

Ensure your TransmissionVPN container has metrics enabled:

```env
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
```

### 4. Update Telegraf Configuration

Edit `telegraf.conf` to point to your TransmissionVPN instance:

```toml
# For external TransmissionVPN server
urls = ["http://your-server.com:9099/metrics"]
urls = ["http://your-server.com:9099/health"]
```

## 📊 **Available Dashboards**

### 1. TransmissionVPN Overview
**File**: `grafana/dashboards/transmissionvpn-overview.json`

- System health status indicators
- Real-time transfer speeds
- Torrent activity breakdown
- Resource utilization gauges
- VPN connection monitoring
- Network performance metrics

### 2. Detailed Analytics
**File**: `grafana/dashboards/transmissionvpn-analytics.json`

- Torrent status distribution (pie chart)
- Memory usage breakdown
- Container resource analysis
- Disk I/O operations
- DNS performance monitoring
- Network error tracking

## 🔧 **Configuration**

### InfluxDB2 Settings

```yaml
environment:
  - DOCKER_INFLUXDB_INIT_USERNAME=admin
  - DOCKER_INFLUXDB_INIT_PASSWORD=transmissionvpn123
  - DOCKER_INFLUXDB_INIT_ORG=transmissionvpn
  - DOCKER_INFLUXDB_INIT_BUCKET=metrics
  - DOCKER_INFLUXDB_INIT_RETENTION=365d
  - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=transmissionvpn-super-secret-token
```

### Telegraf Collection

The Telegraf agent collects:

#### Application Metrics
- TransmissionVPN Prometheus metrics (`/metrics` endpoint)
- Health data from JSON endpoint (`/health`)
- HTTP response times
- Custom application tags

#### System Metrics
- CPU usage (per-core and total)
- Memory and swap utilization
- Disk usage and I/O operations
- Network interface statistics
- System load averages
- Process counts

#### Docker Metrics
- Container resource usage
- Container logs (optional)
- Docker daemon statistics
- Container lifecycle events

#### Network Monitoring
- Ping tests to external hosts
- DNS query performance
- VPN interface statistics
- Network error rates

### Grafana Provisioning

Dashboards and data sources are automatically provisioned:

```yaml
# Data source configuration
datasources:
  - name: InfluxDB2
    type: influxdb
    url: http://influxdb:8086
    jsonData:
      version: Flux
      organization: transmissionvpn
      defaultBucket: metrics
```

## 📈 **Metrics Reference**

### TransmissionVPN Health Metrics

```flux
from(bucket: "metrics")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "transmissionvpn_health")
```

**Available Fields**:
- `uptime_seconds` - System uptime
- `load_1m`, `load_5m`, `load_15m` - Load averages
- `memory_total`, `memory_available`, `memory_used` - Memory stats
- `disk_total`, `disk_used`, `disk_usage_percent` - Disk usage
- `connected` - VPN connection status
- `web_ui_accessible`, `rpc_accessible` - Service status
- `response_time_ms` - API response times

### Transmission Application Metrics

```flux
from(bucket: "metrics")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] =~ /^transmission_/)
```

**Available Measurements**:
- `transmission_torrent_count` - Total torrents
- `transmission_active_torrents` - Active torrents
- `transmission_downloading_torrents` - Downloading
- `transmission_seeding_torrents` - Seeding
- `transmission_download_rate_bytes_per_second` - Download speed
- `transmission_upload_rate_bytes_per_second` - Upload speed
- `transmission_session_downloaded_bytes` - Session totals
- `transmission_session_uploaded_bytes` - Session totals

### System Metrics

```flux
# CPU Usage
from(bucket: "metrics")
  |> filter(fn: (r) => r["_measurement"] == "cpu")
  |> filter(fn: (r) => r["_field"] == "usage_active")

# Memory Usage
from(bucket: "metrics")
  |> filter(fn: (r) => r["_measurement"] == "mem")
  |> filter(fn: (r) => r["_field"] == "used_percent")

# Network Traffic
from(bucket: "metrics")
  |> filter(fn: (r) => r["_measurement"] == "net")
  |> filter(fn: (r) => r["_field"] =~ /bytes_(sent|recv)/)
```

## 🔍 **Querying Data**

### Flux Query Examples

#### Current VPN Status
```flux
from(bucket: "metrics")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "transmissionvpn_health")
  |> filter(fn: (r) => r["_field"] == "connected")
  |> last()
```

#### Average Download Speed (Last Hour)
```flux
from(bucket: "metrics")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "transmission_download_rate_bytes_per_second")
  |> mean()
```

#### System Load Trend
```flux
from(bucket: "metrics")
  |> range(start: -24h)
  |> filter(fn: (r) => r["_measurement"] == "transmissionvpn_health")
  |> filter(fn: (r) => r["_field"] == "load_1m")
  |> aggregateWindow(every: 5m, fn: mean)
```

## 🚨 **Alerting**

### Grafana Alerts

Create alerts for critical conditions:

#### VPN Disconnection Alert
```flux
from(bucket: "metrics")
  |> range(start: -5m)
  |> filter(fn: (r) => r["_measurement"] == "transmissionvpn_health")
  |> filter(fn: (r) => r["_field"] == "connected")
  |> last()
  |> map(fn: (r) => ({r with _value: if r._value == false then 1 else 0}))
```

#### High Disk Usage Alert
```flux
from(bucket: "metrics")
  |> range(start: -5m)
  |> filter(fn: (r) => r["_measurement"] == "transmissionvpn_health")
  |> filter(fn: (r) => r["_field"] == "disk_usage_percent")
  |> last()
  |> filter(fn: (r) => r._value > 90)
```

#### Transmission Down Alert
```flux
from(bucket: "metrics")
  |> range(start: -5m)
  |> filter(fn: (r) => r["_measurement"] == "transmissionvpn_health")
  |> filter(fn: (r) => r["_field"] == "web_ui_accessible")
  |> last()
  |> map(fn: (r) => ({r with _value: if r._value == false then 1 else 0}))
```

## 🔧 **Troubleshooting**

### Common Issues

#### 1. No Data in Grafana
```bash
# Check Telegraf logs
docker logs telegraf

# Verify InfluxDB connection
docker exec telegraf telegraf --test --config /etc/telegraf/telegraf.conf

# Check InfluxDB data
docker exec influxdb2 influx query 'from(bucket:"metrics") |> range(start:-1h) |> limit(n:10)'
```

#### 2. TransmissionVPN Metrics Not Collected
```bash
# Test metrics endpoint
curl http://your-server:9099/metrics

# Test health endpoint
curl http://your-server:9099/health

# Check Telegraf configuration
docker exec telegraf cat /etc/telegraf/telegraf.conf | grep -A 10 "inputs.prometheus"
```

#### 3. Dashboard Not Loading
```bash
# Check Grafana logs
docker logs grafana-influx

# Verify data source
curl -u admin:admin http://localhost:3001/api/datasources

# Test InfluxDB connection from Grafana
docker exec grafana-influx curl http://influxdb:8086/ping
```

### Performance Tuning

#### Reduce Collection Frequency
```toml
# In telegraf.conf
[agent]
  interval = "60s"  # Increase from 30s

[[inputs.prometheus]]
  interval = "60s"  # Match agent interval
```

#### Optimize InfluxDB
```yaml
# In docker-compose.yml
environment:
  - INFLUXD_STORAGE_CACHE_MAX_MEMORY_SIZE=1g
  - INFLUXD_STORAGE_CACHE_SNAPSHOT_MEMORY_SIZE=25m
```

## 📚 **Advanced Usage**

### Custom Metrics

Add custom metrics to Telegraf:

```toml
[[inputs.exec]]
  commands = ["/path/to/custom-script.sh"]
  data_format = "influx"
  interval = "60s"
```

### Data Retention Policies

Configure different retention periods:

```flux
// Create bucket with custom retention
bucket.create(
  bucket: "short-term",
  org: "transmissionvpn",
  retentionRules: [{type: "expire", everySeconds: 604800}] // 7 days
)
```

### Backup and Restore

```bash
# Backup InfluxDB data
docker exec influxdb2 influx backup /tmp/backup
docker cp influxdb2:/tmp/backup ./influxdb-backup

# Restore InfluxDB data
docker cp ./influxdb-backup influxdb2:/tmp/restore
docker exec influxdb2 influx restore /tmp/restore
```

## 🔗 **Integration**

### External Monitoring

Connect to external monitoring systems:

```toml
# Prometheus remote write
[[outputs.prometheus_client]]
  listen = ":9273"
  metric_version = 2

# External InfluxDB
[[outputs.influxdb_v2]]
  urls = ["https://external-influx.example.com:8086"]
  token = "$EXTERNAL_INFLUX_TOKEN"
  organization = "external-org"
  bucket = "transmissionvpn"
```

### API Access

Query data programmatically:

```python
from influxdb_client import InfluxDBClient

client = InfluxDBClient(
    url="http://localhost:8086",
    token="transmissionvpn-super-secret-token",
    org="transmissionvpn"
)

query = '''
from(bucket: "metrics")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "transmission_torrent_count")
  |> last()
'''

result = client.query_api().query(query)
```

## 📋 **Maintenance**

### Regular Tasks

1. **Monitor Disk Usage**: InfluxDB data grows over time
2. **Update Dashboards**: Keep visualizations current
3. **Review Alerts**: Ensure alerting rules are effective
4. **Backup Data**: Regular backups of important metrics
5. **Update Images**: Keep Docker images up to date

### Cleanup Commands

```bash
# Remove old data
docker exec influxdb2 influx delete \
  --bucket metrics \
  --start 2023-01-01T00:00:00Z \
  --stop 2023-06-01T00:00:00Z

# Compact database
docker exec influxdb2 influx server-config update \
  --storage-compact-full-write-cold-duration=1h
```

## 🆘 **Support**

For issues and questions:

1. Check the [main README](../../README.md) for TransmissionVPN configuration
2. Review Telegraf documentation: https://docs.influxdata.com/telegraf/
3. InfluxDB2 documentation: https://docs.influxdata.com/influxdb/v2.0/
4. Grafana documentation: https://grafana.com/docs/

---

**Note**: This monitoring stack is designed to work alongside the main TransmissionVPN container. Ensure your TransmissionVPN instance has metrics enabled and is accessible from the monitoring network. 
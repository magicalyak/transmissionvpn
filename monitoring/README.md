# 📊 Monitoring TransmissionVPN

This directory contains monitoring configurations and instructions for integrating TransmissionVPN with popular monitoring stacks.

## 🎯 Supported Monitoring Solutions

- **[Prometheus](#prometheus)** - Time-series database and monitoring system
- **[InfluxDB2](#influxdb2)** - Time-series database optimized for IoT and real-time analytics  
- **[Grafana](#grafana)** - Visualization and dashboard platform

## 📋 Prerequisites

- Docker and Docker Compose installed
- TransmissionVPN container running
- Basic understanding of monitoring concepts

## 🔧 Quick Start

### Environment Configuration

Before starting, copy and customize the environment file:

```bash
# Copy the sample environment file
cp monitoring/env.sample monitoring/.env

# Edit with your preferred settings
nano monitoring/.env
```

### Choose Your Stack

```bash
# Prometheus + Grafana
cd monitoring/prometheus
docker-compose up -d

# InfluxDB2 + Grafana  
cd monitoring/influxdb2
docker-compose up -d

# Complete stack (all monitoring solutions)
cd monitoring/complete
docker-compose up -d
```

## ⚙️ Environment Variables

The monitoring stack uses environment variables for configuration. Copy `env.sample` to `.env` and customize as needed:

### 📊 Grafana Configuration
```bash
GRAFANA_ADMIN_USER=admin              # Default admin username
GRAFANA_ADMIN_PASSWORD=admin          # Default admin password (⚠️ change in production!)
GRAFANA_ALLOW_SIGN_UP=false          # Allow new user registration
```

### 🔍 Prometheus Configuration
```bash
PROMETHEUS_RETENTION_TIME=200h        # How long to keep metrics data
PROMETHEUS_SCRAPE_INTERVAL=15s        # How often to collect metrics
```

### 💾 InfluxDB2 Configuration
```bash
INFLUXDB_ADMIN_USERNAME=admin         # InfluxDB2 admin username
INFLUXDB_ADMIN_PASSWORD=password123   # InfluxDB2 admin password (⚠️ change!)
INFLUXDB_ORG=transmissionvpn         # Organization name
INFLUXDB_BUCKET=metrics              # Default bucket for metrics
INFLUXDB_TOKEN=my-super-secret-auth-token  # API token (⚠️ generate unique!)
```

### 🌐 Transmission Configuration
```bash
TRANSMISSION_HOST=transmissionvpn     # Transmission container name/IP
TRANSMISSION_PORT=9091               # Transmission RPC port
TRANSMISSION_USERNAME=               # RPC username (if authentication enabled)
TRANSMISSION_PASSWORD=               # RPC password (if authentication enabled)
```

### 🔗 VPN Monitoring
```bash
HEALTH_CHECK_HOSTS=checkip.amazonaws.com,api.ipify.org,icanhazip.com
# Comma-separated list of hosts to check VPN connectivity
```

### 🌐 Network Configuration
```bash
MONITORING_NETWORK=monitoring               # Docker network for monitoring stack
TRANSMISSIONVPN_NETWORK=transmissionvpn_default  # TransmissionVPN network to connect to
```

### 🚪 Service Ports
```bash
PROMETHEUS_PORT=9090              # Prometheus web interface
GRAFANA_PORT=3000                # Grafana web interface
INFLUXDB_PORT=8086               # InfluxDB2 web interface
TRANSMISSION_EXPORTER_PORT=19091  # Transmission metrics exporter
CADVISOR_PORT=8080               # Container metrics
NODE_EXPORTER_PORT=9100          # System metrics
BLACKBOX_EXPORTER_PORT=9115      # Network probing
```

### 📦 Data Retention
```bash
METRICS_RETENTION_DAYS=30         # How long to keep metrics
LOG_RETENTION_DAYS=7             # How long to keep logs
```

### 🚨 Alert Configuration
```bash
ENABLE_ALERTS=true                    # Enable/disable alerting
ALERT_EMAIL=admin@example.com         # Email for alert notifications
SLACK_WEBHOOK_URL=                    # Slack webhook URL
DISCORD_WEBHOOK_URL=                  # Discord webhook URL
```

### 🔒 Security Notes

> **⚠️ Important**: Change default passwords and tokens before using in production!

```bash
# Generate secure passwords
openssl rand -base64 32

# Generate InfluxDB2 token
openssl rand -hex 32
```

## 📊 Prometheus

### Features
- 📈 Transmission metrics collection via HTTP API
- 🚨 Alerting rules for torrent monitoring
- 📊 Pre-configured Grafana dashboards
- 🔍 VPN connectivity monitoring

### Setup

1. **Configure Transmission for monitoring:**
   ```yaml
   # In your transmissionvpn docker-compose.yml
   environment:
     - TRANSMISSION_RPC_ENABLED=true
     - TRANSMISSION_RPC_HOST_WHITELIST_ENABLED=false
     - TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=false
   ```

   > **💡 Tip**: Set `TRANSMISSION_USERNAME` and `TRANSMISSION_PASSWORD` in your `.env` file if you enable RPC authentication.

2. **Start Prometheus stack:**
   ```bash
   cd monitoring/prometheus
   docker-compose up -d
   ```

3. **Access services:**
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000 (admin/admin)

### Configuration Files
- `prometheus/prometheus.yml` - Prometheus configuration
- `prometheus/alert-rules.yml` - Alerting rules
- `prometheus/docker-compose.yml` - Complete stack
- `grafana/dashboards/` - Pre-built dashboards

## 📊 InfluxDB2

### Features
- ⚡ High-performance time-series storage
- 📝 Flux query language support
- 🔄 Real-time data ingestion
- 📊 Native Grafana integration

### Setup

1. **Start InfluxDB2 stack:**
   ```bash
   cd monitoring/influxdb2
   docker-compose up -d
   ```

2. **Initial setup:**
   - Access InfluxDB2: http://localhost:8086
   - Initial setup is automated using environment variables from `.env`
   - Default credentials: `admin` / `password123` (⚠️ change in production!)
   - Organization: `transmissionvpn`
   - Bucket: `metrics`

3. **Environment variables:**
   The InfluxDB2 stack automatically configures itself using these variables:
   ```bash
   INFLUXDB_ADMIN_USERNAME=admin
   INFLUXDB_ADMIN_PASSWORD=password123
   INFLUXDB_ORG=transmissionvpn
   INFLUXDB_BUCKET=metrics
   INFLUXDB_TOKEN=my-super-secret-auth-token
   ```

### Configuration Files
- `influxdb2/docker-compose.yml` - Complete stack
- `telegraf/telegraf.conf` - Data collection agent
- `grafana/dashboards/` - InfluxDB2 dashboards

## 📊 Grafana Dashboards

### Available Dashboards

#### Transmission Overview
- 📈 Active torrents count
- 🔄 Download/upload rates
- 💾 Storage usage
- 🌐 VPN status

#### Network Monitoring  
- 🔌 VPN connectivity status
- 📡 IP address monitoring
- 🚀 Bandwidth utilization
- 📊 Connection statistics

#### System Resources
- 💻 Container CPU usage
- 🧠 Memory consumption
- 💾 Disk I/O statistics
- 🌡️ Container health status

### Dashboard Installation

1. **Automatic (via provisioning):**
   ```yaml
   # Dashboards are auto-loaded from:
   grafana/provisioning/dashboards/
   ```

2. **Manual import:**
   - Navigate to Grafana → Import
   - Upload JSON files from `grafana/dashboards/`
   - Configure data source

## 🚨 Alerting

### Prometheus Alerts
- ⚠️ VPN connection down
- 🐌 Slow download speeds
- 💾 Low disk space
- 🔴 Container unhealthy

### Alert Channels
- 📧 Email notifications
- 💬 Slack integration
- 📱 Discord webhooks
- 🔔 PagerDuty integration

## 📊 Metrics Collected

### Transmission Metrics
```
transmission_active_torrents_total
transmission_download_speed_bytes
transmission_upload_speed_bytes
transmission_free_space_bytes
transmission_session_stats_*
```

### System Metrics
```
container_cpu_usage_seconds_total
container_memory_usage_bytes
container_network_receive_bytes_total
container_network_transmit_bytes_total
```

### VPN Metrics
```
vpn_connection_status
vpn_public_ip_changed
vpn_tunnel_bytes_received
vpn_tunnel_bytes_sent
```

## 🔧 Customization

### Adding Custom Metrics

1. **Create custom exporter:**
   ```python
   # See examples/custom-exporter/
   # Python script to expose custom metrics
   ```

2. **Extend Telegraf configuration:**
   ```toml
   # Add to telegraf.conf
   [[inputs.exec]]
     commands = ["/path/to/custom-script.sh"]
     data_format = "influx"
   ```

### Custom Dashboards

1. **Export from Grafana:**
   - Dashboard → Share → Export → Save to file
   - Place in `grafana/dashboards/custom/`

2. **Version control:**
   ```bash
   # Add to git
   git add grafana/dashboards/custom/my-dashboard.json
   ```

## 🔍 Troubleshooting

### Common Issues

**Prometheus can't scrape metrics:**
```yaml
# Ensure network connectivity
networks:
  - monitoring
  - transmissionvpn_default
```

**InfluxDB2 connection refused:**
```bash
# Check container logs
docker logs influxdb2
# Verify port binding
docker ps | grep influxdb2
```

**Grafana dashboards not loading:**
```bash
# Check provisioning logs
docker logs grafana | grep provisioning
```

### Debug Commands

```bash
# Test Prometheus targets
curl http://localhost:9090/api/v1/targets

# Test InfluxDB2 API (replace with your token from .env)
curl -H "Authorization: Token ${INFLUXDB_TOKEN}" \
     http://localhost:8086/api/v2/buckets

# Test Grafana API
curl -H "Authorization: Bearer YOUR_API_KEY" \
     http://localhost:3000/api/health

# Check environment variables are loaded
docker-compose config | grep -i "environment"
```

### Environment Variable Issues

**Variables not being used:**
```bash
# Ensure .env file is in the same directory as docker-compose.yml
ls -la .env

# Check if variables are being substituted
docker-compose config | grep GRAFANA_ADMIN_USER
```

**Container can't connect to Transmission:**
```bash
# Check TRANSMISSION_HOST setting
docker network ls
docker inspect transmissionvpn | grep NetworkMode
```

## 📚 Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [InfluxDB2 Documentation](https://docs.influxdata.com/influxdb/v2.0/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Transmission RPC Protocol](https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md)

## 🤝 Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on:
- Adding new dashboards
- Improving alert rules
- Submitting monitoring enhancements 
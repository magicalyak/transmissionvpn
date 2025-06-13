# TransmissionVPN Monitoring

Monitoring solutions for TransmissionVPN - from simple single-container to full Prometheus/Grafana stack.

## 🎯 **Single Container Setup (Recommended)**

**Perfect for users who want health monitoring without additional containers.**

### **Quick Setup**
```bash
# 1. Enable built-in health metrics
echo "METRICS_ENABLED=true" >> /opt/containerd/env/transmission.env
docker restart transmission

# 2. View health status
docker exec transmission /root/healthcheck.sh
docker exec transmission cat /tmp/metrics.txt

# 3. Optional: Run health bridge for HTTP access
python3 scripts/health-bridge.py
# Access: http://localhost:8080/metrics
```

📖 **[Complete Single Container Guide →](docs/single-container-guide.md)**

---

## 🚀 **Full Monitoring Stack (Advanced)**

**For users who want comprehensive monitoring with Prometheus and Grafana.**

### **Quick Start**
```bash
cd monitoring/docker-compose
docker-compose up -d
```

**Access:**
- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **TransmissionVPN**: http://localhost:9091

The dashboard is automatically loaded in Grafana with transmission metrics!

## 📁 Directory Structure

```
monitoring/
├── README.md                           # This guide
├── scripts/                            # Health monitoring scripts
│   ├── health-bridge.py                # Single-container health bridge
│   └── README.md                       # Scripts documentation
├── docs/                               # Documentation
│   ├── single-container-guide.md       # Single container setup
│   ├── single-container-setup.md       # Alternative setup guide
│   └── single-container-instructions.md # Step-by-step instructions
└── docker-compose/                     # Full monitoring stack
    ├── docker-compose.yml              # Complete monitoring stack
    ├── prometheus.yml                  # Prometheus configuration
    └── grafana/                        # Grafana configuration
        ├── dashboards/
        │   └── transmissionvpn-dashboard.json
        └── provisioning/
            ├── datasources/prometheus.yml
            └── dashboards/dashboard.yml
```

## 📊 Dashboard Features

- **📈 Real-time Transfer Speeds** (download/upload)
- **📊 Torrent Statistics** (total, active, paused)
- **💾 System Info** (disk usage, free space)
- **📈 Transfer History** (cumulative and session stats)
- **🎨 Clean, responsive design**

## 🔧 Prerequisites

Your TransmissionVPN container needs these environment variables:

```bash
# Required for transmission metrics
TRANSMISSION_EXPORTER_ENABLED=true
TRANSMISSION_EXPORTER_PORT=9099

# Optional for enhanced health monitoring (single container)
METRICS_ENABLED=true
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true
```

## 📈 Available Metrics

### Transmission Core Metrics (Always Available)
- `transmission_session_stats_download_speed_bytes` - Current download speed
- `transmission_session_stats_upload_speed_bytes` - Current upload speed
- `transmission_session_stats_torrents_total` - Total number of torrents
- `transmission_session_stats_torrents_active` - Currently active torrents
- `transmission_session_stats_torrents_paused` - Paused torrents

### Transfer Statistics
- `transmission_session_stats_downloaded_bytes{type="cumulative"}` - All-time downloads
- `transmission_session_stats_uploaded_bytes{type="cumulative"}` - All-time uploads
- `transmission_session_stats_downloaded_bytes{type="current"}` - Session downloads
- `transmission_session_stats_uploaded_bytes{type="current"}` - Session uploads

### System Metrics
- `transmission_free_space` - Available disk space
- `transmission_cache_size_bytes` - Cache memory usage
- `transmission_version` - Transmission version info
- `transmission_global_peer_limit` - Maximum global peers
- `transmission_speed_limit_down_bytes` - Download speed limit
- `transmission_speed_limit_up_bytes` - Upload speed limit

**View all metrics:**
```bash
# Transmission metrics
curl http://localhost:9099/metrics | grep transmission_
```

## 🚨 Troubleshooting

### No metrics showing?

**Quick fix:**
```bash
cd monitoring/scripts
chmod +x quick-network-fix.sh
./quick-network-fix.sh
```

**Common issues:**
1. **Missing env vars**: Add `TRANSMISSION_EXPORTER_ENABLED=true` to your `.env` file
2. **Network isolation**: Containers on different Docker networks
3. **Port conflicts**: Port 9099 not exposed or in use

### Comprehensive diagnostics:
```bash
cd monitoring/scripts
chmod +x fix-prometheus-issues.sh
./fix-prometheus-issues.sh
```

## 🎯 Setup Options

### Option 1: Single Container (Recommended)
Perfect for most users - no additional containers needed:

```bash
# Enable health metrics in your existing container
echo "METRICS_ENABLED=true" >> /opt/containerd/env/transmission.env
docker restart transmission

# Optional: Run health bridge for HTTP access
python3 monitoring/scripts/health-bridge.py
```

### Option 2: Full Monitoring Stack
Includes Prometheus and Grafana for advanced monitoring:

```bash
# Start full monitoring stack
cd monitoring/docker-compose
docker-compose up -d
```

## 🔗 Useful Commands

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("transmission")) | .health'

# Test metrics endpoints
curl http://localhost:9099/metrics | head -10  # Transmission metrics

# View container logs
docker logs transmission | grep -i metric
docker logs prometheus | grep -i transmission
docker logs grafana
```

## 🆘 Need Help?

1. **Single Container Issues**: See [Single Container Guide](docs/single-container-guide.md)
2. **Run diagnostics**: `./scripts/fix-prometheus-issues.sh`
3. **Check container status**: `docker ps`
4. **Test connectivity**: `curl -v http://localhost:9099/metrics` 
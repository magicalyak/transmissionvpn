# TransmissionVPN Monitoring Setup

This directory contains a complete monitoring stack for TransmissionVPN using Prometheus and Grafana.

## 🚨 Troubleshooting Common Issues

### Issue: Prometheus Can't Scrape Metrics

**Symptoms:**
- Prometheus targets show as "down"
- `curl localhost:9099/metrics` fails
- Health checks showing all 0 values

**Root Causes & Solutions:**

#### 1. **METRICS_ENABLED=false** (Most Common)
```bash
# Check your transmission.env file
grep METRICS_ENABLED /opt/containerd/env/transmission.env

# Should be:
METRICS_ENABLED=true
TRANSMISSION_EXPORTER_ENABLED=true
```

#### 2. **Network Connectivity Issues**
```bash
# Wrong: Using localhost in Prometheus config
- targets: ['localhost:9099']

# Correct: Using container name
- targets: ['transmissionvpn:9099']
```

#### 3. **Container Not Exposing Metrics**
```bash
# Check if metrics endpoint is responding
curl -s http://localhost:9099/metrics | head -10

# Should return Prometheus-formatted metrics starting with transmission_
```

## 🔧 Quick Fix Script

Run our troubleshooting script to diagnose and fix issues:

```bash
cd monitoring
chmod +x fix-prometheus-issues.sh
./fix-prometheus-issues.sh
```

## 📊 Monitoring Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ TransmissionVPN │    │    Prometheus    │    │     Grafana     │
│                 │    │                  │    │                 │
│ Built-in        │───▶│ Scrapes metrics  │───▶│ Visualizes data │
│ Exporter :9099  │    │ every 15s        │    │ Dashboards      │
│                 │    │                  │    │                 │
│ Health checks   │    │ Stores time      │    │ Alerts          │
│ Internal metrics│    │ series data      │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### 1. **Fix TransmissionVPN Configuration**

Edit your `/opt/containerd/env/transmission.env`:

```bash
# Enable metrics (REQUIRED)
TRANSMISSION_EXPORTER_ENABLED=true
TRANSMISSION_EXPORTER_PORT=9099
METRICS_ENABLED=true

# Enable health monitoring
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true
HEALTH_CHECK_HOST=8.8.8.8
```

### 2. **Start Monitoring Stack**

```bash
# Navigate to monitoring directory
cd monitoring

# Start Prometheus + Grafana
docker-compose up -d

# Check logs
docker-compose logs -f
```

### 3. **Restart TransmissionVPN**

```bash
# Restart to apply new configuration
docker restart transmission
```

### 4. **Verify Setup**

```bash
# Check metrics endpoint
curl http://localhost:9099/metrics | grep transmission_

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("transmission"))'

# Access Grafana
open http://localhost:3000
# Login: admin/admin
```

## 📈 Available Metrics

### Built-in Prometheus Exporter
- **Torrent Statistics**: Active, downloading, seeding counts
- **Transfer Rates**: Download/upload speeds and totals
- **Session Info**: Uptime, version, configuration
- **Queue Status**: Torrent queue sizes and states

### Internal Health Metrics
- **System Health**: CPU, memory, disk usage
- **VPN Status**: Interface status, connectivity, ping times
- **Network**: Total RX/TX bytes, DNS resolution times
- **Security**: IP leak detection, DNS leak detection

## 🎯 Prometheus Targets

Your `prometheus.yml` should target:

```yaml
scrape_configs:
  # Built-in metrics exporter
  - job_name: 'transmissionvpn-exporter'
    static_configs:
      - targets: ['transmissionvpn:9099']
    scrape_interval: 15s

  # Health metrics (if using external server)
  - job_name: 'transmissionvpn-health'
    static_configs:
      - targets: ['host.docker.internal:8081']
    metrics_path: '/prometheus'
```

## 🔍 Debugging Commands

```bash
# Check container networking
docker network ls
docker inspect transmission | grep -A 10 Networks

# Test connectivity between containers
docker exec prometheus wget -qO- http://transmissionvpn:9099/metrics

# Check Prometheus configuration
docker exec prometheus cat /etc/prometheus/prometheus.yml

# View Prometheus targets
curl http://localhost:9090/api/v1/targets | jq .

# Check container logs
docker logs transmission | grep -i metrics
docker logs prometheus | grep -i transmission
```

## 📋 Grafana Dashboard Setup

1. **Access Grafana**: http://localhost:3000 (admin/admin)
2. **Import Dashboard**: 
   - Dashboard ID: `14355` (Transmission Dashboard)
   - Or ID: `13265` (Simple Transmission Exporter)
3. **Select Prometheus Datasource**
4. **Customize panels** as needed

## 🛠️ Troubleshooting Checklist

- [ ] `TRANSMISSION_EXPORTER_ENABLED=true` in env file
- [ ] `METRICS_ENABLED=true` in env file  
- [ ] Port 9099 exposed in docker run/compose
- [ ] Prometheus targets use container names, not localhost
- [ ] Containers on same Docker network
- [ ] Firewall allows port 9099
- [ ] TransmissionVPN container is healthy
- [ ] Metrics endpoint returns data: `curl localhost:9099/metrics`

## 📚 Advanced Configuration

### Multiple Metrics Approaches

You can use both built-in and external metrics:

```yaml
# Built-in exporter (recommended)
- job_name: 'transmissionvpn-builtin'
  static_configs:
    - targets: ['transmissionvpn:9099']

# External health server
- job_name: 'transmissionvpn-health'
  static_configs:
    - targets: ['host.docker.internal:8081']
  metrics_path: '/prometheus'
```

### Custom Metrics Collection

```bash
# Enable all monitoring features
TRANSMISSION_EXPORTER_ENABLED=true
METRICS_ENABLED=true
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true
HEALTH_CHECK_HOST=1.1.1.1
```

## 🆘 Getting Help

If you're still having issues:

1. **Run the troubleshooter**: `./fix-prometheus-issues.sh`
2. **Check logs**: `docker logs transmission | grep -i metric`
3. **Verify network**: `docker network inspect transmissionvpn_default`
4. **Test endpoints**: `curl -v http://localhost:9099/metrics`

## 🔗 Useful Links

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Transmission Exporter](https://github.com/metalmatze/transmission-exporter)
- [Docker Networking](https://docs.docker.com/network/) 
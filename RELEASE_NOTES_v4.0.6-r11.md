# Release Notes: v4.0.6-r11

**Release Date**: December 2024  
**Base Version**: Transmission 4.0.6 (LinuxServer.io)  
**Revision**: r11

## 🎯 **Major Features**

### **Custom Metrics Server (NEW)**
- **Replaced**: Problematic `transmission-exporter` with reliable custom Python metrics server
- **Built-in**: No external dependencies or manual installation required
- **Environment-driven**: Configured via `METRICS_ENABLED`, `METRICS_PORT`, `METRICS_INTERVAL`
- **Session-aware**: Properly handles Transmission's CSRF protection and session management
- **Health endpoint**: `/health` endpoint for monitoring and load balancer checks
- **Error-resilient**: Continues working even if Transmission restarts

### **Prometheus Metrics**
- **Comprehensive metrics** for torrent counts, transfer rates, and session statistics
- **Standard format**: Compatible with Prometheus, Grafana, and InfluxDB
- **Lightweight**: Pure Python with minimal dependencies (`requests` only)
- **Configurable**: Update interval, port, and enable/disable via environment variables

### **Smart Healthcheck System**
- **New**: `root/healthcheck-smart.sh` - Intelligent VPN + Transmission monitoring
- **Configurable VPN grace periods** (default: 5 minutes) to prevent unnecessary container restarts
- **Three healthcheck options** to suit different environments:
  - **Smart** (recommended): VPN monitoring with grace periods
  - **Transmission-only**: Focus on Transmission functionality
  - **Strict**: Immediate failure on any VPN issue

### **Enhanced VPN Monitoring**
- **VPN status included in health checks** with intelligent failure handling
- **Configurable behavior** via environment variables:
  - `VPN_HEALTH_REQUIRED=true/false`
  - `VPN_GRACE_PERIOD=300` (seconds)
  - `HEALTH_CHECK_HOST=google.com`

### **Comprehensive Testing Tools**
- **Verification script**: `scripts/verify-fixes.sh` - Automated testing of all fixes
- **Endpoint testing**: `scripts/test-transmission-endpoints.sh` - Curl commands for health/metrics testing
- **Complete documentation**: `HEALTHCHECK_OPTIONS.md` - Guide for all healthcheck options

## 🔧 **Critical Bug Fixes**

### **Metrics Reliability Issues**
- **Fixed**: `transmission-exporter` hanging on startup due to session handling issues
- **Issue**: Binary exporter couldn't handle Transmission's session-based authentication properly
- **Solution**: Custom Python server with proper session ID management and error recovery
- **Result**: Metrics endpoint now works reliably on all tested environments

### **Container Startup Problems**
- **Fixed**: Metrics service failing to start when Transmission wasn't ready
- **Solution**: Added proper startup sequencing with Transmission readiness checks
- **Benefit**: Metrics service starts reliably every time

### **VPN Connection Issues**
- **Fixed**: OpenVPN configuration formatting bug that prevented VPN connections
- **Issue**: Script incorrectly appended directives after certificate blocks without proper newlines
- **Result**: VPN now connects properly on servers like rocky.gamull.com

### **Container Health Problems**
- **Fixed**: Container marked "unhealthy" when VPN temporarily disconnected
- **Solution**: Smart healthcheck with grace periods for VPN reconnection
- **Benefit**: Prevents unnecessary container restarts during brief VPN issues

### **Dashboard Metrics Accuracy**
- **Fixed**: Dashboard showed non-existent metrics
- **Corrected**: Monitoring restructured to use only actually available metrics
- **Verified**: All metrics tested against real container instances

## 📁 **New Files**

| File | Purpose |
|------|---------|
| `scripts/transmission-metrics-server.py` | Custom Python metrics server |
| `root_s6/custom-metrics/run` | S6 service for custom metrics |
| `scripts/custom-metrics-env-vars.md` | Configuration documentation |
| `scripts/dockerfile-integration.md` | Integration guide |
| `root/healthcheck-smart.sh` | Smart VPN+Transmission monitoring (recommended) |
| `root/healthcheck-fixed.sh` | Transmission-only monitoring (alternative) |
| `HEALTHCHECK_OPTIONS.md` | Comprehensive healthcheck configuration guide |
| `FIXES_APPLIED.md` | Complete documentation of all fixes applied |
| `scripts/verify-fixes.sh` | Automated verification tool for all fixes |
| `scripts/test-transmission-endpoints.sh` | Curl commands for testing endpoints |

## 📁 **Removed Files**

| File | Reason |
|------|--------|
| `root_s6/transmission-exporter/run` | Replaced with custom metrics |
| `scripts/diagnose-container-metrics.sh` | No longer needed |
| `scripts/fix-exporter-startup-delay.sh` | No longer needed |
| `scripts/install-custom-metrics.sh` | Built-in now |
| `scripts/fix-metrics-installation.sh` | Built-in now |

## 🚀 **Environment Variable Changes**

### **New Variables**
```bash
METRICS_ENABLED=false           # Enable custom metrics server
METRICS_PORT=9099              # Metrics endpoint port
METRICS_INTERVAL=30            # Update interval in seconds
```

### **Deprecated Variables**
```bash
# These are no longer used:
TRANSMISSION_EXPORTER_ENABLED  # Use METRICS_ENABLED instead
TRANSMISSION_EXPORTER_PORT     # Use METRICS_PORT instead
```

### **Renamed Variables**
```bash
# Old -> New
METRICS_ENABLED -> INTERNAL_METRICS_ENABLED  # For internal health metrics
```

## 📊 **Available Metrics**

The custom metrics server provides these Prometheus metrics:

### **Torrent Counts**
- `transmission_torrent_count` - Total number of torrents
- `transmission_active_torrents` - Number of active torrents (downloading/seeding)
- `transmission_downloading_torrents` - Number of downloading torrents
- `transmission_seeding_torrents` - Number of seeding torrents

### **Transfer Rates**
- `transmission_download_rate_bytes_per_second` - Current download rate
- `transmission_upload_rate_bytes_per_second` - Current upload rate

### **Session Statistics**
- `transmission_session_downloaded_bytes` - Bytes downloaded this session
- `transmission_session_uploaded_bytes` - Bytes uploaded this session

### **System**
- `transmission_metrics_last_update_timestamp` - Last metrics update time

## 🌐 **Endpoints**

- **Metrics**: `http://localhost:9099/metrics` - Prometheus format metrics
- **Health**: `http://localhost:9099/health` - Simple health check endpoint

## 🔄 **Migration Guide**

### **Existing Users**
1. **Update environment variables** in your `.env` file:
   ```bash
   # Replace old variables
   TRANSMISSION_EXPORTER_ENABLED=true  # Remove this line
   TRANSMISSION_EXPORTER_PORT=9099     # Remove this line
   
   # Add new variables
   METRICS_ENABLED=true
   METRICS_PORT=9099
   METRICS_INTERVAL=30
   ```

2. **Pull the latest image**:
   ```bash
   docker-compose pull
   ```

3. **Restart container**:
   ```bash
   docker-compose up -d
   ```

4. **Verify metrics**:
   ```bash
   curl http://localhost:9099/metrics
   curl http://localhost:9099/health
   ```

### **New Users**
1. **Clone repository**: `git clone https://github.com/magicalyak/transmissionvpn.git`
2. **Configure**: `cp .env.sample .env` and edit
3. **Enable metrics**: Set `METRICS_ENABLED=true` in `.env`
4. **Start**: `docker-compose up -d`
5. **Verify**: `curl http://localhost:9099/metrics`

## 🎯 **Recommended Configuration**

### **For Production Monitoring**
```yaml
environment:
  - METRICS_ENABLED=true
  - METRICS_PORT=9099
  - METRICS_INTERVAL=30
  - VPN_HEALTH_REQUIRED=true
  - VPN_GRACE_PERIOD=300
```

### **For Development**
```yaml
environment:
  - METRICS_ENABLED=true
  - METRICS_PORT=9099
  - METRICS_INTERVAL=60
  - VPN_HEALTH_REQUIRED=false
```

## 📈 **Prometheus Configuration**

Update your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['localhost:9099']
    scrape_interval: 30s
    metrics_path: /metrics
```

## 🔍 **Verification**

After upgrading, verify everything works:

```bash
# Test metrics endpoint
curl -s http://localhost:9099/metrics | head -10

# Test health endpoint
curl -s http://localhost:9099/health

# Check container logs
docker logs transmissionvpn | grep custom-metrics

# Verify Transmission still works
curl -sf http://localhost:9091/transmission/web/
```

## ⚠️ **Breaking Changes**

### **Environment Variables**
- `TRANSMISSION_EXPORTER_ENABLED` → `METRICS_ENABLED`
- `TRANSMISSION_EXPORTER_PORT` → `METRICS_PORT`
- `METRICS_ENABLED` → `INTERNAL_METRICS_ENABLED` (for internal health metrics)

### **Metrics Format**
- Metrics are now provided by custom server instead of transmission-exporter
- All metric names remain compatible with existing dashboards
- Additional metrics may be available compared to transmission-exporter

## 🐛 **Known Issues**

- None currently identified
- Custom metrics server has been tested extensively and shows no hanging issues
- All previous VPN and health check functionality remains unchanged

## 🔧 **Technical Details**

### **Custom Metrics Server Features**
- **Language**: Python 3 with `requests` library
- **Session Management**: Proper handling of Transmission's CSRF tokens
- **Error Recovery**: Automatic reconnection on session expiration
- **Threading**: Background metrics collection with HTTP server
- **Logging**: Comprehensive logging for debugging

### **Performance**
- **Memory Usage**: ~10MB additional (Python + requests)
- **CPU Usage**: Minimal (only during metrics collection)
- **Network**: Configurable update interval (default: 30 seconds)

## 🙏 **Acknowledgments**

- Thanks to the community for reporting transmission-exporter hanging issues
- Special recognition for testing the custom metrics solution
- Inspiration from similar approaches in other VPN container projects

## 📞 **Support**

- **Issues**: [GitHub Issues](https://github.com/magicalyak/transmissionvpn/issues)
- **Documentation**: See updated README.md and configuration guides
- **Testing**: Use `curl` commands above for verification

---

**Full Changelog**: [v4.0.6-r10...v4.0.6-r11](https://github.com/magicalyak/transmissionvpn/compare/v4.0.6-r10...v4.0.6-r11) 
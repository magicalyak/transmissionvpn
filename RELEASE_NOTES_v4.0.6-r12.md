# Release Notes - v4.0.6-r12

## 🔧 Critical Bug Fix Release

This release fixes a critical networking issue where the metrics endpoint and BitTorrent peer port were not accessible externally due to missing iptables rules.

### 🐛 Bug Fixes

**Fixed External Access to Metrics and BitTorrent Ports**
- **Issue**: Metrics endpoint (port 9099) and BitTorrent peer port (51413) were not accessible from outside the container
- **Root Cause**: Missing iptables INPUT rules in the VPN setup script
- **Solution**: Added proper iptables rules and CONNMARK policy routing for:
  - Metrics server port (9099) when `METRICS_ENABLED=true`
  - BitTorrent peer port (51413) when `TRANSMISSION_PEER_PORT` is set
  - Proper policy routing to ensure responses go back through the correct interface

### 🔍 Technical Details

The VPN setup script (`root/vpn-setup.sh`) now includes:

```bash
# Allow metrics server access if enabled
if [ "${METRICS_ENABLED,,}" = "true" ]; then
  iptables -A INPUT -i eth0 -p tcp --dport "${METRICS_PORT:-9099}" -j ACCEPT
  echo "[INFO] Added iptables rule to allow metrics server on eth0:${METRICS_PORT:-9099}."
fi

# Allow BitTorrent peer port if set
if [ -n "$TRANSMISSION_PEER_PORT" ]; then
  iptables -A INPUT -i eth0 -p tcp --dport "$TRANSMISSION_PEER_PORT" -j ACCEPT
  iptables -A INPUT -i eth0 -p udp --dport "$TRANSMISSION_PEER_PORT" -j ACCEPT
  echo "[INFO] Added iptables rule to allow BitTorrent peer port on eth0:$TRANSMISSION_PEER_PORT (TCP/UDP)."
fi
```

Plus corresponding CONNMARK policy routing rules for proper response handling.

### 🚀 Impact

- ✅ **Metrics endpoint** (`http://your-server:9099/metrics`) now accessible externally
- ✅ **Health endpoint** (`http://your-server:9099/health`) now accessible externally  
- ✅ **BitTorrent peer port** (51413) now accessible for incoming connections
- ✅ **Prometheus monitoring** now works correctly
- ✅ **Better torrent connectivity** with proper port forwarding

### 📋 Upgrade Instructions

1. **Pull the new image:**
   ```bash
   docker pull magicalyak/transmissionvpn:v4.0.6-r12
   ```

2. **Update your docker-compose.yml or restart command to use the new version:**
   ```yaml
   image: magicalyak/transmissionvpn:v4.0.6-r12
   ```

3. **Restart your container:**
   ```bash
   docker-compose down && docker-compose up -d
   ```

4. **Verify the fix:**
   ```bash
   # Test metrics endpoint
   curl http://your-server:9099/health
   curl http://your-server:9099/metrics
   
   # Test BitTorrent port (if configured)
   nc -zv your-server 51413
   ```

### 🔗 Related Issues

This fix resolves the networking issues reported where:
- Prometheus metrics collection was failing
- External monitoring systems couldn't reach the metrics endpoint
- BitTorrent clients had connectivity issues with peer connections

### ⚠️ Breaking Changes

None. This is a backward-compatible bug fix.

### 📊 Full Changelog

- **Fixed**: Missing iptables INPUT rules for metrics port (9099)
- **Fixed**: Missing iptables INPUT rules for BitTorrent peer port (51413)  
- **Added**: CONNMARK policy routing rules for metrics server
- **Improved**: VPN setup script logging for better debugging

---

**Previous Version**: v4.0.6-r11  
**Docker Image**: `magicalyak/transmissionvpn:v4.0.6-r12`  
**Release Date**: June 15, 2025 
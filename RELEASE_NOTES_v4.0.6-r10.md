# Release Notes: v4.0.6-r10

**Release Date**: December 2024  
**Base Version**: Transmission 4.0.6 (LinuxServer.io)  
**Revision**: r10

## 🎯 **Major Features**

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
| `root/healthcheck-smart.sh` | Smart VPN+Transmission monitoring (recommended) |
| `root/healthcheck-fixed.sh` | Transmission-only monitoring (alternative) |
| `HEALTHCHECK_OPTIONS.md` | Comprehensive healthcheck configuration guide |
| `FIXES_APPLIED.md` | Complete documentation of all fixes applied |
| `scripts/verify-fixes.sh` | Automated verification tool for all fixes |
| `scripts/test-transmission-endpoints.sh` | Curl commands for testing endpoints |

## 🚀 **Improvements**

### **Configuration Updates**
- **Updated**: `docker-compose.yml` now uses smart healthcheck by default
- **Enhanced**: `.env.sample` with VPN health configuration options
- **Improved**: README with verification steps and new feature documentation

### **Monitoring Enhancements**
- **Detailed logging** and metrics collection for better troubleshooting
- **Environment variables** for fine-tuning healthcheck behavior
- **Grace period handling** to distinguish between temporary and persistent VPN issues

### **User Experience**
- **Backward compatible** - existing setups work without changes
- **Configurable strictness** - adapt to your environment's needs
- **Better documentation** - comprehensive guides for all scenarios

## 🎯 **Recommended Usage**

### **For Most Users (Production)**
```yaml
healthcheck:
  test: ["CMD", "/root/healthcheck-smart.sh"]
environment:
  - VPN_HEALTH_REQUIRED=true
  - VPN_GRACE_PERIOD=300
  - METRICS_ENABLED=true
```

### **For Development**
```yaml
healthcheck:
  test: ["CMD", "/root/healthcheck-fixed.sh"]
```

### **For Strict Monitoring**
```yaml
healthcheck:
  test: ["CMD", "/root/healthcheck.sh"]
```

## 🔍 **Verification**

After upgrading, verify everything works:

```bash
# Run the verification script
./scripts/verify-fixes.sh

# Test endpoints
./scripts/test-transmission-endpoints.sh

# Manual health check
docker exec transmissionvpn /root/healthcheck-smart.sh
```

## 📊 **Metrics & Monitoring**

### **Available Endpoints**
- **Web UI**: `http://localhost:9091/transmission/web/`
- **Metrics**: `http://localhost:9099/metrics` (if enabled)
- **Health**: `docker exec transmissionvpn /root/healthcheck-smart.sh`

### **Key Curl Commands**
```bash
# Basic health
curl -sf http://localhost:9091/transmission/web/

# Metrics
curl -s http://localhost:9099/metrics | grep transmission_

# VPN status
docker exec transmissionvpn ip addr show tun0
```

## ⚠️ **Breaking Changes**

**None** - This release is fully backward compatible.

## 🔄 **Migration Guide**

### **Existing Users**
1. **Pull the latest image**: `docker-compose pull`
2. **Restart container**: `docker-compose up -d`
3. **Verify health**: `./scripts/verify-fixes.sh`

### **New Users**
1. **Clone repository**: `git clone https://github.com/magicalyak/transmissionvpn.git`
2. **Configure**: `cp .env.sample .env` and edit
3. **Start**: `docker-compose up -d`
4. **Verify**: `./scripts/verify-fixes.sh`

## 🐛 **Known Issues**

- VPN provider-specific configuration may still require manual adjustment
- Dashboard metrics need manual correction to use verified available metrics
- Some VPN providers may have different interface naming (wg0 vs tun0)

## 🙏 **Acknowledgments**

- Thanks to the community for reporting VPN connection issues
- Special recognition for identifying the need for VPN status in health checks
- LinuxServer.io team for the excellent base Transmission image

## 📞 **Support**

- **Issues**: [GitHub Issues](https://github.com/magicalyak/transmissionvpn/issues)
- **Documentation**: See `HEALTHCHECK_OPTIONS.md` and `FIXES_APPLIED.md`
- **Testing**: Use `scripts/verify-fixes.sh` for automated verification

---

**Full Changelog**: [v4.0.6-r9...v4.0.6-r10](https://github.com/magicalyak/transmissionvpn/compare/v4.0.6-r9...v4.0.6-r10) 
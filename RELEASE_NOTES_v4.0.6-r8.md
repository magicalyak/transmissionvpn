# Release Notes - v4.0.6-r8

## 🚀 Major Bug Fixes & Improvements

This release addresses critical VPN connection and health check issues that were preventing proper container operation.

### 🔧 Critical Bug Fixes

#### VPN Connection Fix
- **Issue**: VPN connections failing due to malformed OpenVPN configuration
- **Root Cause**: OpenVPN config directives were being appended without proper newlines after `</ca>` certificate block
- **Fix**: Added newline detection and insertion before appending configuration directives
- **Impact**: VPN now connects successfully (tun0 interface operational)
- **Files Changed**: `root/vpn-setup.sh`

#### Health Check Script Fix  
- **Issue**: False "interface not found" errors causing containers to show as unhealthy
- **Root Cause**: `log` function output to stdout interfered with function return values via `tee`
- **Fix**: Modified `log` function to output only to stderr (`>&2`)
- **Impact**: Health checks now work correctly, containers show as healthy
- **Files Changed**: `root/healthcheck.sh`

#### Health Check Configuration Fix
- **Issue**: LAN addresses being tested through VPN tunnel causing connectivity failures
- **Solution**: Added `health-patch.sh` wrapper that overrides LAN addresses with `google.com` for VPN testing
- **Impact**: VPN connectivity tests now work properly
- **Files Added**: `root/health-patch.sh`

### 📁 Monitoring Directory Restructure

Reorganized monitoring directory to match **nzbgetvpn** pattern with single-container priority:

```
monitoring/
├── README.md (prioritizes single-container setup)
├── scripts/ (health-bridge.py and troubleshooting tools)  
├── docs/ (single-container guides and fixes)
└── docker-compose/ (full monitoring stack for advanced users)
```

### 📊 Dashboard Metrics Corrections

- **Removed**: Non-existent metrics that caused dashboard errors
  - `transmissionvpn_container_running`
  - `transmissionvpn_web_ui_up` 
  - `transmissionvpn_vpn_connected`
  - `transmissionvpn_external_ip_reachable`

- **Verified**: Working metrics retained
  - `transmission_session_stats_download_speed_bytes` ✅
  - `transmission_session_stats_upload_speed_bytes` ✅  
  - `transmission_session_stats_torrents_total/active/paused` ✅
  - `transmission_free_space` ✅

### 📚 Documentation Improvements

#### New Documentation Added:
- `monitoring/docs/VPN_FIX_GUIDE.md` - Instructions to fix VPN script bug
- `monitoring/docs/HEALTH_FIX_GUIDE.md` - Health check fix options  
- `monitoring/docs/PERMANENT_HEALTH_FIX.md` - Implementation details
- `monitoring/docs/single-container-setup.md` - Single container setup guide
- `monitoring/MONITORING_SUMMARY.md` - Complete summary of changes
- `VERSIONING.md` - Versioning scheme documentation

#### Updated Documentation:
- `monitoring/README.md` - Now prioritizes single-container approach
- Main `README.md` - Updated to reflect single-container focus

## 🔄 Migration Guide

### For Existing Users:
1. **VPN Issues**: If experiencing VPN connection problems, the new `root/vpn-setup.sh` will resolve them
2. **Health Check Issues**: If containers show as unhealthy despite working properly, the new `root/healthcheck.sh` will fix this
3. **Monitoring**: Existing monitoring setups will continue to work, but consider the new single-container approach

### For New Users:
- Follow the updated `monitoring/README.md` for single-container setup
- Use `monitoring/docs/single-container-setup.md` for detailed instructions

## 🧪 Tested Environment

This release has been thoroughly tested on:
- **Server**: rocky.gamull.com
- **Container**: transmission (now shows as "healthy")
- **VPN**: PrivadoVPN with successful tun0 interface connection (IP: 172.21.34.32/23)
- **Metrics**: Available at :9099/metrics, dashboard functional
- **Transmission**: Fully operational and accessible

## 📋 Technical Details

### Files Modified:
- `root/vpn-setup.sh` - VPN connection fix
- `root/healthcheck.sh` - Health check logging fix
- `monitoring/README.md` - Updated priorities

### Files Added:
- `root/health-patch.sh` - Health check wrapper
- `monitoring/docs/` - Comprehensive documentation
- `monitoring/scripts/` - Troubleshooting tools
- `VERSIONING.md` - Version scheme documentation

### Files Removed:
- Old monitoring configurations that didn't work
- Temporary fix files (consolidated into proper locations)

## 🎯 What's Next

- Monitor for any additional VPN or health check edge cases
- Consider additional single-container monitoring improvements
- Evaluate upstream linuxserver.io transmission updates

## 🙏 Acknowledgments

Special thanks to the testing and validation performed on the rocky.gamull.com environment that made these fixes possible.

---

**Full Changelog**: https://github.com/magicalyak/transmissionvpn/compare/v4.0.6-r7...v4.0.6-r8 
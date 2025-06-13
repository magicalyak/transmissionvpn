# Release Notes - v4.0.6-r9

## 🚨 Critical Kill Switch Fix

This release resolves a critical **kill switch chicken-and-egg problem** that prevented VPN connections from establishing.

### 🔧 Critical Bug Fix

#### Kill Switch Blocking VPN Connection
- **Issue**: Kill switch blocked OpenVPN traffic to VPN server during initial connection
- **Symptoms**: 
  - `write UDPv4 []: Operation not permitted` errors in OpenVPN logs
  - VPN connection timeouts and failures
  - Container showing as unhealthy despite Transmission working
- **Root Cause**: Kill switch `iptables -A OUTPUT -o eth0 -j DROP` rule blocked UDP packets to VPN server (`45.38.16.37:1194`) before VPN tunnel was established
- **Impact**: VPN could not connect, defeating the purpose of the VPN-enabled container

#### The Fix: Smart Kill Switch Exception
- **Solution**: Added dynamic VPN server exception before applying kill switch
- **Implementation**: 
  ```bash
  # Extract VPN server from config and allow traffic to it
  VPN_SERVER=$(grep '^remote ' "$OVPN_CONFIG_FILE" | head -1 | awk '{print $2}')
  VPN_PORT=$(grep '^remote ' "$OVPN_CONFIG_FILE" | head -1 | awk '{print $3}')
  iptables -A OUTPUT -o eth0 -d "$VPN_SERVER" -p udp --dport "$VPN_PORT" -j ACCEPT
  ```
- **Result**: VPN now connects successfully while maintaining kill switch protection

### 🧪 Verified Fixes from Previous Releases

This release builds on the comprehensive fixes from v4.0.6-r8:

#### VPN Setup Script (v4.0.6-r8)
- ✅ **Fixed**: Malformed OpenVPN config due to missing newlines
- ✅ **Working**: VPN connects and creates tun0 interface properly

#### Health Check Script (v4.0.6-r8)  
- ✅ **Fixed**: stdout interference from log function
- ✅ **Working**: No more false "interface not found" errors

#### Dashboard Metrics (v4.0.6-r8)
- ✅ **Verified**: All transmission metrics working correctly
- ✅ **Available**: `transmission_session_stats_*`, `transmission_free_space`

### 🔧 Additional Configuration Fix

#### Health Check Host Configuration
- **Issue**: Health check tested LAN address (`10.1.10.1`) through VPN tunnel
- **Fix**: Update `HEALTH_CHECK_HOST=8.8.8.8` in container environment
- **Note**: Requires container recreation to take effect

### 🧪 Tested Environment

**Verified working on:**
- **Server**: rocky.gamull.com
- **VPN**: PrivadoVPN (atl-009.vpn.privado.io)
- **Connection**: tun0 interface with IP 172.21.24.30/23
- **Status**: Container healthy, VPN connected, Transmission operational

### 📋 Technical Details

#### Files Modified:
- `root/vpn-setup.sh` - Added kill switch exception logic

#### Kill Switch Logic:
1. **Parse OpenVPN config** to extract VPN server and port
2. **Add exception rule** before kill switch DROP rule
3. **Allow VPN handshake** while maintaining security
4. **Apply kill switch** for all other traffic

#### Deployment Requirements:
- Update container image to v4.0.6-r9
- Update `HEALTH_CHECK_HOST=8.8.8.8` in environment config
- Recreate container to apply environment changes

### 🔄 Migration Guide

#### For Existing Users:
1. **Update Image**: Pull `magicalyak/transmissionvpn:v4.0.6-r9`
2. **Update Config**: Set `HEALTH_CHECK_HOST=8.8.8.8` in environment
3. **Recreate Container**: Stop, remove, and recreate to apply fixes
4. **Verify**: Check VPN connection and container health status

#### Expected Results:
- ✅ VPN connects successfully on startup
- ✅ Container shows as "healthy"
- ✅ No "Operation not permitted" errors
- ✅ Kill switch protection maintained

### 🎯 What's Fixed

- ❌ **Before**: VPN connection failed due to kill switch blocking handshake
- ✅ **After**: VPN connects while maintaining kill switch security
- ❌ **Before**: Health check failed due to LAN address testing through VPN
- ✅ **After**: Health check passes with external address testing

### 🛡️ Security Notes

- **Kill switch protection maintained**: Only VPN server traffic allowed through eth0
- **All other traffic**: Still routed through VPN or blocked
- **LAN access**: Preserved for local network communication
- **No security degradation**: Fix is surgical and targeted

### 🙏 Acknowledgments

Special thanks to the thorough testing and debugging performed on rocky.gamull.com that identified and resolved this critical issue.

---

**Full Changelog**: https://github.com/magicalyak/transmissionvpn/compare/v4.0.6-r8...v4.0.6-r9 
# VPN Connection Fix Guide

## 🚨 Issue: VPN Not Connecting

If your healthcheck shows "VPN interface tun0 does not exist", this is due to a bug in the container's VPN setup script.

## 🔧 Quick Fix

### Step 1: Create a Fixed OpenVPN Config

SSH into your server and run:

```bash
# Access the container
docker exec -it transmission bash

# Create a corrected config file
cd /config/openvpn
cp atl-009.ovpn atl-009.ovpn.backup

# Create corrected version
head -n -1 atl-009.ovpn > atl-009-fixed.ovpn
cat >> atl-009-fixed.ovpn << 'EOF'
script-security 2
auth-user-pass /tmp/vpn-credentials
up /etc/openvpn/update-resolv.sh
down /etc/openvpn/restore-resolv.sh
EOF
tail -n 1 atl-009.ovpn >> atl-009-fixed.ovpn

# Replace the original
mv atl-009-fixed.ovpn atl-009.ovpn
```

### Step 2: Restart Container

```bash
docker restart transmission
```

### Step 3: Verify VPN Connection

```bash
# Wait 30 seconds, then check
docker exec transmission /root/healthcheck.sh

# Should show VPN interface exists
docker exec transmission ip addr show tun0
```

## 🔍 Alternative: Use Different VPN Provider

If the fix doesn't work, try a different VPN provider config file that doesn't have this issue.

## 📊 Monitoring Without VPN

Even without VPN, you can still monitor Transmission:

```bash
# Enable metrics
echo "METRICS_ENABLED=true" >> /opt/containerd/env/transmission.env
docker restart transmission

# Check metrics
curl http://localhost:9099/metrics | grep transmission_
```

## 🐛 Report the Bug

This is a known issue with the container's VPN setup script. Consider:
1. Reporting to the container maintainer
2. Using a different VPN container
3. Using the single-container monitoring approach (which works regardless of VPN status) 
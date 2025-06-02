# 🔧 Troubleshooting Guide

This document helps you diagnose and resolve common issues with transmissionvpn.

## 📋 Table of Contents

- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [VPN Connection Issues](#vpn-connection-issues)
- [Transmission Problems](#transmission-problems)
- [Network & Connectivity](#network--connectivity)
- [Performance Issues](#performance-issues)
- [Docker & Container Issues](#docker--container-issues)
- [File Permissions](#file-permissions)
- [Security & Privacy](#security--privacy)
- [Advanced Debugging](#advanced-debugging)

## Quick Diagnostic Commands

Start troubleshooting with these commands:

```bash
# Check container status
docker ps | grep transmissionvpn

# View container logs
docker logs transmissionvpn

# Check if VPN is working
docker exec transmissionvpn curl ifconfig.me

# Test internal connectivity
docker exec transmissionvpn ping 8.8.8.8

# Check Transmission status
curl -s http://localhost:9091/transmission/web/ | head -5
```

## VPN Connection Issues

### 🚫 Container Exits with VPN Connection Error

**Symptoms:**

- Container starts but exits after a few seconds
- Logs show VPN connection failures

**Common Causes & Solutions:**

1. **Incorrect VPN Credentials:**

```bash
# Check your environment variables
docker exec transmissionvpn env | grep VPN

# Verify credentials are correct
# For file-based auth, check credentials.txt exists and has correct format
docker exec transmissionvpn cat /config/openvpn/credentials.txt
```

2. **Wrong VPN Configuration Path:**

```bash
# Verify config file exists
docker exec transmissionvpn ls -la /config/openvpn/
docker exec transmissionvpn ls -la /config/wireguard/

# Check file permissions
docker exec transmissionvpn stat /config/openvpn/your-config.ovpn
```

3. **Missing Required Capabilities:**

```yaml
# Ensure your docker-compose.yml has:
cap_add:
  - NET_ADMIN
  - SYS_MODULE  # Required for WireGuard
devices:
  - /dev/net/tun:/dev/net/tun
```

4. **Firewall/Network Restrictions:**

```bash
# Test if VPN ports are accessible
telnet your-vpn-server.com 1194  # OpenVPN
telnet your-vpn-server.com 51820  # WireGuard

# Check if container can resolve DNS
docker exec transmissionvpn nslookup google.com
```

### 🔄 VPN Connects but Disconnects Frequently

**Diagnosis:**

```bash
# Monitor VPN connection stability
docker logs -f transmissionvpn | grep -i "vpn\|connect\|disconnect"

# Check for network timeouts
docker exec transmissionvpn ping -c 10 your-vpn-server.com
```

**Solutions:**
1. **Add Connection Keep-alive:**

```bash
# Add to your OpenVPN config
echo "keepalive 10 60" >> /config/openvpn/your-config.ovpn
echo "persist-tun" >> /config/openvpn/your-config.ovpn
echo "persist-key" >> /config/openvpn/your-config.ovpn
```

2. **Switch VPN Server:**

- Try a different server location
- Use UDP instead of TCP for OpenVPN
- Test with WireGuard if using OpenVPN

### 🌐 VPN Connection Shows Different IP

**Verify VPN is Working:**

```bash
# Check external IP
docker exec transmissionvpn curl ifconfig.me

# Compare with your real IP
curl ifconfig.me

# Test DNS leak
docker exec transmissionvpn nslookup google.com
```

## Transmission Problems

### 🚪 Cannot Access Transmission Web UI

**Symptoms:**

- Browser shows "connection refused" on port 9091
- Transmission interface doesn't load

**Diagnosis:**
```bash
# Check if Transmission is running
docker exec transmissionvpn ps aux | grep transmission

# Check port binding
docker port transmissionvpn

# Test local connectivity
curl -s http://localhost:9091/transmission/web/
```

**Solutions:**

1. **Port Mapping Issues:**

```yaml
# Ensure correct port mapping in docker-compose.yml
ports:
  - "9091:9091"
```

2. **RPC Whitelist Problems:**

```bash
# Check RPC settings
docker exec transmissionvpn cat /config/settings.json | grep rpc

# Temporarily disable whitelist for testing
# Edit settings.json: "rpc-whitelist-enabled": false
```

3. **Authentication Issues:**

```bash
# Check if RPC authentication is enabled
docker exec transmissionvpn grep rpc-authentication /config/settings.json

# Reset credentials if needed
# Set TRANSMISSION_RPC_USERNAME and TRANSMISSION_RPC_PASSWORD
```

### ⬇️ Downloads Not Starting/Slow

**Diagnosis:**

```bash
# Check Transmission daemon status
docker exec transmissionvpn transmission-remote -n user:pass -l

# Check peer connections
docker exec transmissionvpn netstat -an | grep 51413

# Monitor download activity
docker logs -f transmissionvpn | grep -i "download\|peer\|seed"
```

**Solutions:**

1. **Port Forwarding Issues:**

```yaml
# Add port forwarding to docker-compose.yml
environment:
  - TRANSMISSION_PEER_PORT=51413
  - ADDITIONAL_PORTS=51413
ports:
  - "51413:51413"
  - "51413:51413/udp"
```

2. **VPN Provider Port Restrictions:**

```bash
# Some VPN providers block P2P ports
# Try different ports or enable provider's port forwarding
```

3. **Bandwidth Limitations:**

```yaml
# Add bandwidth controls
environment:
  - TRANSMISSION_SPEED_LIMIT_DOWN_ENABLED=true
  - TRANSMISSION_SPEED_LIMIT_DOWN=1000  # KB/s
  - TRANSMISSION_SPEED_LIMIT_UP_ENABLED=true
  - TRANSMISSION_SPEED_LIMIT_UP=100     # KB/s
```

## Network & Connectivity

### 🔗 DNS Resolution Problems

**Symptoms:**

- Cannot resolve domain names
- Trackers not connecting

**Diagnosis:**

```bash
# Test DNS resolution
docker exec transmissionvpn nslookup google.com
docker exec transmissionvpn nslookup tracker.example.com

# Check current DNS servers
docker exec transmissionvpn cat /etc/resolv.conf
```

**Solutions:**

1. **Custom DNS Servers:**

```yaml
# Add custom DNS to docker-compose.yml
dns:
  - 8.8.8.8
  - 8.8.4.4
  - 1.1.1.1
```

2. **VPN Provider DNS:**

```bash
# Use VPN provider's DNS servers
# Check your VPN provider documentation for recommended DNS
```

### 🌐 Local Network Access Issues

**Symptoms:**

- Cannot access NAS/local services
- LAN devices unreachable

**Diagnosis:**

```bash
# Check routing table
docker exec transmissionvpn ip route

# Test LAN connectivity
docker exec transmissionvpn ping 192.168.1.1  # Your router
```

**Solutions:**

1. **Configure LAN Network:**

```yaml
environment:
  - LAN_NETWORK=192.168.1.0/24  # Adjust to your network
```

2. **Multiple LAN Networks:**

```yaml
environment:
  - LAN_NETWORK=192.168.1.0/24,10.0.0.0/8,172.16.0.0/12
```

## Performance Issues

### 🐌 Slow Download Speeds

**Diagnosis:**

```bash
# Test VPN speed
docker exec transmissionvpn curl -o /dev/null -s -w "Downloaded at %{speed_download} bytes/sec\n" http://speedtest.tele2.net/100MB.zip

# Check CPU/Memory usage
docker stats transmissionvpn

# Monitor network usage
docker exec transmissionvpn iftop -i tun0
```

**Solutions:**

1. **Optimize Transmission Settings:**
```yaml
environment:
  - TRANSMISSION_PEER_LIMIT_GLOBAL=200
  - TRANSMISSION_PEER_LIMIT_PER_TORRENT=50
  - TRANSMISSION_UPLOAD_SLOTS_PER_TORRENT=8
```

2. **VPN Optimization:**
- Switch to WireGuard if using OpenVPN
- Try different VPN server locations
- Use UDP protocol for OpenVPN

3. **Container Resources:**
```yaml
# Add resource limits
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '1.0'
```

### 💾 High Memory Usage

**Diagnosis:**
```bash
# Check memory usage
docker exec transmissionvpn free -h
docker exec transmissionvpn top

# Check for memory leaks
docker stats --no-stream transmissionvpn
```

**Solutions:**

1. **Limit Cache Size:**
```yaml
environment:
  - TRANSMISSION_CACHE_SIZE_MB=32  # Default is 4MB
```

2. **Reduce Active Torrents:**
```yaml
environment:
  - TRANSMISSION_DOWNLOAD_QUEUE_SIZE=5
  - TRANSMISSION_SEED_QUEUE_SIZE=10
```

## Docker & Container Issues

### 🐳 Container Won't Start

**Diagnosis:**
```bash
# Check container status
docker ps -a | grep transmissionvpn

# View startup logs
docker logs transmissionvpn

# Check for port conflicts
netstat -tulpn | grep :9091
```

**Common Solutions:**

1. **Port Conflicts:**
```bash
# Find process using port 9091
sudo lsof -i :9091

# Kill conflicting process or change port
```

2. **Permission Issues:**
```bash
# Fix ownership of config directory
sudo chown -R 1000:1000 ./config

# Check PUID/PGID settings
```

3. **Volume Mount Problems:**
```bash
# Verify volume paths exist
ls -la ./config ./downloads ./watch

# Check mount points
docker inspect transmissionvpn | grep -A 10 Mounts
```

### 🔄 Container Restarts Constantly

**Diagnosis:**
```bash
# Check restart count
docker ps | grep transmissionvpn

# Review recent logs
docker logs --tail 100 transmissionvpn

# Check system resources
df -h  # Disk space
free -h  # Memory
```

**Solutions:**

1. **Health Check Issues:**
```bash
# Test health check manually
docker exec transmissionvpn curl -f http://localhost:9091/transmission/web/

# Disable health check temporarily
# Remove healthcheck from docker-compose.yml
```

2. **Resource Exhaustion:**
```bash
# Clear log files
docker exec transmissionvpn find /var/log -name "*.log" -exec truncate -s 0 {} \;

# Clean up incomplete downloads
docker exec transmissionvpn rm -rf /downloads/incomplete/*
```

## File Permissions

### 📁 Permission Denied Errors

**Symptoms:**
- Cannot write to download directory
- Configuration changes not saved

**Diagnosis:**
```bash
# Check file ownership
ls -la config/ downloads/ watch/

# Check PUID/PGID in container
docker exec transmissionvpn id

# Check file permissions in container
docker exec transmissionvpn ls -la /config /downloads /watch
```

**Solutions:**

1. **Fix Directory Ownership:**
```bash
# Set correct ownership (use your PUID/PGID)
sudo chown -R 1000:1000 config downloads watch

# Set proper permissions
chmod -R 755 config downloads watch
```

2. **Configure PUID/PGID:**
```yaml
environment:
  - PUID=1000  # Your user ID
  - PGID=1000  # Your group ID
```

3. **Check User ID:**
```bash
# Find your user/group ID
id $USER
```

## Security & Privacy

### 🕵️ IP/DNS Leak Detection

**Test for Leaks:**
```bash
# Check external IP (should be VPN IP)
docker exec transmissionvpn curl ifconfig.me

# DNS leak test
docker exec transmissionvpn curl https://www.dnsleaktest.com/

# WebRTC leak test (if using web browser)
# Visit: https://browserleaks.com/webrtc
```

**Solutions:**

1. **Enable Kill Switch:**
```yaml
environment:
  - KILL_SWITCH=on
```

2. **Custom DNS:**
```yaml
dns:
  - 9.9.9.9   # Quad9
  - 149.112.112.112
```

3. **Disable IPv6:**
```yaml
sysctls:
  - net.ipv6.conf.all.disable_ipv6=1
```

### 🔒 VPN Kill Switch Not Working

**Test Kill Switch:**
```bash
# Temporarily disconnect VPN and test
docker exec transmissionvpn pkill openvpn  # or wg-quick down wg0

# Check if internet access is blocked
docker exec transmissionvpn curl --connect-timeout 5 ifconfig.me
```

**Solutions:**

1. **Verify iptables Rules:**
```bash
# Check firewall rules
docker exec transmissionvpn iptables -L -n
```

2. **Manual Kill Switch Test:**
```bash
# Stop VPN manually and verify no connectivity
docker exec transmissionvpn systemctl stop openvpn
docker exec transmissionvpn ping -c 3 8.8.8.8  # Should fail
```

## Advanced Debugging

### 📊 Enable Debug Logging

**Enable Verbose Logging:**
```yaml
environment:
  - LOG_TO_STDOUT=true
  - VPN_DEBUG=true
```

**Monitor Real-time Logs:**
```bash
# Follow all logs
docker logs -f transmissionvpn

# Filter specific components
docker logs -f transmissionvpn 2>&1 | grep -i "vpn\|transmission\|error"
```

### 🔍 Network Traffic Analysis

**Monitor Network Traffic:**
```bash
# Install network tools in container
docker exec transmissionvpn apt-get update && apt-get install -y tcpdump iftop

# Monitor VPN interface
docker exec transmissionvpn tcpdump -i tun0

# Monitor all interfaces
docker exec transmissionvpn iftop
```

### 🧪 Test Environment

**Create Test Setup:**
```yaml
# Minimal test configuration
version: "3.8"
services:
  transmissionvpn-test:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn-test
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/test.ovpn
      - VPN_USER=testuser
      - VPN_PASS=testpass
      - LOG_TO_STDOUT=true
    volumes:
      - ./test-config:/config
    ports:
      - "9092:9091"  # Different port to avoid conflicts
```

### 🔧 Manual Configuration Override

**Direct Container Access:**
```bash
# Enter container for manual debugging
docker exec -it transmissionvpn bash

# Manually start components
# Stop automatic services first, then:
openvpn --config /config/openvpn/your-config.ovpn
# or
wg-quick up /config/wireguard/your-config.conf

# Start Transmission manually
transmission-daemon --foreground --config-dir /config
```

### 📝 Collect Debug Information

**Gather System Information:**
```bash
#!/bin/bash
# Debug info collection script

echo "=== Container Status ==="
docker ps | grep transmissionvpn

echo "=== Container Logs (last 50 lines) ==="
docker logs --tail 50 transmissionvpn

echo "=== Network Configuration ==="
docker exec transmissionvpn ip addr show
docker exec transmissionvpn ip route

echo "=== VPN Status ==="
docker exec transmissionvpn ps aux | grep -E "(openvpn|wg-quick)"

echo "=== Transmission Status ==="
docker exec transmissionvpn ps aux | grep transmission

echo "=== File Permissions ==="
docker exec transmissionvpn ls -la /config /downloads /watch

echo "=== External IP ==="
docker exec transmissionvpn curl -s ifconfig.me

echo "=== DNS Resolution ==="
docker exec transmissionvpn nslookup google.com
```

## Getting Help

If you're still having issues after trying these solutions:

1. **Search Existing Issues:** Check [GitHub Issues](https://github.com/magicalyak/transmissionvpn/issues)
2. **Create Bug Report:** Use our [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml)
3. **Join Discussions:** Visit [GitHub Discussions](https://github.com/magicalyak/transmissionvpn/discussions)
4. **Check Documentation:** Review [README.md](../README.md) and [EXAMPLES.md](../EXAMPLES.md)

When reporting issues, please include:
- Container logs (`docker logs transmissionvpn`)
- Your docker-compose.yml (remove sensitive info)
- Host OS and Docker version
- VPN provider and configuration type
- Steps to reproduce the issue 
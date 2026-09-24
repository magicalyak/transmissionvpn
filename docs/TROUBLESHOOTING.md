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
- [Sonarr/Radarr Integration Issues](#sonarr-radarr-integration-issues)
- [Web UI Issues](#web-ui-issues)
- [Performance Problems](#performance-problems)

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

### ⏳ Stuck on "Waiting for initial VPN setup to complete..."

**Symptoms:**

- `[VPN-MONITOR] Waiting for initial VPN setup to complete...` repeats
  indefinitely
- The web UI on 9091 is unreachable
- The container keeps running rather than exiting

**Cause:**

VPN setup did not finish, so the monitor is still waiting for it. Since
v4.1.2-r8 the monitor stops repeating itself after about a minute and prints
the actual error from the setup log, so read the log rather than the waiting
message:

```bash
docker logs transmissionvpn 2>&1 | grep -A5 '\[ERROR\]'
docker exec transmissionvpn cat /tmp/vpn-setup.log
```

The usual causes are the ones under
[Container Exits with VPN Connection Error](#-container-exits-with-vpn-connection-error):
a config file the container cannot see, bad credentials, or missing
`NET_ADMIN`.

**Why the web UI is also down:** as of v4.1.2-r7 a container whose VPN setup
aborts fails closed — everything except loopback is dropped, including port
9091. This is intended. Before r7 a failed setup left the firewall wide open
with Transmission already listening, which leaked traffic outside the tunnel.
A dark web UI after an upgrade to r7 or later is almost always a
pre-existing configuration fault that used to fail silently, not a regression.

**If the config path is the problem,** note that a relative bind mount in
`docker-compose.yml` resolves against the directory holding the compose file,
not your shell's working directory. `./config:/config` in
`~/docker/docker-compose.yml` mounts `~/docker/config`, so a config sitting in
`~/docker/transmissionvpn/config/openvpn/` is never seen. The container creates
`/config/openvpn` when it is absent, so a wrong mount shows up as an *empty*
directory rather than a missing one:

```bash
# What the container actually sees
docker exec transmissionvpn ls -la /config/openvpn /config/wireguard
```

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

### Container exits with code 1 after the VPN stops passing traffic

This is deliberate. With `AUTO_RESTART_VPN=true`, `vpn-monitor` restarts a failed tunnel up to
`MAX_RESTART_ATTEMPTS` times. If it is still dead after that, the container stops with exit code 1 so your
restart policy (or Kubernetes) starts a fresh one, which re-runs VPN setup and PIA port forwarding from
scratch. The log line just before it stops says so:

```
[VPN-MONITOR] ERROR: VPN still down after 3 restart attempts. Stopping the container (exit code 1) ...
```

Before `v4.1.3-r2` the monitor logged "manual intervention required" every ~35 seconds forever instead. The
web UI kept answering, so nothing outside the container noticed. If the container keeps exiting, the fault
is in the tunnel itself. Look at `/tmp/openvpn.log` or `/tmp/vpn-setup.log` from the run before the exit,
and check that the provider's servers in your config still exist and that `compress`/`comp-lzo` match what
the provider expects. Set `EXIT_ON_MAX_RESTARTS=false` to get the old behaviour back. Without a restart policy,
Docker leaves the container stopped.

"Dead" means no reply through the tunnel from `HEALTH_CHECK_HOST` or `HEALTH_CHECK_HOST_FALLBACK`,
three packets each. An interface that is up with an address does not count as working.

**Reproducing a dead tunnel locally.** With a working VPN connection, drop everything leaving through the tunnel:

```bash
docker exec transmissionvpn iptables -I OUTPUT -o tun0 -j DROP      # wg0 for WireGuard
# Within one or two checks:
docker exec transmissionvpn cat /tmp/vpn_tunnel_state                # connected=0
curl -s localhost:9099/metrics | grep -E '^transmissionvpn_(vpn_connected|vpn_interface_up|healthy) '
# transmissionvpn_vpn_connected 0, transmissionvpn_vpn_interface_up 1, transmissionvpn_healthy 0
docker exec transmissionvpn iptables -D OUTPUT -o tun0 -j DROP      # undo
```

That rule lives in the filter table's OUTPUT chain, which `vpn-monitor` rebuilds when it engages the kill
switch after `VPN_MAX_FAILURES` failed checks, so it only holds the tunnel dead for about that long. To follow
it through restarts to the container exit, put the rule in the `raw` table instead, which neither the kill
switch nor VPN setup flushes:

```bash
docker exec transmissionvpn iptables -t raw -I OUTPUT -o tun0 -j DROP
docker exec transmissionvpn iptables -t raw -D OUTPUT -o tun0 -j DROP   # undo
```

With `AUTO_RESTART_VPN=true` and the defaults, the exit comes 15 to 20 minutes later. Setting
`VPN_CHECK_INTERVAL=5 VPN_MAX_FAILURES=1 MAX_RESTART_ATTEMPTS=1 RESTART_COOLDOWN_SECONDS=20` gets there in
about a minute.

Without VPN credentials, a dummy interface does the same job. VPN setup fails closed, but `vpn-monitor` only
needs the interface and the setup flag:

```bash
docker run -d --name tvpn-test --cap-add NET_ADMIN -e VPN_CLIENT=openvpn -e METRICS_ENABLED=true \
  -e AUTO_RESTART_VPN=true -e VPN_CHECK_INTERVAL=5 -e VPN_MAX_FAILURES=1 -e VPN_INITIAL_DELAY=1 \
  -e MAX_RESTART_ATTEMPTS=1 -e RESTART_COOLDOWN_SECONDS=20 -e CHECK_DNS=false -e CHECK_EXTERNAL_IP=false \
  magicalyak/transmissionvpn:latest
docker exec tvpn-test sh -c 'ip link add tun0 type dummy && ip addr add 10.25.18.69/24 dev tun0 &&
  ip link set tun0 up && echo tun0 > /tmp/vpn_interface_name && touch /tmp/vpn_setup_complete'
docker wait tvpn-test    # prints 1 after roughly 30 seconds
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

## Sonarr/Radarr Integration Issues

### 📂 "Directory does not appear to exist inside the container"

**Symptoms:**

- Sonarr/Radarr shows error: "download client transmission places downloads in /downloads/complete/Series but this directory does not appear to exist inside the container"
- Downloads complete but Sonarr/Radarr can't find them

**Root Cause:**
Directory structure mismatch between haugene/docker-transmission-openvpn and LinuxServer.io transmission base image:

| Container | Complete Downloads | Incomplete Downloads |
|-----------|-------------------|---------------------|
| **haugene/docker-transmission-openvpn** | `/data/completed/` | `/data/incomplete/` |
| **LinuxServer.io transmission** | `/downloads/complete/` | `/downloads/incomplete/` |

**Automatic Fix (v4.0.6-2+):**

**transmissionvpn** now automatically creates compatibility symlinks during startup:

- `/downloads/completed` → `/downloads/complete`
- `/data` → `/downloads`

This should **automatically resolve** the directory mismatch for most users! Check if the symlinks are working:

```bash
# Verify automatic compatibility symlinks
docker exec transmissionvpn ls -la /downloads/
docker exec transmissionvpn ls -la / | grep "data ->"

# Test both paths work
docker exec transmissionvpn ls -la /downloads/complete/
docker exec transmissionvpn ls -la /downloads/completed/  # Should show same content
```

**Manual Fix - Option 1 (if automatic doesn't work):**

Update your Sonarr/Radarr download client settings:

1. **Download Client Settings:**

   ```
   Host: transmissionvpn
   Port: 9091
   Category: (leave empty or set to tv/movies)
   Directory: (leave empty)
   ```

2. **Remote Path Mappings:**

   ```
   Host: transmissionvpn
   Remote Path: /downloads/
   Local Path: /media/downloads/  (your host path)
   ```

3. **Volume Mapping (both containers):**

   ```yaml
   transmissionvpn:
     volumes:
       - /media/downloads:/downloads
   
   sonarr:
     volumes:
       - /media/downloads:/media/downloads
   ```

**Quick Fix - Option 2 (haugene compatibility):**

Change your transmissionvpn volume mapping:

```yaml
transmissionvpn:
  volumes:
    - ./config:/config
    - /media/downloads:/downloads/completed    # Map host to completed subdirectory
    - /media/incomplete:/downloads/incomplete
    - ./watch:/watch
```

**Verification:**

```bash
# Check if directories exist in container
docker exec transmissionvpn ls -la /downloads/

# Check if Sonarr can see the path  
docker exec sonarr ls -la /media/downloads/
```

### 🔗 Container Communication Issues

**Symptoms:**

- Sonarr/Radarr can't connect to Transmission
- "Unable to connect to Transmission" errors

**Solutions:**

1. **Network Configuration:**

   ```yaml
   # Ensure containers can communicate
   version: "3.8"
   services:
     transmissionvpn:
       container_name: transmissionvpn  # Use this name in Sonarr/Radarr
       networks:
         - media
     
     sonarr:
       container_name: sonarr
       networks:
         - media
   
   networks:
     media:
       driver: bridge
   ```

2. **Firewall/LAN Network:**

   ```yaml
   transmissionvpn:
     environment:
       - LAN_NETWORK=172.18.0.0/16  # Docker network range
   ```

3. **Test Connection:**

   ```bash
   # From Sonarr container to Transmission
   docker exec sonarr curl -f http://transmissionvpn:9091
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

## Alternative Web UI Issues

### 🎨 Web UI Auto-Download Failed

**Symptoms:**

- Container logs show web UI download errors
- Default Transmission web UI appears instead of chosen alternative
- `/config/web-ui/` directory is empty or missing files

**Diagnosis:**

```bash
# Check if web UI was downloaded
docker exec transmissionvpn ls -la /config/web-ui/

# Check current UI setting
docker exec transmissionvpn cat /config/web-ui/.current-ui

# Check download logs
docker logs transmissionvpn | grep -i "web.*ui\|download\|flood\|kettu"

# Check TRANSMISSION_WEB_HOME setting
docker exec transmissionvpn printenv | grep TRANSMISSION_WEB
```

**Solutions:**

1. **Network/Download Issues:**

```bash
# Test internet connectivity in container
docker exec transmissionvpn curl -I https://github.com

# Force re-download by removing cached UI
docker exec transmissionvpn rm -rf /config/web-ui/flood
docker restart transmissionvpn
```

2. **Supported UI Names:**

```yaml
# Ensure you're using a supported UI name
environment:
  - TRANSMISSION_WEB_UI_AUTO=flood                    # ✅ Correct
  - TRANSMISSION_WEB_UI_AUTO=kettu                    # ✅ Correct  
  - TRANSMISSION_WEB_UI_AUTO=combustion               # ✅ Correct
  - TRANSMISSION_WEB_UI_AUTO=transmission-web-control # ✅ Correct
  - TRANSMISSION_WEB_UI_AUTO=invalid-ui-name          # ❌ Will fail
```

3. **Permissions Issues:**

```bash
# Check directory permissions
docker exec transmissionvpn ls -la /config/

# Fix permissions if needed
sudo chown -R 1000:1000 ./config/web-ui/
```

### 🔄 Switching Between Web UIs

**To change UI:**

```yaml
# Update docker-compose.yml
environment:
  - TRANSMISSION_WEB_UI_AUTO=kettu  # Switch to Kettu

# Restart container
docker-compose restart transmissionvpn
```

**To force fresh download:**

```bash
# Remove cached UI files
docker exec transmissionvpn rm -rf /config/web-ui/flood
docker restart transmissionvpn
```

**To disable automatic UI:**

```yaml
environment:
  - TRANSMISSION_WEB_UI_AUTO=false  # Use default UI
```

### 📱 Web UI Not Loading Properly

**Symptoms:**

- Blank page or loading errors
- JavaScript errors in browser console
- UI appears but doesn't connect to Transmission

**Solutions:**

1. **Clear Browser Cache:**

```bash
# Hard refresh: Ctrl+F5 (Windows/Linux) or Cmd+Shift+R (Mac)
# Or clear browser cache completely
```

2. **Check Network Access:**

```bash
# Test if Transmission RPC is accessible
curl -f http://localhost:9091/transmission/rpc/

# Check from within container
docker exec transmissionvpn curl -f http://localhost:9091/transmission/rpc/
```

3. **Verify UI Files:**

```bash
# Check if index.html exists and is valid
docker exec transmissionvpn ls -la /config/web-ui/flood/index.html
docker exec transmissionvpn head -10 /config/web-ui/flood/index.html
```

### 🔧 Manual Web UI Setup

If automatic download fails, you can manually install UIs:

```bash
# Download and extract manually
mkdir -p ./config/web-ui/flood
cd ./config/web-ui/flood
curl -OL https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.zip
unzip flood-for-transmission.zip --strip-components=1
rm flood-for-transmission.zip
```

```yaml
# Use manual installation
environment:
  - TRANSMISSION_WEB_HOME=/config/web-ui/flood
  # Don't set TRANSMISSION_WEB_UI_AUTO when using manual setup
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

### 🔗 `127.0.0.11#53: connection refused`

**Symptoms:**

- `nslookup` inside the container fails with `;; connection timed out` or
  `connection refused` against `127.0.0.11#53`
- The address is one you never configured
- Name resolution works from the host and from other containers

**Cause:**

`127.0.0.11` is Docker's embedded DNS resolver, used whenever a container is on
a user-defined network. It does not really listen on port 53 — Docker installs
NAT rules inside the container's own network namespace that redirect
`127.0.0.11:53` to the ephemeral port the resolver actually listens on.

Before starting the tunnel, `vpn-setup.sh` runs `iptables -t nat -F` to clear
any leftover state from a previous run and to avoid wiping rules that a
provider's `PostUp` hook installs. That flush also removes Docker's redirect,
so `127.0.0.11:53` stops answering.

On a **successful** start this does not matter: once the tunnel is up the
container rewrites `/etc/resolv.conf` to `NAME_SERVERS` (default
`8.8.8.8,1.1.1.1`), which is queried through the tunnel, and `127.0.0.11` is
never consulted again.

Seeing this error therefore means **the tunnel never came up**. The rewrite
happens only after the tunnel succeeds, so the container is still pointed at a
resolver that the flush disabled. The DNS error is a symptom; the VPN failure
is the fault.

**Diagnosis:**

```bash
# The real error is here. Since v4.1.2-r7 it is in the container log too.
docker logs transmissionvpn 2>&1 | grep -A5 '\[ERROR\]'
docker exec transmissionvpn cat /tmp/vpn-setup.log
```

Fix whatever that reports — a missing or unreadable config, bad credentials, a
failed handshake — and the DNS error goes with it.

**Note on resolving other containers by name:** because `/etc/resolv.conf` is
moved off `127.0.0.11`, this container cannot resolve other containers by name
(`sonarr`, `radarr`) even when everything is working. That is deliberate: using
Docker's resolver would send every lookup out through the host, outside the
tunnel, which is a DNS leak. If you need to reach another container, either
give it a static address and use that, or run it inside this container's
network namespace with `network_mode: "service:transmissionvpn"`, in which case
it is reachable on `127.0.0.1` and no DNS is involved.

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

## 📺 Sonarr/Radarr Integration

- **Symptom:** Sonarr/Radarr can't connect to Transmission.
- **Symptom:** Sonarr/Radarr shows error: "Unable to communicate with Transmission."
- **Symptom:** Downloads are not being imported automatically.

### ✅ Solution

1. **Network Configuration:**

   ```yaml
   # Ensure containers can communicate
   version: "3.8"
   services:
     transmissionvpn:
       container_name: transmissionvpn  # Use this name in Sonarr/Radarr
       networks:
         - media
     
     sonarr:
       container_name: sonarr
       networks:
         - media
   
   networks:
     media:
       driver: bridge
   ```

2. **Firewall/LAN Network:**

   ```yaml
   transmissionvpn:
     environment:
       - LAN_NETWORK=172.18.0.0/16  # Docker network range
   ```

3. **Test Connection:**

   ```bash
   # From Sonarr container to Transmission
   docker exec sonarr curl -f http://transmissionvpn:9091
   ```

## 🐢 Slow Speeds or High CPU Usage

- **Symptom:** Download/upload speeds are much lower than expected.
- **Symptom:** The container is using a high amount of CPU.

### ✅ Solution

1. **Optimize Transmission Settings:**

    - In `settings.json` or via environment variables, adjust:
      - `cache-size-mb`: `16` or `32` can help with I/O.
      - `peer-limit-global`: Lower if you have many torrents.
      - `peer-limit-per-torrent`: Lower to reduce CPU usage.

2. **VPN Optimization:**

    - Switch to WireGuard if using OpenVPN; it's often faster.
    - Try different VPN servers or protocols.
    - Ensure your VPN provider is not throttling your connection.

3. **Container Resources:**

    - If running on a low-power device, limit the number of active torrents.
    - Use `docker stats` to monitor resource usage.

## 🧠 High Memory Usage

- **Symptom:** The container is consuming a large amount of RAM.
- **Symptom:** `docker stats` shows high memory usage.

### ✅ Solution

1. **Limit Cache Size:**

    - Set `TRANSMISSION_CACHE_SIZE_MB` to a lower value (e.g., `4`).

2. **Reduce Active Torrents:**

    - Limit the number of simultaneous downloads/uploads.

## 🔑 Permissions & File Access

- **Symptom:** "Permission denied" errors in the logs.
- **Symptom:** Cannot write to download directories.
- **Symptom:** `settings.json` is not being saved.

### ✅ Solution

1. **Fix Directory Ownership:**

    - Ensure the user running the container (`PUID`/`PGID`) owns the config and download directories.
    - `sudo chown -R 1000:1000 ./config ./downloads`

2. **Configure PUID/PGID:**

    - Set `PUID` and `PGID` in your `.env` file to match your user's ID.
    - Use `id $(whoami)` to find your user ID.

3. **Check User ID:**

    - Verify the user ID inside the container.
    - `docker exec -it transmissionvpn id`

## 🛡️ IP Leaks & Kill Switch

- **Symptom:** My real IP address is being exposed.
- **Symptom:** The kill switch is not working as expected.

### ✅ Solution

1. **Enable Kill Switch:**

    - Ensure `ENABLE_KILLSWITCH` is set to `true` (it is by default).

2. **Custom DNS:**

    - Use a trusted DNS provider via the `NAME_SERVERS` variable.

3. **Disable IPv6:**

    - If you don't use IPv6, you can disable it in the container for added security.
    - Set `DISABLE_IPV6` to `true`.

## 🐛 Other Common Issues

### Container Restarts Randomly

1. **Health Check Issues:**

    - The health check might be failing, causing restarts. Check the logs for `unhealthy`.
    - Increase the `HEALTH_CHECK_INTERVAL` if needed.

2. **Resource Exhaustion:**

    - Monitor CPU and memory usage with `docker stats`.
    - The container might be OOM-killed if it exceeds memory limits.

### Cannot Access Web UI

- **Symptom:** Blank page or loading errors.
- **Symptom:** "403: Forbidden" error.

1. **Clear Browser Cache:**

    - Your browser might have cached an old version of the UI.

2. **Check Network Access:**

    - Ensure you are on the same network as the Docker host.
    - Try accessing `http://<docker_host_ip>:9091`.

3. **Verify UI Files:**

    - If using a custom UI, ensure the files are correctly mounted.
    - Check the container logs for any UI-related errors.
 
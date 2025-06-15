# Rocky Server Upgrade Guide - v4.0.6-r11

## 🎯 **Current vs Recommended Configuration**

### **📋 Current Issues Found:**
1. **Mixed old/new environment variables**
2. **Typos in variable names**
3. **Missing new v4.0.6-r11 variables**
4. **Basic wrapper script without proper logging**
5. **Security: VPN credentials in plain text**

---

## **🔧 Step-by-Step Upgrade Process**

### **1. Backup Current Configuration**
```bash
# Backup existing files
sudo cp /opt/containerd/env/transmission.env /opt/containerd/env/transmission.env.backup
sudo cp /opt/containerd/start-transmission-wrapper.sh /opt/containerd/start-transmission-wrapper.sh.backup
```

### **2. Update Environment File**

**Current Issues:**
```bash
# ❌ OLD/DEPRECATED VARIABLES
EXPORTER_ENABLED=true                    # Remove
EXPORTER_PORT=9099                       # Remove
TRANSMISSION_EXPORTER_ENABLED=true      # Remove

# ❌ TYPOS
CHECK_DNS_LEAKS=true                     # Should be CHECK_DNS_LEAK
CHECK_IP_LEAKS=true                      # Should be CHECK_IP_LEAK

# ❌ MISSING VARIABLES
# METRICS_PORT=9099                      # Missing
# METRICS_INTERVAL=30                    # Missing
```

**✅ Updated `/opt/containerd/env/transmission.env`:**
```bash
# =====================================================
# TRANSMISSION VPN CONFIGURATION - v4.0.6-r11
# =====================================================

# ---- Container Image ----
TRANSMISSION_IMAGE=magicalyak/transmissionvpn:latest

# ---- VPN Configuration ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/atl-009.ovpn
VPN_USER=nhmacpjuhsrg
VPN_PASS=Fz2#At7U9Cw@1

# ---- System Settings ----
PUID=911
PGID=911
TZ=America/New_York

# ---- Network Configuration ----
LOCAL_NETWORK=10.1.0.0/16

# ---- Transmission Settings ----
TRANSMISSION_RPC_USERNAME=tom
TRANSMISSION_RPC_PASSWORD={92581b5860d7071c59c4a108baae6aa4fb10a909ZaJ2ba1/
TRANSMISSION_WEB_AUTO=flood
TRANSMISSION_DOWNLOAD_DIR=/downloads/completed
TRANSMISSION_INCOMPLETE_DIR=/downloads/incomplete
TRANSMISSION_WATCH_DIR=/watch

# ---- Custom Metrics Server (v4.0.6-r11) ----
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30

# ---- Health Check Settings ----
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true
HEALTH_CHECK_HOST=8.8.8.8

# ---- Optional Features ----
ENABLE_PRIVOXY=true
PRIVOXY_PORT=8119
DEBUG=false

# ---- Legacy Variables (Cleaned Up) ----
# Removed: OPENVPN_PROVIDER, OPENVPN_USERNAME, OPENVPN_PASSWORD, OPENVPN_CONFIG
# Removed: EXPORTER_ENABLED, EXPORTER_PORT, TRANSMISSION_EXPORTER_ENABLED
```

### **3. Update Wrapper Script**

**✅ Enhanced `/opt/containerd/start-transmission-wrapper.sh`:**
```bash
#!/bin/bash
set -e

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker is not running"
    exit 1
fi

# Load environment variables
if [[ -f /opt/containerd/env/transmission.env ]]; then
    source /opt/containerd/env/transmission.env
    log "INFO: Loaded environment variables"
else
    log "ERROR: Environment file not found"
    exit 1
fi

# Check for and remove existing containers
for CONTAINER in "transmission"; do
  if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
    log "INFO: Stopping and removing existing container $CONTAINER"
    docker stop "$CONTAINER" 2>/dev/null || true
    docker rm "$CONTAINER" 2>/dev/null || true
  fi
done

log "INFO: Starting transmission container with VPN"

# Use regular docker run instead of exec to allow proper cleanup
/usr/bin/docker run \
  --name transmission \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v /opt/transmission:/config \
  -v /var/nfs/Containers/transmission-ssd:/watch \
  -v /var/nfs/Containers/usenet-download:/downloads \
  -v /opt/transmission/flood-for-transmission:/web-ui:ro \
  -v /etc/localtime:/etc/localtime:ro \
  -p 9092:9091 \
  -p 51413:51413/tcp \
  -p 51413:51413/udp \
  -p 8119:8119/tcp \
  -p 9099:${METRICS_PORT}/tcp \
  --restart unless-stopped \
  -e VPN_CLIENT="$VPN_CLIENT" \
  -e VPN_USER="$VPN_USER" \
  -e VPN_PASS="$VPN_PASS" \
  -e VPN_CONFIG="$VPN_CONFIG" \
  -e LAN_NETWORK="$LOCAL_NETWORK" \
  -e TZ="$TZ" \
  -e TRANSMISSION_RPC_USERNAME="$TRANSMISSION_RPC_USERNAME" \
  -e TRANSMISSION_RPC_PASSWORD="$TRANSMISSION_RPC_PASSWORD" \
  -e TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true \
  -e TRANSMISSION_WEB_UI_AUTO="$TRANSMISSION_WEB_AUTO" \
  -e TRANSMISSION_DOWNLOAD_DIR="$TRANSMISSION_DOWNLOAD_DIR" \
  -e TRANSMISSION_INCOMPLETE_DIR="$TRANSMISSION_INCOMPLETE_DIR" \
  -e TRANSMISSION_WATCH_DIR="$TRANSMISSION_WATCH_DIR" \
  -e ENABLE_PRIVOXY=true \
  -e PRIVOXY_PORT=8119 \
  -e LOG_TO_STDOUT=true \
  -e PUID="$PUID" \
  -e PGID="$PGID" \
  -e METRICS_ENABLED="$METRICS_ENABLED" \
  -e METRICS_PORT="$METRICS_PORT" \
  -e METRICS_INTERVAL="$METRICS_INTERVAL" \
  -e CHECK_DNS_LEAK="$CHECK_DNS_LEAK" \
  -e CHECK_IP_LEAK="$CHECK_IP_LEAK" \
  -e HEALTH_CHECK_HOST="$HEALTH_CHECK_HOST" \
  -e DEBUG="$DEBUG" \
  -d \
  "$TRANSMISSION_IMAGE"

if [[ $? -eq 0 ]]; then
    log "INFO: Container started successfully"
    log "INFO: Web UI available at: http://rocky.gamull.com:9092"
    log "INFO: Metrics available at: http://rocky.gamull.com:9099/metrics"
    log "INFO: Health check available at: http://rocky.gamull.com:9099/health"
else
    log "ERROR: Failed to start container"
    exit 1
fi
```

### **4. Upgrade Commands**

```bash
# 1. Pull new image
docker pull magicalyak/transmissionvpn:v4.0.6-r11

# 2. Update environment file
sudo nano /opt/containerd/env/transmission.env
# (Copy the updated content from above)

# 3. Update wrapper script
sudo nano /opt/containerd/start-transmission-wrapper.sh
# (Copy the updated content from above)

# 4. Make wrapper executable
sudo chmod +x /opt/containerd/start-transmission-wrapper.sh

# 5. Restart service
sudo systemctl restart transmission

# 6. Check status
sudo systemctl status transmission
```

### **5. Verification**

```bash
# Test Web UI
curl -sf http://rocky.gamull.com:9092/transmission/web/

# Test new metrics endpoint
curl -s http://rocky.gamull.com:9099/metrics | head -10

# Test new health endpoint
curl -s http://rocky.gamull.com:9099/health

# Check container logs
docker logs transmission | tail -20

# Verify VPN is working
docker exec transmission curl -s ifconfig.me
```

---

## **🆚 Comparison: Current vs NZBGet Setup**

### **✅ NZBGet (Well Organized)**
- Clean environment file with sections
- Robust wrapper with logging
- Enhanced systemd service
- Security-conscious (credentials file)
- Professional structure

### **⚠️ Transmission (Needs Improvement)**
- Mixed old/new variables
- Basic wrapper without logging
- Inconsistent naming
- No error handling
- Security issues

### **🎯 After Upgrade: Transmission = NZBGet Quality**
- ✅ Clean organized environment file
- ✅ Robust wrapper with logging and error handling
- ✅ Consistent variable naming
- ✅ Professional structure
- ✅ Better security practices

---

## **🔒 Security Improvements**

### **Current Security Issues:**
1. **VPN credentials in plain text environment file**
2. **No credentials file option**

### **Future Security Enhancement (Optional):**
```bash
# Create credentials file (more secure)
sudo mkdir -p /opt/transmission/openvpn
echo "nhmacpjuhsrg" | sudo tee /opt/transmission/openvpn/credentials.txt
echo "Fz2#At7U9Cw@1" | sudo tee -a /opt/transmission/openvpn/credentials.txt
sudo chmod 600 /opt/transmission/openvpn/credentials.txt

# Update environment file
VPN_CREDENTIALS_FILE=/config/openvpn/credentials.txt
# Remove VPN_USER and VPN_PASS lines
```

---

## **📊 Expected Results After Upgrade**

### **✅ What Will Work:**
- ✅ **Reliable metrics** - No more hanging issues
- ✅ **Health endpoint** - `http://rocky.gamull.com:9099/health`
- ✅ **Better logging** - Timestamped logs with proper error handling
- ✅ **Clean configuration** - No more deprecated variables
- ✅ **Professional setup** - Matches nzbget quality

### **🌐 Endpoints:**
- **Web UI**: `http://rocky.gamull.com:9092/transmission/web/`
- **Metrics**: `http://rocky.gamull.com:9099/metrics`
- **Health**: `http://rocky.gamull.com:9099/health`

### **📈 Metrics Available:**
- `transmission_torrent_count`
- `transmission_active_torrents`
- `transmission_downloading_torrents`
- `transmission_seeding_torrents`
- `transmission_download_rate_bytes_per_second`
- `transmission_upload_rate_bytes_per_second`
- `transmission_session_downloaded_bytes`
- `transmission_session_uploaded_bytes`

---

## **🚨 Important Notes**

1. **Backup first** - Always backup before making changes
2. **Test thoroughly** - Verify all endpoints work after upgrade
3. **Monitor logs** - Check for any issues in the first few hours
4. **VPN credentials** - Consider moving to credentials file for better security
5. **Firewall** - Ensure port 9099 is still open for metrics

This upgrade will bring your transmission setup to the same professional level as your nzbget configuration! 🚀 
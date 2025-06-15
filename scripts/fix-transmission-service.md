# Fix Transmission SystemD Service Guide

## Step 1: Run Troubleshooting Script

First, copy the troubleshooting script to your server and run it:

```bash
# On rocky.gamull.com
scp scripts/troubleshoot-transmission-service.sh rocky.gamull.com:/tmp/
ssh rocky.gamull.com
sudo bash /tmp/troubleshoot-transmission-service.sh > /tmp/transmission-diagnosis.log 2>&1
cat /tmp/transmission-diagnosis.log
```

## Step 2: Check Current Service Status

```bash
# Check if service exists
sudo systemctl list-unit-files | grep transmission

# Check service status
sudo systemctl status transmission

# Check recent logs
sudo journalctl -u transmission --no-pager -n 50
```

## Step 3: Fix Common Issues

### Issue A: Missing Environment File

If `/opt/containerd/env/transmission.env` doesn't exist:

```bash
# Create directory
sudo mkdir -p /opt/containerd/env

# Copy sample and customize
sudo cp scripts/sample-transmission.env /opt/containerd/env/transmission.env
sudo nano /opt/containerd/env/transmission.env

# Set proper permissions
sudo chmod 600 /opt/containerd/env/transmission.env
sudo chown root:root /opt/containerd/env/transmission.env
```

**Required customizations in transmission.env:**
- Set your VPN credentials: `VPN_USERNAME` and `VPN_PASSWORD`
- Adjust paths: `DOWNLOADS_PATH`, `CONFIG_PATH`, `WATCH_PATH`
- Set timezone: `TZ=America/New_York`

### Issue B: Missing or Broken Wrapper Script

If `/opt/containerd/start-transmission-wrapper.sh` doesn't exist or has issues:

```bash
# Create directory
sudo mkdir -p /opt/containerd

# Copy sample and customize
sudo cp scripts/sample-wrapper-script.sh /opt/containerd/start-transmission-wrapper.sh

# Make executable
sudo chmod +x /opt/containerd/start-transmission-wrapper.sh
sudo chown root:root /opt/containerd/start-transmission-wrapper.sh

# Test the script manually
sudo /opt/containerd/start-transmission-wrapper.sh
```

### Issue C: Missing SystemD Service

If the systemd service doesn't exist:

```bash
# Copy service file
sudo cp scripts/sample-systemd-service.service /etc/systemd/system/transmission.service

# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable transmission
```

### Issue D: Port/Firewall Issues

If ports aren't accessible:

```bash
# Check if ports are listening locally
sudo netstat -tlnp | grep -E ':(9091|9099)'

# For UFW firewall
sudo ufw allow 9091/tcp
sudo ufw allow 9099/tcp
sudo ufw allow 51413

# For firewalld
sudo firewall-cmd --permanent --add-port=9091/tcp
sudo firewall-cmd --permanent --add-port=9099/tcp
sudo firewall-cmd --permanent --add-port=51413/tcp
sudo firewall-cmd --permanent --add-port=51413/udp
sudo firewall-cmd --reload
```

## Step 4: Start/Restart Service

```bash
# Start the service
sudo systemctl start transmission

# Check status
sudo systemctl status transmission

# Enable auto-start
sudo systemctl enable transmission

# View logs in real-time
sudo journalctl -u transmission -f
```

## Step 5: Verify Everything Works

```bash
# Test locally on the server
curl -I http://localhost:9091/transmission/web/
curl -s http://localhost:9099/metrics | head -10

# Check container status
sudo docker ps | grep transmission
sudo docker logs transmissionvpn --tail 20

# Test VPN connection
sudo docker exec transmissionvpn ip addr show tun0
sudo docker exec transmissionvpn curl -s ifconfig.me
```

## Step 6: Test External Access

From your local machine:
```bash
curl -I http://rocky.gamull.com:9091/transmission/web/
curl -s http://rocky.gamull.com:9099/metrics | head -10
```

## Common Issues and Solutions

### 1. "Failed to connect to rocky.gamull.com port 9091"
- **Cause**: Service not running or firewall blocking
- **Fix**: Check service status, open firewall ports

### 2. "Environment file not found"
- **Cause**: Missing `/opt/containerd/env/transmission.env`
- **Fix**: Create environment file with proper settings

### 3. "Permission denied"
- **Cause**: Wrapper script not executable
- **Fix**: `sudo chmod +x /opt/containerd/start-transmission-wrapper.sh`

### 4. "Container failed to start"
- **Cause**: Missing VPN credentials or invalid config
- **Fix**: Check environment file, verify VPN settings

### 5. "VPN not connecting"
- **Cause**: Incorrect VPN provider or config file
- **Fix**: Verify `VPN_PROVIDER=PRIVADOVPN` and `VPN_CONFIG=atl-009.ovpn`

## Monitoring Commands

```bash
# Service status
sudo systemctl status transmission

# Live logs
sudo journalctl -u transmission -f

# Container logs
sudo docker logs transmissionvpn -f

# Container stats
sudo docker stats transmissionvpn

# Health check
sudo docker exec transmissionvpn /healthcheck
```

## Useful Paths

- Service file: `/etc/systemd/system/transmission.service`
- Wrapper script: `/opt/containerd/start-transmission-wrapper.sh`
- Environment file: `/opt/containerd/env/transmission.env`
- Downloads: `/opt/transmission/downloads` (customizable)
- Config: `/opt/transmission/config` (customizable)
- Logs: `sudo journalctl -u transmission` 

# Get the new container IP after restart
CONTAINER_IP=$(docker inspect transmission --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Container IP: $CONTAINER_IP"

# Add manual iptables rule for port forwarding
sudo iptables -t nat -A DOCKER -p tcp --dport 9099 -j DNAT --to-destination $CONTAINER_IP:9099
sudo iptables -A DOCKER -d $CONTAINER_IP/32 ! -i docker0 -o docker0 -p tcp -m tcp --dport 9099 -j ACCEPT

# Test again
curl -s --connect-timeout 5 http://127.0.0.1:9099/metrics | head -3 
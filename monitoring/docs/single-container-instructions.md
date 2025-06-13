# Single Container Health Monitoring

**Simple solution for VPN and container health monitoring without additional containers.**

## 🎯 **Enable Built-in Health Metrics**

Your TransmissionVPN container already has health monitoring built-in!

### **Step 1: Enable Metrics**

Add this to your `/opt/containerd/env/transmission.env`:

```bash
# Enable built-in health metrics
METRICS_ENABLED=true

# Enable health checks
CHECK_DNS_LEAK=true
CHECK_IP_LEAK=true
HEALTH_CHECK_HOST=8.8.8.8
```

### **Step 2: Restart Container**

```bash
docker stop transmission
/opt/containerd/start-transmission-wrapper.sh
```

### **Step 3: Verify Health Monitoring**

```bash
# Run health check
docker exec transmission /root/healthcheck.sh

# Check if metrics file is created
docker exec transmission ls -la /tmp/metrics.txt

# View health logs
docker exec transmission tail -10 /tmp/healthcheck.log
```

## 📊 **What You Get**

### **Health Status via Command Line**
```bash
# Quick health check
docker exec transmission /root/healthcheck.sh

# Continuous monitoring
watch 'docker exec transmission /root/healthcheck.sh'

# View detailed logs
docker exec transmission tail -f /tmp/healthcheck.log
```

### **Available Health Checks**
- ✅ **Transmission Web UI** - Is the web interface responding?
- ✅ **VPN Interface** - Is the VPN interface (tun0/wg0) up?
- ✅ **VPN Connectivity** - Can we reach the internet through VPN?
- ✅ **DNS Resolution** - Is DNS working through VPN?
- ✅ **IP Leak Detection** - Are we leaking our real IP?
- ✅ **Resource Usage** - CPU, memory, disk usage

## 🔧 **Optional: HTTP Metrics Bridge**

If you want to access health metrics via HTTP (for Prometheus or monitoring tools):

### **Copy the bridge script to your server:**

```bash
# On your local machine
scp monitoring/scripts/health-bridge.py rocky.gamull.com:/opt/scripts/

# On rocky.gamull.com
chmod +x /opt/scripts/health-bridge.py
```

### **Run the bridge:**

```bash
# Start the health bridge (runs on port 8080)
python3 /opt/scripts/health-bridge.py

# Or run in background
nohup python3 /opt/scripts/health-bridge.py > /tmp/health-bridge.log 2>&1 &
```

### **Access metrics:**

```bash
# Prometheus format metrics
curl http://localhost:8080/metrics

# JSON health status
curl http://localhost:8080/health
```

## 🚨 **Troubleshooting**

### **No metrics file created?**

Check if METRICS_ENABLED is actually set:
```bash
docker exec transmission printenv | grep METRICS
```

If it shows `METRICS_ENABLED=false`, the environment variable wasn't loaded. Make sure:
1. You added it to the correct `.env` file
2. You restarted the container completely
3. Your startup script loads the environment file

### **VPN interface not found?**

This is normal if your VPN isn't currently connected. The health check will show:
```
[ERROR] VPN interface tun0 does not exist
```

To fix VPN connectivity, check your VPN configuration in the container.

### **Health check always fails?**

Check the detailed logs:
```bash
docker exec transmission cat /tmp/healthcheck.log
```

Common issues:
- VPN not connected (most common)
- DNS resolution issues
- Network connectivity problems

## 📋 **Summary**

**Minimal setup (no additional containers):**
1. Add `METRICS_ENABLED=true` to transmission.env
2. Restart container
3. Use `docker exec transmission /root/healthcheck.sh` for health status

**With HTTP access:**
1. Enable metrics (above)
2. Run `health-bridge.py` script
3. Access via `http://localhost:8080/metrics`

**No Docker Compose required!** ✅ 
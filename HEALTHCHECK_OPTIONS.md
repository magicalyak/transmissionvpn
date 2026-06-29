# TransmissionVPN Healthcheck Options

You're absolutely right that VPN status should be included in health checks! We now provide **three different healthcheck approaches** to suit different needs:

## 🎯 **Option 1: Smart Healthcheck (Recommended)**

**File**: `root/healthcheck-smart.sh`

**Best for**: Production environments where VPN is critical but you want intelligent handling of temporary VPN issues.

### Features:
- ✅ **Monitors both Transmission AND VPN**
- ✅ **Grace period for VPN reconnection** (default: 5 minutes)
- ✅ **Configurable VPN requirement** via environment variables
- ✅ **Detailed logging and metrics**
- ✅ **Smart failure handling**

### Configuration:
```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD", "/root/healthcheck-smart.sh"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s

# Environment variables
environment:
  - VPN_HEALTH_REQUIRED=true        # Default: true
  - VPN_GRACE_PERIOD=300            # Default: 300 seconds (5 minutes)
  - HEALTH_CHECK_HOST=1.1.1.1       # Default: 1.1.1.1 (Cloudflare; avoid 8.8.8.8 - it rate-limits ICMP)
  - HEALTH_CHECK_HOST_FALLBACK=9.9.9.9  # Default: 9.9.9.9; only fails if both hosts fail; empty to disable
  - METRICS_ENABLED=true            # Enable detailed metrics
```

### Behavior:
- **VPN Up + Transmission Up** → ✅ Healthy
- **VPN Down + Transmission Up** → ⏳ Healthy (within grace period) → ❌ Unhealthy (after grace period)
- **VPN Up + Transmission Down** → ❌ Unhealthy
- **VPN Down + Transmission Down** → ❌ Unhealthy

---

## 🔧 **Option 2: Transmission-Only Healthcheck**

**File**: `root/healthcheck-fixed.sh`

**Best for**: Development environments or when VPN issues shouldn't affect container orchestration.

### Features:
- ✅ **Monitors only Transmission**
- ✅ **VPN status is informational only**
- ✅ **Simple and reliable**
- ✅ **Never fails due to VPN issues**

### Configuration:
```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD", "/root/healthcheck-fixed.sh"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### Behavior:
- **Transmission Up** → ✅ Healthy (regardless of VPN status)
- **Transmission Down** → ❌ Unhealthy

---

## ⚡ **Option 3: Original Healthcheck**

**File**: `root/healthcheck.sh`

**Best for**: Strict environments where any VPN issue should immediately mark container as unhealthy.

### Features:
- ✅ **Monitors both Transmission AND VPN**
- ❌ **No grace period** - immediate failure on VPN issues
- ✅ **Comprehensive checks** (DNS leak, IP leak, etc.)

### Configuration:
```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD", "/root/healthcheck.sh"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### Behavior:
- **VPN Up + Transmission Up** → ✅ Healthy
- **VPN Down** → ❌ Immediately Unhealthy
- **Transmission Down** → ❌ Unhealthy

---

## 🚀 **Quick Setup Guide**

### For Most Users (Smart Healthcheck):
```yaml
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn
    # ... other config ...
    environment:
      # VPN and Transmission config
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - VPN_USER=your_username
      - VPN_PASS=your_password
      
      # Smart healthcheck config
      - VPN_HEALTH_REQUIRED=true
      - VPN_GRACE_PERIOD=300
      - METRICS_ENABLED=true
      
    healthcheck:
      test: ["CMD", "/root/healthcheck-smart.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

### For Development (Transmission-Only):
```yaml
healthcheck:
  test: ["CMD", "/root/healthcheck-fixed.sh"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### For Strict Monitoring (Original):
```yaml
healthcheck:
  test: ["CMD", "/root/healthcheck.sh"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

---

## 📊 **Comparison Table**

| Feature | Smart | Transmission-Only | Original |
|---------|-------|-------------------|----------|
| **Monitors Transmission** | ✅ | ✅ | ✅ |
| **Monitors VPN** | ✅ | ℹ️ Info only | ✅ |
| **VPN Grace Period** | ✅ Configurable | ❌ N/A | ❌ No |
| **Configurable Behavior** | ✅ Yes | ❌ No | ❌ No |
| **Detailed Metrics** | ✅ Yes | ✅ Basic | ✅ Yes |
| **Production Ready** | ✅ Yes | ⚠️ Limited | ⚠️ Strict |
| **Development Friendly** | ✅ Yes | ✅ Yes | ❌ No |

---

## 🔍 **Testing Your Healthcheck**

```bash
# Test the smart healthcheck
docker exec transmissionvpn /root/healthcheck-smart.sh
echo "Exit code: $?"

# Test transmission-only healthcheck
docker exec transmissionvpn /root/healthcheck-fixed.sh
echo "Exit code: $?"

# Test original healthcheck
docker exec transmissionvpn /root/healthcheck.sh
echo "Exit code: $?"

# Check health logs
docker exec transmissionvpn tail -10 /tmp/healthcheck.log

# Monitor health status
watch 'docker ps --format "table {{.Names}}\t{{.Status}}"'
```

---

## 🎯 **Recommendation**

**Use the Smart Healthcheck** (`healthcheck-smart.sh`) for most scenarios because:

1. **Includes VPN monitoring** (as you correctly pointed out)
2. **Handles temporary VPN issues gracefully** with configurable grace periods
3. **Prevents unnecessary container restarts** during brief VPN reconnections
4. **Provides detailed logging and metrics** for troubleshooting
5. **Configurable behavior** to suit different environments

The grace period is especially important because VPN connections can have brief interruptions during:
- VPN server maintenance
- Network connectivity issues
- Container restarts
- OpenVPN reconnection attempts

With the smart healthcheck, your container won't be marked unhealthy during these brief interruptions, but will fail if the VPN is down for an extended period (configurable via `VPN_GRACE_PERIOD`). 
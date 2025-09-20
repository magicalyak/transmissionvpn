# Kill Switch Verification Guide

This guide provides comprehensive methods to verify that the VPN kill switch is working correctly and protecting against IP leaks.

## Understanding the Kill Switch Implementation

The kill switch in transmissionvpn works through iptables firewall rules that:

1. **Default DROP policy** - All traffic is blocked by default on INPUT and FORWARD chains
2. **VPN-only OUTPUT** - Outbound traffic is only allowed through the VPN interface (tun0/wg0)
3. **Specific exceptions** - Only allows:
   - Loopback traffic (localhost)
   - Transmission UI access on port 9091 via eth0
   - Initial VPN server connection
   - LAN network access (if configured)
   - Established/related connections

## Verification Methods

### Method 1: Basic Container Inspection

Check the current iptables rules inside the container:

```bash
# Enter the container
docker exec -it transmission sh

# View all iptables rules
iptables -L -v -n

# Check default policies (should show DROP for INPUT/FORWARD)
iptables -S | grep POLICY

# Verify OUTPUT chain blocks eth0 except for exceptions
iptables -L OUTPUT -v -n
```

Expected results:
- Default policies should show: `INPUT DROP`, `FORWARD DROP`, `OUTPUT ACCEPT`
- Final OUTPUT rule should be: `-A OUTPUT -o eth0 -j DROP`
- VPN interface should have: `-A OUTPUT -o tun0 -j ACCEPT` (or wg0 for WireGuard)

### Method 2: VPN Connection Test

Test what happens when the VPN connection is disrupted:

```bash
# 1. Monitor external IP before test
docker exec transmission curl -s ifconfig.me
# Note this IP - it should be your VPN provider's IP

# 2. Inside the container, kill the VPN process
docker exec -it transmission sh
# For OpenVPN:
pkill openvpn
# For WireGuard:
wg-quick down wg0

# 3. Try to access internet (should fail)
curl -s --max-time 5 ifconfig.me
# Should timeout or return nothing

# 4. Try to ping external server (should fail)
ping -c 1 -W 2 google.com
# Should show "Network is unreachable"
```

### Method 3: Network Interface Test

Verify traffic routing through VPN interface:

```bash
# Check active routes
docker exec transmission ip route show

# Verify default route goes through VPN
docker exec transmission ip route get 8.8.8.8

# Monitor traffic on interfaces
docker exec transmission sh -c "cat /sys/class/net/tun0/statistics/tx_bytes"
# Wait and check again - bytes should increase during active downloads

docker exec transmission sh -c "cat /sys/class/net/eth0/statistics/tx_bytes"
# Should only increase for UI access, not torrent traffic
```

### Method 4: DNS Leak Test

Verify DNS queries go through VPN:

```bash
# Check DNS configuration
docker exec transmission cat /etc/resolv.conf

# Test DNS resolution
docker exec transmission nslookup google.com

# Monitor DNS traffic (requires tcpdump in container)
docker exec transmission apk add tcpdump
docker exec transmission tcpdump -i tun0 -n port 53 -c 10
# Should show DNS queries on VPN interface
```

### Method 5: Transmission-Specific Test

Test that Transmission stops working without VPN:

```bash
# 1. Add a test torrent and verify it's downloading
# Use Transmission UI at http://localhost:9091

# 2. Simulate VPN failure
docker exec transmission pkill openvpn

# 3. Check Transmission can't connect to peers
# In UI, torrent should show no peers/seeds
# Download/upload should stop

# 4. Verify UI still accessible but torrenting blocked
curl -s http://localhost:9091/transmission/web/
# Should work (UI exception)

# 5. Check peer connections are blocked
docker exec transmission netstat -an | grep ESTABLISHED | grep -v "9091\|127.0.0.1"
# Should show no peer connections
```

### Method 6: Automated Health Check

The container includes a health check that monitors kill switch:

```bash
# Check health status
docker inspect transmission --format='{{.State.Health.Status}}'

# View health check logs
docker exec transmission cat /tmp/healthcheck.log

# Manually run health check
docker exec transmission /root/healthcheck.sh
echo "Exit code: $?"
# Exit codes:
# 0 = healthy
# 2 = VPN interface down
# 3 = VPN interface missing
# 4 = VPN connectivity failed
```

### Method 7: Port Scan Test

Verify only allowed ports are accessible:

```bash
# From host machine, scan container
nmap -p 1-65535 $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' transmission)

# Should only show:
# - Port 9091 (Transmission UI)
# - Port 8118 (Privoxy if enabled)
# - Configured peer port (if set)
# - NO other ports should be open
```

### Method 8: Firewall Rule Persistence Test

Verify rules persist across container restarts:

```bash
# 1. Restart container
docker restart transmission

# 2. Wait for VPN to connect
docker logs -f transmission | grep "VPN setup script finished"

# 3. Verify iptables rules are restored
docker exec transmission iptables -L OUTPUT -n | grep DROP

# 4. Test internet connectivity still goes through VPN
docker exec transmission curl -s ifconfig.me
# Should show VPN IP
```

## Monitoring Kill Switch Status

### Real-time Monitoring

```bash
# Watch iptables packet counters
watch -n 1 'docker exec transmission iptables -L -v -n | grep DROP'

# Monitor dropped packets (counter should increase if kill switch is blocking)
docker exec transmission iptables -L OUTPUT -v -n | grep "eth0.*DROP"
```

### Log Analysis

```bash
# Check VPN setup logs
docker exec transmission cat /tmp/vpn-setup.log | grep -i "kill\|drop\|block"

# Check for leak protection messages
docker logs transmission | grep -i "kill switch\|leak\|drop"
```

## Common Issues and Solutions

### Issue: Kill switch too restrictive

**Symptom:** Can't access Transmission UI
**Solution:** Check CONNMARK rules for UI port:

```bash
docker exec transmission iptables -t mangle -L PREROUTING -n | grep 9091
docker exec transmission iptables -t mangle -L OUTPUT -n | grep 9091
```

### Issue: LAN access blocked

**Symptom:** Can't access from local network
**Solution:** Set LAN_NETWORK environment variable:

```yaml
environment:
  - LAN_NETWORK=192.168.1.0/24
```

### Issue: VPN reconnection blocked

**Symptom:** VPN can't reconnect after disconnect
**Solution:** Verify VPN server exception:

```bash
docker exec transmission iptables -L OUTPUT -n | grep "$VPN_SERVER"
```

## Security Recommendations

1. **Regular Testing:** Run verification tests weekly or after configuration changes
2. **Monitor Logs:** Set up alerts for VPN disconnections
3. **Use Health Checks:** Configure Docker/Kubernetes to restart unhealthy containers
4. **Test After Updates:** Always verify kill switch after updating container
5. **Network Isolation:** Consider using Docker networks for additional isolation

## Automated Test Script

Save this as `test-killswitch.sh`:

```bash
#!/bin/bash

echo "Kill Switch Verification Test"
echo "=============================="

CONTAINER_NAME="transmission"

# Test 1: Check iptables policies
echo -n "1. Checking firewall policies... "
if docker exec $CONTAINER_NAME iptables -S | grep -q "P INPUT DROP" && \
   docker exec $CONTAINER_NAME iptables -S | grep -q "P FORWARD DROP"; then
    echo "PASS"
else
    echo "FAIL - Kill switch policies not set"
    exit 1
fi

# Test 2: Check VPN interface
echo -n "2. Checking VPN interface... "
VPN_IF=$(docker exec $CONTAINER_NAME cat /tmp/vpn_interface_name 2>/dev/null || echo "tun0")
if docker exec $CONTAINER_NAME ip link show $VPN_IF &>/dev/null; then
    echo "PASS (Interface: $VPN_IF)"
else
    echo "FAIL - VPN interface not found"
    exit 1
fi

# Test 3: Check OUTPUT chain has DROP rule
echo -n "3. Checking OUTPUT DROP rule... "
if docker exec $CONTAINER_NAME iptables -L OUTPUT -n | grep -q "eth0.*DROP"; then
    echo "PASS"
else
    echo "FAIL - No DROP rule for eth0"
    exit 1
fi

# Test 4: Check external IP is VPN
echo -n "4. Checking external IP... "
EXTERNAL_IP=$(docker exec $CONTAINER_NAME curl -s --max-time 5 ifconfig.me)
if [ -n "$EXTERNAL_IP" ]; then
    echo "PASS (IP: $EXTERNAL_IP)"
    echo "   Verify this is your VPN provider's IP, not your real IP"
else
    echo "SKIP - Could not determine external IP"
fi

# Test 5: Check health status
echo -n "5. Checking container health... "
HEALTH=$(docker inspect $CONTAINER_NAME --format='{{.State.Health.Status}}')
if [ "$HEALTH" = "healthy" ]; then
    echo "PASS"
else
    echo "WARNING - Container health: $HEALTH"
fi

echo ""
echo "Kill switch verification complete!"
echo "For thorough testing, manually verify VPN disconnection behavior."
```

Make it executable and run:

```bash
chmod +x test-killswitch.sh
./test-killswitch.sh
```

## Conclusion

A properly functioning kill switch should:

1. Block all non-VPN traffic by default
2. Only allow specific exceptions (UI, LAN if configured)
3. Prevent any data leaks if VPN disconnects
4. Maintain UI accessibility for management
5. Automatically enforce rules on container start

Regular testing using these methods ensures your privacy remains protected even if the VPN connection fails.
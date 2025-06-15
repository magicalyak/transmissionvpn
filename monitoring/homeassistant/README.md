# Home Assistant Integration for TransmissionVPN

This directory contains Home Assistant configuration files to monitor your TransmissionVPN service using the health endpoints.

## 🚀 Quick Start

1. **Copy the configuration files** to your Home Assistant server
2. **Choose your monitoring approach** (see options below)
3. **Update IP address** from `10.1.10.20` to your server's IP
4. **Restart Home Assistant** to load the new sensors
5. **Configure notifications** (optional)

## 📁 Files Overview

| File | Purpose | Usage |
|------|---------|-------|
| `command_line.yaml` | Command-line sensors | Add to your existing `command_line.yaml` |
| `configuration.yaml` | REST sensors (recommended) | Add to your main `configuration.yaml` |
| `template_sensors.yaml` | Advanced template sensors | Include in `configuration.yaml` |
| `automations.yaml` | Sample automations | Add to your `automations.yaml` |

## 🎯 Configuration Options

### Option 1: Command Line Sensors (Simple)
```yaml
# Add to your command_line.yaml
command_line: !include command_line.yaml
```

### Option 2: REST Sensors (Recommended)
```yaml
# Add to your configuration.yaml
rest:
  # ... paste content from configuration.yaml
```

### Option 3: Complete Integration (Advanced)
```yaml
# In configuration.yaml
rest: !include homeassistant/configuration.yaml
template: !include homeassistant/template_sensors.yaml

# In automations.yaml
automation: !include_dir_merge_list homeassistant/
```

## 🔧 Customization

### Update Server IP
Replace `10.1.10.20` with your TransmissionVPN server IP in all files:
```bash
sed -i 's/10.1.10.20/YOUR_SERVER_IP/g' *.yaml
```

### Configure Notifications
Update the notification service in `automations.yaml`:
```yaml
# Change this line:
service: notify.notify
# To your notification service:
service: notify.mobile_app_your_phone
```

## 📊 Available Sensors

### Binary Sensors (On/Off)
- `binary_sensor.transmissionvpn_online` - Service is running
- `binary_sensor.transmissionvpn_vpn_connected` - VPN is connected
- `binary_sensor.transmissionvpn_daemon_running` - Transmission daemon status
- `binary_sensor.transmissionvpn_needs_attention` - Alerts when issues detected
- `binary_sensor.transmissionvpn_high_activity` - High torrent activity

### Regular Sensors (Values)
- `sensor.transmissionvpn_status` - Overall status (healthy/degraded/unhealthy)
- `sensor.transmissionvpn_external_ip` - Current VPN IP address
- `sensor.transmissionvpn_active_torrents` - Number of active torrents
- `sensor.transmissionvpn_download_speed` - Current download speed (MB/s)
- `sensor.transmissionvpn_upload_speed` - Current upload speed (MB/s)
- `sensor.transmissionvpn_memory_usage` - Memory usage percentage
- `sensor.transmissionvpn_cpu_usage` - CPU usage percentage
- `sensor.transmissionvpn_disk_usage` - Disk usage percentage

### Template Sensors (Advanced)
- `sensor.transmissionvpn_health_summary` - Combined health status
- `sensor.transmissionvpn_data_usage` - Total data transfer rate
- `binary_sensor.transmissionvpn_needs_attention` - Smart alerting

## 🚨 Automations

The included automations provide:

1. **Critical Alerts** - Immediate notification when service is down
2. **VPN Disconnect Alerts** - Warning when VPN connection is lost
3. **Recovery Notifications** - Confirmation when issues are resolved
4. **Daily Reports** - Optional daily status summary

### Customizing Alerts

```yaml
# Modify trigger timing
for:
  minutes: 2  # Wait time before alerting

# Change notification service
service: notify.your_service_here

# Customize message content
message: "Your custom alert message"
```

## 🔍 Troubleshooting

### Sensors Not Updating
1. Check if TransmissionVPN health endpoints are working:
   ```bash
   curl http://YOUR_SERVER_IP:9099/health/simple
   ```
2. Verify Home Assistant can reach the server
3. Check Home Assistant logs for errors

### Timeout Issues
If sensors timeout, increase the timeout value:
```yaml
timeout: 30  # Increase from default
```

### Wrong IP Address
Update all configuration files with your server's IP:
```bash
# On your Home Assistant server
sed -i 's/10.1.10.20/YOUR_ACTUAL_IP/g' /config/homeassistant/*.yaml
```

## 📈 Dashboard Integration

### Lovelace Card Example
```yaml
type: entities
title: TransmissionVPN Status
entities:
  - entity: sensor.transmissionvpn_health_summary
    name: Status
  - entity: binary_sensor.transmissionvpn_vpn_connected
    name: VPN Connected
  - entity: sensor.transmissionvpn_external_ip
    name: External IP
  - entity: sensor.transmissionvpn_active_torrents
    name: Active Torrents
  - entity: sensor.transmissionvpn_download_speed
    name: Download Speed
  - entity: sensor.transmissionvpn_upload_speed
    name: Upload Speed
```

### Gauge Card for Speeds
```yaml
type: gauge
entity: sensor.transmissionvpn_download_speed
name: Download Speed
unit: MB/s
min: 0
max: 100
```

## 🔗 Health Endpoints

The integration uses these TransmissionVPN endpoints:

- **Simple Health**: `http://server:9099/health/simple`
  - Returns: `OK` or `Service Unavailable`
  - Use for: Basic up/down monitoring

- **Detailed Health**: `http://server:9099/health`
  - Returns: Comprehensive JSON status
  - Use for: Detailed monitoring and metrics

- **Prometheus Metrics**: `http://server:9099/metrics`
  - Returns: Prometheus format metrics
  - Use for: Advanced monitoring systems

## 🆘 Support

If you encounter issues:

1. **Check TransmissionVPN logs**: `docker logs transmission`
2. **Verify health endpoints**: `curl http://server:9099/health`
3. **Check Home Assistant logs**: Settings → System → Logs
4. **Test connectivity**: Ensure Home Assistant can reach your server

## 🔄 Migration from Port Checking

If you're migrating from simple port checking:

### Old Configuration (Remove)
```yaml
- sensor:
    name: nzbget service
    command: /bin/bash -c "(echo > /dev/tcp/10.1.10.20/6790) > /dev/null 2>&1 && echo ON || echo OFF"
```

### New Configuration (Add)
```yaml
- sensor:
    name: transmissionvpn service
    command: 'curl -sf --max-time 30 http://10.1.10.20:9099/health/simple 2>/dev/null && echo "ON" || echo "OFF"'
```

The new approach provides much more detailed monitoring and actual service health checking rather than just port availability. 
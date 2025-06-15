# Custom Transmission Metrics Server

## Environment Variables

Add these to your `/opt/containerd/env/transmission.env` file:

```bash
# Custom Metrics Configuration
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30

# These are already set for Transmission RPC
TRANSMISSION_RPC_USERNAME=tom
TRANSMISSION_RPC_PASSWORD={92581b5860d7071c59c4a108baae6aa4fb10a909ZaJ2ba1/
```

## Available Metrics

The custom metrics server provides these Prometheus metrics:

### Torrent Counts
- `transmission_torrent_count` - Total number of torrents
- `transmission_active_torrents` - Number of active torrents (downloading/seeding)
- `transmission_downloading_torrents` - Number of downloading torrents
- `transmission_seeding_torrents` - Number of seeding torrents

### Transfer Rates
- `transmission_download_rate_bytes_per_second` - Current download rate
- `transmission_upload_rate_bytes_per_second` - Current upload rate

### Session Statistics
- `transmission_session_downloaded_bytes` - Bytes downloaded this session
- `transmission_session_uploaded_bytes` - Bytes uploaded this session

### System
- `transmission_metrics_last_update_timestamp` - Last metrics update time

## Endpoints

- **Metrics**: `http://rocky.gamull.com:9099/metrics`
- **Health**: `http://rocky.gamull.com:9099/health`

## Features

✅ **Lightweight**: Pure Python, no external dependencies except `requests`
✅ **Environment-driven**: Configured via environment variables
✅ **Session handling**: Properly handles Transmission's CSRF protection
✅ **Error resilient**: Continues working even if Transmission restarts
✅ **Prometheus compatible**: Standard Prometheus metrics format
✅ **Health endpoint**: For monitoring and load balancer checks

## Installation

1. Copy scripts to server:
   ```bash
   scp scripts/transmission-metrics-server.py rocky.gamull.com:/tmp/
   scp scripts/install-custom-metrics.sh rocky.gamull.com:/tmp/
   ```

2. Run installation:
   ```bash
   ssh rocky.gamull.com
   sudo bash /tmp/install-custom-metrics.sh
   ```

3. Restart container:
   ```bash
   sudo systemctl restart transmission
   ```

## Verification

```bash
# Test metrics endpoint
curl -s http://rocky.gamull.com:9099/metrics | head -10

# Test health endpoint
curl -s http://rocky.gamull.com:9099/health
``` 
# Dockerfile Integration Example

## Adding Custom Metrics to Container Build

Here's how you could integrate the custom metrics server directly into the Dockerfile:

```dockerfile
# Add to existing Dockerfile after Python installation
COPY scripts/transmission-metrics-server.py /usr/local/bin/transmission-metrics-server.py
RUN chmod +x /usr/local/bin/transmission-metrics-server.py

# Install Python requests if not already available
RUN apk add --no-cache py3-requests || pip3 install requests

# Add startup script for custom metrics
COPY <<EOF /etc/cont-init.d/99-custom-metrics
#!/usr/bin/with-contenv bash

# Custom Transmission Metrics Server
if [ "\${METRICS_ENABLED:-true}" = "true" ]; then
    echo "[custom-metrics] Starting custom Transmission metrics server"
    
    # Wait for Transmission to be ready
    while ! curl -s http://127.0.0.1:9091/transmission/rpc >/dev/null 2>&1; do
        echo "[custom-metrics] Waiting for Transmission..."
        sleep 2
    done
    
    # Start custom metrics server
    python3 /usr/local/bin/transmission-metrics-server.py &
    echo "[custom-metrics] Custom metrics server started"
else
    echo "[custom-metrics] Metrics disabled, skipping"
fi
EOF

RUN chmod +x /etc/cont-init.d/99-custom-metrics
```

## Environment Variables in docker-compose.yml

```yaml
version: '3.8'
services:
  transmission:
    image: haugene/transmission-openvpn:latest
    environment:
      # Existing variables...
      TRANSMISSION_RPC_USERNAME: tom
      TRANSMISSION_RPC_PASSWORD: your_password_hash
      
      # Custom metrics configuration
      METRICS_ENABLED: "true"
      METRICS_PORT: "9099"
      METRICS_INTERVAL: "30"
    ports:
      - "9092:9091"    # Web UI
      - "9099:9099"    # Custom metrics
      - "51413:51413"  # BitTorrent
```

## Benefits of Built-in Integration

✅ **No manual installation** - Works out of the box
✅ **Version controlled** - Metrics server version tied to container version
✅ **Consistent deployment** - Same behavior across all deployments
✅ **Automatic updates** - Updated when container is updated
✅ **Environment driven** - Easy to enable/disable via env vars

## Current vs Future Approach

### Current (Manual Installation)
- Install via script after container is running
- Requires manual setup on each deployment
- Good for testing and immediate implementation

### Future (Built-in)
- Integrated into container build process
- Automatic deployment with container
- Better for production and long-term use

## Migration Path

1. **Phase 1**: Use manual installation script (current)
2. **Phase 2**: Test and validate metrics work correctly
3. **Phase 3**: Integrate into Dockerfile for next release
4. **Phase 4**: Remove manual installation, use built-in version 
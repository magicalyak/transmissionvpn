# Dockerfile Integration for Custom Metrics

## Adding to Dockerfile

```dockerfile
# Add custom metrics server
COPY scripts/transmission-metrics-server.py /usr/local/bin/transmission-metrics-server.py
RUN chmod +x /usr/local/bin/transmission-metrics-server.py

# Install Python requests
RUN apk add --no-cache py3-requests

# Add startup script
RUN echo '#!/usr/bin/with-contenv bash\n\
if [ "${METRICS_ENABLED:-true}" = "true" ]; then\n\
    echo "[custom-metrics] Starting metrics server"\n\
    while ! curl -s http://127.0.0.1:9091/transmission/rpc >/dev/null 2>&1; do\n\
        sleep 2\n\
    done\n\
    python3 /usr/local/bin/transmission-metrics-server.py &\n\
fi' > /etc/cont-init.d/99-custom-metrics && chmod +x /etc/cont-init.d/99-custom-metrics
```

## Environment Variables

```bash
METRICS_ENABLED=true
METRICS_PORT=9099
METRICS_INTERVAL=30
```

## Benefits

- Built into container
- Environment controlled
- Automatic startup
- No manual installation needed 
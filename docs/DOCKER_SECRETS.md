# 🔐 Docker Secrets Guide

This document explains how to use Docker secrets with transmissionvpn for enhanced security, keeping your VPN credentials secure and out of environment variables or configuration files.

## 📋 Table of Contents

- [What are Docker Secrets?](#what-are-docker-secrets)
- [Docker Swarm Secrets](#docker-swarm-secrets)
- [Docker Compose Secrets](#docker-compose-secrets)
- [Kubernetes Secrets](#kubernetes-secrets)
- [Manual Secrets (Bind Mounts)](#manual-secrets-bind-mounts)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## What are Docker Secrets?

Docker secrets provide a secure way to store sensitive data like passwords, API keys, and certificates. Instead of passing credentials as environment variables (which can be visible in process lists), secrets are:

- Encrypted at rest and in transit
- Only accessible to services that explicitly grant access
- Mounted as files in the container's filesystem
- Not visible in `docker inspect` or process lists

The transmissionvpn container supports Docker secrets using the `FILE__` prefix convention:
- `FILE__VPN_USER` - Path to file containing VPN username
- `FILE__VPN_PASS` - Path to file containing VPN password

## Docker Swarm Secrets

Docker Swarm provides native secret management. Secrets are encrypted and distributed securely across the swarm.

### Creating Secrets

```bash
# Create VPN username secret
echo "your_vpn_username" | docker secret create vpn_username -

# Create VPN password secret
echo "your_vpn_password" | docker secret create vpn_password -

# Verify secrets were created
docker secret ls
```

### Docker Compose for Swarm

```yaml
version: "3.8"

services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "9091:9091"
    volumes:
      - vpn_config:/config
      - vpn_downloads:/downloads
      - vpn_watch:/watch
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/your_provider.ovpn
      - FILE__VPN_USER=/run/secrets/vpn_username
      - FILE__VPN_PASS=/run/secrets/vpn_password
      - LAN_NETWORK=192.168.1.0/24
    secrets:
      - vpn_username
      - vpn_password

secrets:
  vpn_username:
    external: true
  vpn_password:
    external: true

volumes:
  vpn_config:
  vpn_downloads:
  vpn_watch:
```

### Deploy to Swarm

```bash
# Initialize swarm (if not already done)
docker swarm init

# Deploy the stack
docker stack deploy -c docker-compose.yml transmissionvpn

# Check deployment status
docker service ls
docker service logs transmissionvpn_transmissionvpn
```

## Docker Compose Secrets

Docker Compose (non-swarm) also supports secrets, though they're stored as regular files.

### Create Secret Files

```bash
# Create secret files
mkdir -p secrets
echo "your_vpn_username" > secrets/vpn_username.txt
echo "your_vpn_password" > secrets/vpn_password.txt

# Secure the files
chmod 600 secrets/vpn_username.txt secrets/vpn_password.txt
```

### Docker Compose Configuration

```yaml
version: "3.8"

services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "9091:9091"
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/your_provider.ovpn
      - FILE__VPN_USER=/run/secrets/vpn_username
      - FILE__VPN_PASS=/run/secrets/vpn_password
      - LAN_NETWORK=192.168.1.0/24
    secrets:
      - vpn_username
      - vpn_password
    restart: unless-stopped

secrets:
  vpn_username:
    file: ./secrets/vpn_username.txt
  vpn_password:
    file: ./secrets/vpn_password.txt
```

### Alternative: Direct File Mapping

```yaml
version: "3.8"

services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "9091:9091"
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
      - ./secrets/vpn_username.txt:/var/secrets/vpn_username:ro
      - ./secrets/vpn_password.txt:/var/secrets/vpn_password:ro
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/your_provider.ovpn
      - FILE__VPN_USER=/var/secrets/vpn_username
      - FILE__VPN_PASS=/var/secrets/vpn_password
      - LAN_NETWORK=192.168.1.0/24
    restart: unless-stopped
```

## Kubernetes Secrets

For Kubernetes deployments, use native Kubernetes secrets.

### Create Kubernetes Secrets

```bash
# Create secret from command line
kubectl create secret generic vpn-credentials \
  --from-literal=username=your_vpn_username \
  --from-literal=password=your_vpn_password

# Or create from files
kubectl create secret generic vpn-credentials \
  --from-file=username=vpn_username.txt \
  --from-file=password=vpn_password.txt
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transmissionvpn
spec:
  replicas: 1
  selector:
    matchLabels:
      app: transmissionvpn
  template:
    metadata:
      labels:
        app: transmissionvpn
    spec:
      containers:
      - name: transmissionvpn
        image: magicalyak/transmissionvpn:latest
        ports:
        - containerPort: 9091
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "America/New_York"
        - name: VPN_CLIENT
          value: "openvpn"
        - name: VPN_CONFIG
          value: "/config/openvpn/your_provider.ovpn"
        - name: FILE__VPN_USER
          value: "/var/secrets/username"
        - name: FILE__VPN_PASS
          value: "/var/secrets/password"
        - name: LAN_NETWORK
          value: "192.168.1.0/24"
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
          privileged: true
        volumeMounts:
        - name: vpn-credentials
          mountPath: /var/secrets
          readOnly: true
        - name: config
          mountPath: /config
        - name: downloads
          mountPath: /downloads
        - name: dev-tun
          mountPath: /dev/net/tun
      volumes:
      - name: vpn-credentials
        secret:
          secretName: vpn-credentials
          items:
          - key: username
            path: username
          - key: password
            path: password
      - name: config
        persistentVolumeClaim:
          claimName: transmissionvpn-config
      - name: downloads
        persistentVolumeClaim:
          claimName: transmissionvpn-downloads
      - name: dev-tun
        hostPath:
          path: /dev/net/tun

---
apiVersion: v1
kind: Service
metadata:
  name: transmissionvpn-service
spec:
  selector:
    app: transmissionvpn
  ports:
  - port: 9091
    targetPort: 9091
  type: LoadBalancer
```

## Manual Secrets (Bind Mounts)

For simple setups without orchestration, you can use regular file bind mounts:

### Create Secret Files

```bash
# Create a secure directory
sudo mkdir -p /opt/secrets/transmissionvpn
sudo chmod 700 /opt/secrets/transmissionvpn

# Create secret files
echo "your_vpn_username" | sudo tee /opt/secrets/transmissionvpn/vpn_username > /dev/null
echo "your_vpn_password" | sudo tee /opt/secrets/transmissionvpn/vpn_password > /dev/null

# Secure the files
sudo chmod 600 /opt/secrets/transmissionvpn/vpn_username
sudo chmod 600 /opt/secrets/transmissionvpn/vpn_password

# Set ownership (use your PUID/PGID)
sudo chown 1000:1000 /opt/secrets/transmissionvpn/vpn_username
sudo chown 1000:1000 /opt/secrets/transmissionvpn/vpn_password
```

### Docker Run Command

```bash
docker run -d \
  --name transmissionvpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -v /opt/transmissionvpn/config:/config \
  -v /opt/transmissionvpn/downloads:/downloads \
  -v /opt/transmissionvpn/watch:/watch \
  -v /opt/secrets/transmissionvpn/vpn_username:/var/secrets/vpn_username:ro \
  -v /opt/secrets/transmissionvpn/vpn_password:/var/secrets/vpn_password:ro \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/your_provider.ovpn \
  -e FILE__VPN_USER=/var/secrets/vpn_username \
  -e FILE__VPN_PASS=/var/secrets/vpn_password \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/New_York \
  -e LAN_NETWORK=192.168.1.0/24 \
  magicalyak/transmissionvpn:latest
```

## Security Best Practices

### File Permissions

```bash
# Secret files should be readable only by the container user
chmod 600 secret_file.txt
chown 1000:1000 secret_file.txt  # Match PUID/PGID

# Secret directories should not be world-readable
chmod 700 /path/to/secrets/
```

### Environment Variable Security

```bash
# ❌ AVOID: Credentials in environment variables
-e VPN_USER=my_username
-e VPN_PASS=my_password

# ✅ PREFER: Use Docker secrets
-e FILE__VPN_USER=/run/secrets/vpn_username
-e FILE__VPN_PASS=/run/secrets/vpn_password
```

### Rotation and Management

```bash
# Rotate secrets regularly
docker secret create vpn_username_v2 - < new_username.txt
docker service update --secret-rm vpn_username --secret-add vpn_username_v2 transmissionvpn_transmissionvpn

# Clean up old secrets
docker secret rm vpn_username
```

### Backup Security

```bash
# Encrypt backups containing secrets
tar czf - secrets/ | gpg --symmetric --cipher-algo AES256 > secrets_backup.tar.gz.gpg

# Or use dedicated secret management tools
# - HashiCorp Vault
# - AWS Secrets Manager
# - Azure Key Vault
# - Google Secret Manager
```

## Troubleshooting

### Common Issues

1. **Secret file not found:**
```bash
# Check if secret is mounted correctly
docker exec transmissionvpn ls -la /run/secrets/
docker exec transmissionvpn cat /run/secrets/vpn_username
```

2. **Permission denied:**
```bash
# Check file permissions
docker exec transmissionvpn ls -la /run/secrets/vpn_username
# Ensure the file is readable by the container user (PUID)
```

3. **Empty credentials:**
```bash
# Check secret content
docker exec transmissionvpn head -1 /run/secrets/vpn_username
# Ensure no trailing newlines or whitespace
```

4. **VPN connection still fails:**
```bash
# Check container logs
docker logs transmissionvpn

# Verify credentials are being used
docker exec transmissionvpn cat /tmp/vpn-credentials
```

### Debug Commands

```bash
# Test secret access
docker exec transmissionvpn test -r /run/secrets/vpn_username && echo "Username secret readable"
docker exec transmissionvpn test -r /run/secrets/vpn_password && echo "Password secret readable"

# Check secret content (be careful with passwords!)
docker exec transmissionvpn wc -l /run/secrets/vpn_username
docker exec transmissionvpn wc -l /run/secrets/vpn_password

# Check environment variables
docker exec transmissionvpn env | grep FILE__
```

### Validation Script

```bash
#!/bin/bash
# Secret validation script

CONTAINER_NAME="transmissionvpn"

echo "=== Docker Secrets Validation ==="

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "❌ Container $CONTAINER_NAME is not running"
    exit 1
fi

# Check secret environment variables
VPN_USER_FILE=$(docker exec "$CONTAINER_NAME" printenv FILE__VPN_USER 2>/dev/null)
VPN_PASS_FILE=$(docker exec "$CONTAINER_NAME" printenv FILE__VPN_PASS 2>/dev/null)

if [ -z "$VPN_USER_FILE" ] || [ -z "$VPN_PASS_FILE" ]; then
    echo "❌ FILE__VPN_USER or FILE__VPN_PASS environment variables not set"
    exit 1
fi

echo "✅ Secret environment variables configured"
echo "   FILE__VPN_USER: $VPN_USER_FILE"
echo "   FILE__VPN_PASS: $VPN_PASS_FILE"

# Check if secret files exist and are readable
if docker exec "$CONTAINER_NAME" test -r "$VPN_USER_FILE"; then
    echo "✅ VPN username secret file is readable"
else
    echo "❌ VPN username secret file not found or not readable: $VPN_USER_FILE"
    exit 1
fi

if docker exec "$CONTAINER_NAME" test -r "$VPN_PASS_FILE"; then
    echo "✅ VPN password secret file is readable"
else
    echo "❌ VPN password secret file not found or not readable: $VPN_PASS_FILE"
    exit 1
fi

# Check secret file content (non-empty)
USERNAME_LENGTH=$(docker exec "$CONTAINER_NAME" wc -c < "$VPN_USER_FILE" 2>/dev/null || echo "0")
PASSWORD_LENGTH=$(docker exec "$CONTAINER_NAME" wc -c < "$VPN_PASS_FILE" 2>/dev/null || echo "0")

if [ "$USERNAME_LENGTH" -gt 1 ]; then
    echo "✅ VPN username secret has content ($USERNAME_LENGTH bytes)"
else
    echo "❌ VPN username secret is empty or too short"
    exit 1
fi

if [ "$PASSWORD_LENGTH" -gt 1 ]; then
    echo "✅ VPN password secret has content ($PASSWORD_LENGTH bytes)"
else
    echo "❌ VPN password secret is empty or too short"
    exit 1
fi

echo "✅ All Docker secrets validation checks passed!"
```

## Advanced Scenarios

### Multi-VPN Setup with Different Credentials

```yaml
version: "3.8"

services:
  transmissionvpn-us:
    image: magicalyak/transmissionvpn:latest
    environment:
      - FILE__VPN_USER=/run/secrets/vpn_us_username
      - FILE__VPN_PASS=/run/secrets/vpn_us_password
      - VPN_CONFIG=/config/openvpn/us_server.ovpn
    secrets:
      - vpn_us_username
      - vpn_us_password

  transmissionvpn-eu:
    image: magicalyak/transmissionvpn:latest
    environment:
      - FILE__VPN_USER=/run/secrets/vpn_eu_username
      - FILE__VPN_PASS=/run/secrets/vpn_eu_password
      - VPN_CONFIG=/config/openvpn/eu_server.ovpn
    secrets:
      - vpn_eu_username
      - vpn_eu_password

secrets:
  vpn_us_username:
    file: ./secrets/us_username.txt
  vpn_us_password:
    file: ./secrets/us_password.txt
  vpn_eu_username:
    file: ./secrets/eu_username.txt
  vpn_eu_password:
    file: ./secrets/eu_password.txt
```

### External Secret Management Integration

```bash
# Example with HashiCorp Vault
vault kv put secret/transmissionvpn username="$VPN_USER" password="$VPN_PASS"

# Retrieve and create Docker secret
vault kv get -field=username secret/transmissionvpn | docker secret create vpn_username -
vault kv get -field=password secret/transmissionvpn | docker secret create vpn_password -
``` 
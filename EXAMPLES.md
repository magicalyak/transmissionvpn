# 📋 Configuration Examples

This document provides practical configuration examples for different use cases.

## 🚀 Basic Examples

### OpenVPN with NordVPN

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
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/us8923.nordvpn.com.udp.ovpn
      - VPN_USER=your_nordvpn_username
      - VPN_PASS=your_nordvpn_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - LAN_NETWORK=192.168.1.0/24
    restart: unless-stopped
```

### WireGuard with Mullvad

```yaml
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "9091:9091"
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
    environment:
      - VPN_CLIENT=wireguard
      - VPN_CONFIG=/config/wireguard/mullvad-us.conf
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

## 🎨 Alternative Web UIs

### Flood for Transmission

1. Download Flood:
   ```bash
   curl -OL https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.zip
   unzip flood-for-transmission.zip
   ```

2. Docker Compose:
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
         - ./flood-for-transmission:/web-ui:ro  # Mount Flood UI
       environment:
         - VPN_CLIENT=openvpn
         - VPN_CONFIG=/config/openvpn/provider.ovpn
         - VPN_USER=username
         - VPN_PASS=password
         - TRANSMISSION_WEB_HOME=/web-ui  # Use Flood UI
         - PUID=1000
         - PGID=1000
       restart: unless-stopped
   ```

### Combustion UI

1. Download Combustion:
   ```bash
   curl -OL https://github.com/secretmapper/combustion/archive/release.zip
   unzip release.zip
   mv combustion-release combustion
   ```

2. Mount and configure:
   ```yaml
   volumes:
     - ./combustion:/web-ui:ro
   environment:
     - TRANSMISSION_WEB_HOME=/web-ui
   ```

## 🔐 Secure Configurations

### Using Docker Secrets

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
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - FILE__VPN_USER=/run/secrets/vpn_username
      - FILE__VPN_PASS=/run/secrets/vpn_password
      - PUID=1000
      - PGID=1000
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

### Web UI Authentication

```yaml
environment:
  - TRANSMISSION_RPC_USERNAME=admin
  - TRANSMISSION_RPC_PASSWORD=secure_password
  - TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true
```

## 🌐 Network Configurations

### With HTTP Proxy (Privoxy)

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
      - "8118:8118"  # Privoxy proxy port
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - VPN_USER=username
      - VPN_PASS=password
      - ENABLE_PRIVOXY=yes
      - PRIVOXY_PORT=8118
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### Fixed Peer Port

```yaml
environment:
  - TRANSMISSION_PEER_PORT=51413
  - ADDITIONAL_PORTS=51413
ports:
  - "51413:51413"
  - "51413:51413/udp"
```

## 📊 Monitoring & Themes

### With Theme and Monitoring

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
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - VPN_USER=username
      - VPN_PASS=password
      - PUID=1000
      - PGID=1000
      
      # Beautiful theme
      - DOCKER_MODS=ghcr.io/gilbn/theme.park:transmission
      - TP_THEME=hotline
      
      # Monitoring
      - METRICS_ENABLED=true
      - CHECK_DNS_LEAK=true
      - CHECK_IP_LEAK=true
      - LOG_TO_STDOUT=true
    restart: unless-stopped
```

### External Monitoring

```bash
# Download monitoring script
curl -o monitor.sh https://raw.githubusercontent.com/magicalyak/transmissionvpn/main/scripts/monitor.sh
chmod +x monitor.sh

# Run with Discord notifications
./monitor.sh --discord "https://discord.com/api/webhooks/YOUR_WEBHOOK" --interval 60

# Run with multiple notification types
./monitor.sh \
  --discord "DISCORD_WEBHOOK" \
  --slack "SLACK_WEBHOOK" \
  --level warn \
  --interval 30
```

## 🏠 Media Server Integration

### With Sonarr/Radarr

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
      - /media/downloads:/downloads  # Shared with *arr apps
      - /media/watch:/watch
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - VPN_USER=username
      - VPN_PASS=password
      - TRANSMISSION_INCOMPLETE_DIR=/downloads/incomplete
      - TRANSMISSION_PEER_PORT=51413
      - ADDITIONAL_PORTS=51413
      - PUID=1000
      - PGID=1000
      - LAN_NETWORK=192.168.1.0/24  # Allow *arr apps access
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./sonarr-config:/config
      - /media:/media
    ports:
      - "8989:8989"
    restart: unless-stopped
```

## 🔧 Development & Testing

### Debug Configuration

```yaml
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn-debug
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
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/test.ovpn
      - VPN_USER=testuser
      - VPN_PASS=testpass
      - DEBUG=true
      - LOG_TO_STDOUT=true
      - DOCKER_MODS=lscr.io/linuxserver/mods:universal-tshoot
      - PUID=1000
      - PGID=1000
    restart: "no"  # Don't auto-restart for debugging
```

## 🔄 Migration Examples

### From haugene/transmission-openvpn

**Before (haugene):**
```bash
docker run -d \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -v /opt/transmission:/data \
  -e OPENVPN_PROVIDER=PIA \
  -e OPENVPN_CONFIG=netherlands \
  -e OPENVPN_USERNAME=myuser \
  -e OPENVPN_PASSWORD=mypass \
  -e LOCAL_NETWORK=192.168.1.0/24 \
  haugene/transmission-openvpn
```

**After (transmissionvpn):**
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
      - ./downloads:/downloads  # Changed from /data
      - ./watch:/watch
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/pia-netherlands.ovpn  # Manual config
      - VPN_USER=myuser
      - VPN_PASS=mypass
      - LAN_NETWORK=192.168.1.0/24
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

**Migration steps:**
1. Download PIA Netherlands config to `./config/openvpn/pia-netherlands.ovpn`
2. Move downloads: `cp -r /opt/transmission/completed/* ./downloads/`
3. Move settings: `cp /opt/transmission/transmission-home/settings.json ./config/`

## 🛠️ Advanced Features

### Multiple Mods

```yaml
environment:
  # Combine theme + packages + troubleshooting tools
  - DOCKER_MODS=ghcr.io/gilbn/theme.park:transmission|lscr.io/linuxserver/mods:universal-package-install|lscr.io/linuxserver/mods:universal-tshoot
  - TP_THEME=dracula
  - INSTALL_PACKAGES=unrar|p7zip|mediainfo|curl|git
```

### Prometheus Metrics

```bash
# Start metrics server inside container
docker exec transmissionvpn python3 /scripts/metrics-server.py &

# Access metrics
curl http://localhost:8080/metrics
curl http://localhost:8080/health
```

### Custom DNS

```yaml
environment:
  - NAME_SERVERS=1.1.1.1,8.8.8.8
dns:
  - 1.1.1.1
  - 8.8.8.8
```

## 📝 Quick Reference

### Essential Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `VPN_CLIENT` | VPN type | `openvpn` or `wireguard` |
| `VPN_CONFIG` | Config file path | `/config/openvpn/provider.ovpn` |
| `VPN_USER` | VPN username | `your_username` |
| `VPN_PASS` | VPN password | `your_password` |
| `PUID/PGID` | User/Group ID | `1000` |
| `TZ` | Timezone | `America/New_York` |
| `LAN_NETWORK` | Local network | `192.168.1.0/24` |

### Common Ports

| Port | Service | Purpose |
|------|---------|---------|
| `9091` | Transmission | Web UI |
| `8118` | Privoxy | HTTP proxy |
| `51413` | Transmission | P2P connections |
| `8080` | Metrics | Prometheus metrics |

### Volume Mappings

| Container Path | Purpose | Example Host Path |
|----------------|---------|-------------------|
| `/config` | Settings & VPN configs | `./config` |
| `/downloads` | Completed downloads | `./downloads` |
| `/watch` | Auto-add torrents | `./watch` |
| `/web-ui` | Alternative UI | `./flood-for-transmission` | 
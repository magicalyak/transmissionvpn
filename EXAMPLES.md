# 📋 Configuration Examples

Practical configuration examples for different VPN providers and use cases.

## 🚀 Basic Examples

### NordVPN Example

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
      - LAN_NETWORK=192.168.1.0/24
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

### Private Internet Access (PIA) Example

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
      - VPN_CONFIG=/config/openvpn/us_new_york_city.ovpn
      - VPN_USER=your_pia_username
      - VPN_PASS=your_pia_password
      - LAN_NETWORK=192.168.1.0/24
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### PrivadoVPN Example

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
      - VPN_CONFIG=/config/openvpn/privado.ams-026.tcp.1194.ovpn
      - VPN_USER=your_privadovpn_username
      - VPN_PASS=your_privadovpn_password
      - LAN_NETWORK=192.168.1.0/24
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## 🔒 WireGuard Examples

### Mullvad WireGuard

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
    restart: unless-stopped
```

### Surfshark WireGuard

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
    environment:
      - VPN_CLIENT=wireguard
      - VPN_CONFIG=/config/wireguard/surfshark-us.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## 🔐 Security & Production

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
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### Custom DNS Settings

```yaml
environment:
  - NAME_SERVERS=1.1.1.1,8.8.8.8
  - VPN_CLIENT=openvpn
  - VPN_CONFIG=/config/openvpn/provider.ovpn
  - VPN_USER=username
  - VPN_PASS=password
```

### Port Forwarding

```yaml
environment:
  - TRANSMISSION_PEER_PORT=51413
  - ADDITIONAL_PORTS=51413
ports:
  - "51413:51413"
  - "51413:51413/udp"
```

## 🎨 Alternative Web UIs

### Automatic Installation (Recommended)

The easiest way to use alternative web UIs - they're automatically downloaded and configured:

#### Flood for Transmission

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
      - TRANSMISSION_WEB_UI_AUTO=flood  # Automatically downloads Flood UI
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

#### Kettu UI

```yaml
environment:
  - TRANSMISSION_WEB_UI_AUTO=kettu  # Clean, responsive interface
```

#### Combustion UI

```yaml
environment:
  - TRANSMISSION_WEB_UI_AUTO=combustion  # Sleek, mobile-friendly design
```

#### Transmission Web Control

```yaml
environment:
  - TRANSMISSION_WEB_UI_AUTO=transmission-web-control  # Enhanced control panel
```

### Switching Between UIs

1. **Change the UI:**

   ```yaml
   environment:
     - TRANSMISSION_WEB_UI_AUTO=kettu  # Switch to Kettu
   ```

2. **Force re-download (if needed):**

   ```bash
   # Remove cached UI to force fresh download
   docker exec transmissionvpn rm -rf /config/web-ui/kettu
   docker restart transmissionvpn
   ```

3. **Disable automatic UI:**

   ```yaml
   environment:
     - TRANSMISSION_WEB_UI_AUTO=false  # Use default Transmission UI
   ```

### Manual Installation (Legacy Method)

For custom UIs or if you prefer manual control:

### Flood for Transmission (Manual)

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
      - LAN_NETWORK=192.168.1.0/24  # Allow *arr apps access
      - PUID=1000
      - PGID=1000
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

### Directory Structure & Sonarr/Radarr Compatibility

**Important:** The LinuxServer.io transmission image (which transmissionvpn is based on) uses a different directory structure than haugene/docker-transmission-openvpn:

#### Directory Differences

| Container | Complete Downloads | Incomplete Downloads |
|-----------|-------------------|---------------------|
| **haugene/docker-transmission-openvpn** | `/data/completed/` | `/data/incomplete/` |
| **LinuxServer.io transmission** | `/downloads/complete/` | `/downloads/incomplete/` |
| **magicalyak/transmissionvpn** | `/downloads/complete/` | `/downloads/incomplete/` |

#### Automatic Compatibility (v4.0.6-2+)

**transmissionvpn** automatically creates compatibility symlinks during startup:

- `/downloads/completed` → `/downloads/complete`
- `/data` → `/downloads`

This means **your existing haugene-based Sonarr/Radarr configuration should work without changes!**

#### Sonarr/Radarr Configuration

1. **Download Client Settings in Sonarr/Radarr:**

   ```
   Host: transmissionvpn
   Port: 9091
   Category: tv  (for Sonarr) or movies (for Radarr)
   Directory: leave empty or use /downloads/complete/
   ```

2. **Remote Path Mappings:**

   ```
   Host: transmissionvpn
   Remote Path: /downloads/
   Local Path: /media/downloads/
   ```

3. **Volume Mapping:**

   ```yaml
   # Both containers must see the same paths
   transmissionvpn:
     volumes:
       - /media/downloads:/downloads    # Host path must match Sonarr/Radarr
   
   sonarr:
     volumes:
       - /media/downloads:/media/downloads  # Same host path
   ```

### Alternative Volume Mapping (haugene compatibility)

If you prefer the haugene directory structure, use these volume mappings:

```yaml
transmissionvpn:
  volumes:
    - ./config:/config
    - /media/downloads:/downloads/completed    # Map to completed subdirectory
    - /media/incomplete:/downloads/incomplete  # Separate incomplete volume
    - ./watch:/watch
```

This makes completed downloads appear in `/media/downloads/` on your host, matching haugene's behavior.

## 🔧 Development & Debugging

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
      - PUID=1000
      - PGID=1000
    restart: "no"  # Don't auto-restart for debugging
```

## 🔄 Migration from haugene/transmission-openvpn

### Before (haugene)

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

### After (transmissionvpn)

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

**Migration Steps:**

1. Download PIA Netherlands config to `./config/openvpn/pia-netherlands.ovpn`
2. Move downloads: `cp -r /opt/transmission/completed/* ./downloads/`
3. Move settings: `cp /opt/transmission/transmission-home/settings.json ./config/`

## 📝 Quick Reference

### Essential Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `VPN_CLIENT` | VPN type | `openvpn` or `wireguard` |
| `VPN_CONFIG` | Config file path | `/config/openvpn/provider.ovpn` |
| `VPN_USER` | VPN username | `your_username` |
| `VPN_PASS` | VPN password | `your_password` |
| `LAN_NETWORK` | Local network | `192.168.1.0/24` |

### Docker Run Command Template

```bash
docker run -d \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --name=transmissionvpn \
  -p 9091:9091 \
  -v ./config:/config \
  -v ./downloads:/downloads \
  -v ./watch:/watch \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/provider.ovpn \
  -e VPN_USER=username \
  -e VPN_PASS=password \
  -e LAN_NETWORK=192.168.1.0/24 \
  -e PUID=1000 \
  -e PGID=1000 \
  magicalyak/transmissionvpn:latest
```

## 🚦 Health Checks

### Manual Health Check

```bash
# Check container health
docker exec transmissionvpn /root/healthcheck.sh

# Check external IP
docker exec transmissionvpn curl ifconfig.me

# Verify VPN tunnel
docker exec transmissionvpn ping -c 3 8.8.8.8
```

### Troubleshooting Commands

```bash
# View logs
docker logs transmissionvpn

# Check routing table
docker exec transmissionvpn ip route

# Test DNS resolution
docker exec transmissionvpn nslookup google.com
```

## 📜 Full Examples

### Basic Docker Compose

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
      - LAN_NETWORK=192.168.1.0/24
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### Docker Compose with Sonarr/Radarr

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
      - LAN_NETWORK=192.168.1.0/24
      - PUID=1000
      - PGID=1000
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr
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

  radarr:
    image: linuxserver/radarr
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./radarr-config:/config
    ports:
      - "8989:8989"
    restart: unless-stopped
```

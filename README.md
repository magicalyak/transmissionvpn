# 🛡️ Transmission VPN Docker

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Build Status](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Docker container which runs Transmission with an optional OpenVPN or WireGuard connection**

Transmission BitTorrent client with VPN protection and kill switch to prevent IP leaks when the tunnel goes down.

## 🚀 Quick Start

Run the container with this command:

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
  -e VPN_CONFIG=/config/openvpn/your_provider.ovpn \
  -e VPN_USER=your_vpn_username \
  -e VPN_PASS=your_vpn_password \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/New_York \
  magicalyak/transmissionvpn:latest
```

## 🐙 Docker Compose (Recommended)

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
      - VPN_USER=your_username
      - VPN_PASS=your_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - LAN_NETWORK=192.168.1.0/24
    restart: unless-stopped
```

## 📋 Environment Variables

### Required Variables

| Variable | Function | Example |
|----------|----------|---------|
| `VPN_CLIENT` | VPN type (openvpn/wireguard) | `openvpn` |
| `VPN_CONFIG` | Path to VPN config file | `/config/openvpn/provider.ovpn` |
| `VPN_USER` | VPN username (OpenVPN only) | `your_username` |
| `VPN_PASS` | VPN password (OpenVPN only) | `your_password` |

### Optional Variables

| Variable | Function | Default | Example |
|----------|----------|---------|---------|
| `PUID` | User ID for file permissions | `1000` | `1000` |
| `PGID` | Group ID for file permissions | `1000` | `1000` |
| `TZ` | Timezone | `UTC` | `America/New_York` |
| `LAN_NETWORK` | Local network CIDR | (none) | `192.168.1.0/24` |
| `ENABLE_PRIVOXY` | Enable HTTP proxy | `no` | `yes` |
| `DEBUG` | Enable debug logging | `false` | `true` |

## 📁 Volumes

| Volume | Function | Example |
|--------|----------|---------|
| `/config` | Configuration files and VPN configs | `./config:/config` |
| `/downloads` | Completed downloads | `./downloads:/downloads` |
| `/watch` | Auto-add torrent files | `./watch:/watch` |

## 🌐 Ports

| Port | Function | Required |
|------|----------|----------|
| `9091` | Transmission Web UI | Yes |
| `8118` | Privoxy HTTP proxy | No |

## 🔧 Setup Instructions

### 1. Create Directory Structure

```bash
mkdir -p transmissionvpn/{config/openvpn,downloads,watch}
cd transmissionvpn
```

### 2. Add VPN Configuration

Place your VPN provider's `.ovpn` file in `config/openvpn/` directory.

**Note:** The container will fail to start if `VPN_CLIENT` is set and no valid config file is present.

### 3. Start Container

```bash
docker-compose up -d
```

### 4. Access Transmission

Open http://localhost:9091 in your browser.

## 🛡️ VPN Providers

This container works with any OpenVPN or WireGuard provider:

- **NordVPN** - Download configs from account dashboard
- **ExpressVPN** - Get configs from manual setup page  
- **Surfshark** - Download from manual setup section
- **ProtonVPN** - Get configs from downloads page
- **Private Internet Access** - Download from client support
- **PrivadoVPN** - Generate configs from account dashboard
- **Mullvad** - Generate configs from account page

📖 **Provider-specific guides**: [VPN Setup Documentation](docs/VPN_PROVIDERS.md)

## 🔍 OpenVPN Setup

1. **Download** your provider's `.ovpn` file
2. **Place** it in `config/openvpn/` directory
3. **Set** `VPN_CLIENT=openvpn`
4. **Provide** your credentials via `VPN_USER` and `VPN_PASS`

**Tip:** You can also use `auth-user-pass credentials.txt` in your `.ovpn` file.

## 🔒 WireGuard Setup

For WireGuard, additional requirements apply:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_MODULE
sysctls:
  - net.ipv4.conf.all.src_valid_mark=1
environment:
  - VPN_CLIENT=wireguard
  - VPN_CONFIG=/config/wireguard/wg0.conf
```

**Note:** No username/password needed for WireGuard.

## 🚦 Health Checks

The container includes automatic health monitoring:

- **VPN Connectivity** - Verifies tunnel is active
- **IP Leak Protection** - Blocks traffic if VPN fails
- **DNS Leak Prevention** - Routes DNS through VPN

Check container health:
```bash
docker exec transmissionvpn /root/healthcheck.sh
```

## 🔧 Troubleshooting

### Container Won't Start
```bash
# Check logs
docker logs transmissionvpn

# Common issues:
# - Missing VPN config file
# - Incorrect credentials
# - Missing NET_ADMIN capability
```

### VPN Not Working
```bash
# Check external IP
docker exec transmissionvpn curl ifconfig.me

# Verify VPN connection
docker exec transmissionvpn ping -c 3 8.8.8.8
```

📖 **Complete troubleshooting**: [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

## 📚 Documentation

- **[Configuration Examples](EXAMPLES.md)** - Real-world usage examples
- **[VPN Provider Setup](docs/VPN_PROVIDERS.md)** - Provider-specific guides
- **[Docker Secrets](docs/DOCKER_SECRETS.md)** - Secure credential management
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 🔄 Migration from haugene/transmission-openvpn

| haugene | transmissionvpn |
|---------|-----------------|
| `OPENVPN_PROVIDER` | Use `VPN_CONFIG` with `.ovpn` file |
| `OPENVPN_USERNAME` | `VPN_USER` |
| `OPENVPN_PASSWORD` | `VPN_PASS` |
| `LOCAL_NETWORK` | `LAN_NETWORK` |

### Important Directory Structure Changes

**haugene/docker-transmission-openvpn** uses different paths than the LinuxServer.io base:

| Directory Purpose | haugene Path | transmissionvpn Path |
|------------------|--------------|---------------------|
| **Main Volume** | `/data` | `/downloads` |
| **Completed Downloads** | `/data/completed/` | `/downloads/complete/` |
| **Incomplete Downloads** | `/data/incomplete/` | `/downloads/incomplete/` |

### Automatic Compatibility (New!)

**transmissionvpn v4.0.6-2+** automatically creates compatibility symlinks during container startup:

- `/downloads/completed` → `/downloads/complete` 
- `/data` → `/downloads`

This means **both directory structures work simultaneously** without requiring configuration changes! Your existing Sonarr/Radarr setup should continue working after migration.

### Migration Options

#### Option 1: Use Automatic Compatibility (Recommended)
```yaml
# No changes needed! The container creates symlinks automatically
volumes:
  - /your/downloads:/downloads        # Works with both /downloads/complete/ and /downloads/completed/
```

#### Option 2: Update Your Volume Mappings
```yaml
# NEW: LinuxServer.io compatible structure
volumes:
  - /your/downloads:/downloads        # Downloads go to /your/downloads/complete/
  - /your/incomplete:/downloads/incomplete
```

#### Option 3: Maintain haugene Directory Structure  
```yaml
# ALTERNATIVE: Map to match haugene's structure
volumes:
  - /your/downloads:/downloads/completed    # Downloads go directly to /your/downloads/
  - /your/incomplete:/downloads/incomplete
```

### Sonarr/Radarr Integration Fix

If you're getting "*directory does not appear to exist inside the container*" errors:

1. **Check Download Client Settings:**
   - **Host:** `transmissionvpn` (or your container name)
   - **Port:** `9091`
   - **Category:** Set appropriate category for TV/Movies
   - **Directory:** Leave empty or use `/downloads/complete/`

2. **Configure Remote Path Mappings:**
   ```
   Host: transmissionvpn  
   Remote Path: /downloads/
   Local Path: /media/downloads/  (or your host path)
   ```

3. **Ensure Consistent Volume Mapping:**
   ```yaml
   # Both containers must see the same paths
   transmissionvpn:
     volumes:
       - /media/downloads:/downloads
   
   sonarr:
     volumes:
       - /media/downloads:/media/downloads
   ```

## 🆘 Support

1. **Check logs**: `docker logs transmissionvpn`
2. **Read docs**: Complete guides linked above
3. **Search issues**: [GitHub Issues](https://github.com/magicalyak/transmissionvpn/issues)
4. **Create issue**: Use our [templates](.github/ISSUE_TEMPLATE/)

## ⚙️ Advanced Configuration

<details>
<summary>Click to expand all environment variables</summary>

### VPN Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `VPN_CLIENT` | `openvpn` or `wireguard` | `openvpn` |
| `VPN_CONFIG` | Path to VPN config file | (required) |
| `VPN_USER` | VPN username | (required for OpenVPN) |
| `VPN_PASS` | VPN password | (required for OpenVPN) |
| `VPN_OPTIONS` | Additional VPN options | (none) |

### Network Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `LAN_NETWORK` | Local network CIDR | (none) |
| `NAME_SERVERS` | DNS servers | (auto) |
| `ADDITIONAL_PORTS` | Extra ports | (none) |

### Transmission Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `TRANSMISSION_PEER_PORT` | P2P port | (random) |
| `TRANSMISSION_DOWNLOAD_DIR` | Download directory | `/downloads` |
| `TRANSMISSION_WATCH_DIR` | Watch directory | `/watch` |
| `TRANSMISSION_WEB_HOME` | Alternative web UI | (none) |

### System Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `PUID` | User ID | `1000` |
| `PGID` | Group ID | `1000` |
| `TZ` | Timezone | `UTC` |
| `UMASK` | File creation mask | `002` |

### Optional Features
| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_PRIVOXY` | HTTP proxy | `no` |
| `DEBUG` | Debug logging | `false` |
| `METRICS_ENABLED` | Metrics collection | `false` |

</details>
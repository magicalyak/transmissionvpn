# 🛡️ Transmission VPN Docker

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Build Status](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Transmission BitTorrent client with VPN protection. All traffic is automatically routed through your VPN connection with a kill switch to prevent IP leaks.

## 🚀 Quick Start

### 1. Create directories

```bash
mkdir -p transmissionvpn/{config/openvpn,downloads,watch}
cd transmissionvpn
```

### 2. Add your VPN config

Place your VPN provider's `.ovpn` file in the `config/openvpn/` directory.

### 3. Run with Docker

```bash
docker run -d \
  --name transmissionvpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -v "$(pwd)/config:/config" \
  -v "$(pwd)/downloads:/downloads" \
  -v "$(pwd)/watch:/watch" \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/your_provider.ovpn \
  -e VPN_USER=your_vpn_username \
  -e VPN_PASS=your_vpn_password \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/New_York \
  magicalyak/transmissionvpn:latest
```

### 4. Access Transmission

Open <http://localhost:9091> in your browser.

## 📋 What You Need

- **VPN Configuration**: `.ovpn` file from your VPN provider
- **VPN Credentials**: Username and password for your VPN service
- **Docker**: With `--cap-add=NET_ADMIN` and `/dev/net/tun` access

## 🐙 Docker Compose (Recommended)

Create a `docker-compose.yml` file:

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
      - VPN_CONFIG=/config/openvpn/your_provider.ovpn
      - VPN_USER=your_vpn_username
      - VPN_PASS=your_vpn_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

Then run:

```bash
docker-compose up -d
```

## 🔧 Basic Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `VPN_CLIENT` | VPN type: `openvpn` or `wireguard` | `openvpn` |
| `VPN_CONFIG` | Path to VPN config file | `/config/openvpn/provider.ovpn` |
| `VPN_USER` | VPN username | `your_username` |
| `VPN_PASS` | VPN password | `your_password` |

### Optional Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PUID` | User ID for file permissions | `1000` |
| `PGID` | Group ID for file permissions | `1000` |
| `TZ` | Timezone | `UTC` |
| `LAN_NETWORK` | Local network CIDR (e.g., `192.168.1.0/24`) | (none) |

## 📁 Directory Structure

```text
transmissionvpn/
├── config/
│   ├── openvpn/
│   │   └── your_provider.ovpn    # Your VPN config file
│   └── settings.json             # Transmission settings (auto-created)
├── downloads/                    # Completed downloads
└── watch/                        # Drop .torrent files here for auto-add
```

## 🛡️ VPN Providers

This container works with any OpenVPN or WireGuard provider. Popular choices:

- **NordVPN**: Download `.ovpn` files from your account
- **ExpressVPN**: Get OpenVPN configs from setup page
- **Surfshark**: Download from manual setup section
- **ProtonVPN**: Get configs from downloads page
- **Private Internet Access**: Download from client support
- **Mullvad**: Generate configs from account page

📖 **Detailed setup guides**: [VPN Provider Documentation](docs/VPN_PROVIDERS.md)

## 🔍 Troubleshooting

### Container won't start

```bash
# Check logs
docker logs transmissionvpn

# Common issues:
# - Missing VPN config file
# - Incorrect VPN credentials
# - Missing --cap-add=NET_ADMIN
# - Missing --device=/dev/net/tun
```

### Can't access Transmission UI

```bash
# Check if container is running
docker ps | grep transmissionvpn

# Check if port is accessible
curl http://localhost:9091
```

### VPN not working

```bash
# Check external IP (should be VPN IP, not your real IP)
docker exec transmissionvpn curl ifconfig.me

# Check VPN connection
docker exec transmissionvpn ping -c 3 google.com
```

📖 **Complete troubleshooting guide**: [Troubleshooting Documentation](docs/TROUBLESHOOTING.md)

---

## 🚀 Advanced Features

### WireGuard Support

For WireGuard VPN configs:

```yaml
environment:
  - VPN_CLIENT=wireguard
  - VPN_CONFIG=/config/wireguard/wg0.conf
# Note: No VPN_USER/VPN_PASS needed for WireGuard
```

Additional requirements for WireGuard:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_MODULE
sysctls:
  - net.ipv4.conf.all.src_valid_mark=1
```

### HTTP Proxy (Privoxy)

Enable optional HTTP proxy that also routes through VPN:

```yaml
environment:
  - ENABLE_PRIVOXY=yes
  - PRIVOXY_PORT=8118
ports:
  - "8118:8118"
```

### Alternative Web UIs

Replace the default Transmission web interface:

1. Download your preferred UI (e.g., Flood):

   ```bash
   curl -OL https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.zip
   unzip flood-for-transmission.zip
   ```

2. Mount and configure:

   ```yaml
   volumes:
     - ./flood-for-transmission:/web-ui:ro
   environment:
     - TRANSMISSION_WEB_HOME=/web-ui
   ```

### Docker Secrets

For production deployments, use Docker secrets instead of environment variables:

```yaml
environment:
  - FILE__VPN_USER=/run/secrets/vpn_username
  - FILE__VPN_PASS=/run/secrets/vpn_password
secrets:
  - vpn_username
  - vpn_password

secrets:
  vpn_username:
    file: ./secrets/vpn_username.txt
  vpn_password:
    file: ./secrets/vpn_password.txt
```

📖 **Complete secrets guide**: [Docker Secrets Documentation](docs/DOCKER_SECRETS.md)

### Monitoring & Metrics

Enable comprehensive monitoring:

```yaml
environment:
  - METRICS_ENABLED=true
  - CHECK_DNS_LEAK=true
  - CHECK_IP_LEAK=true
```

External monitoring with notifications:

```bash
# Download monitoring script
curl -o monitor.sh https://raw.githubusercontent.com/magicalyak/transmissionvpn/main/scripts/monitor.sh
chmod +x monitor.sh

# Run with Discord notifications
./monitor.sh --discord "https://discord.com/api/webhooks/YOUR_WEBHOOK"
```

Prometheus metrics endpoint:

```bash
# Start metrics server
docker exec transmissionvpn python3 /scripts/metrics-server.py &

# Access metrics
curl http://localhost:8080/metrics
```

### LinuxServer.io Mods

Extend functionality with community mods:

```yaml
environment:
  # Beautiful themes
  - DOCKER_MODS=ghcr.io/gilbn/theme.park:transmission
  - TP_THEME=hotline
  
  # Additional packages
  - DOCKER_MODS=lscr.io/linuxserver/mods:universal-package-install
  - INSTALL_PACKAGES=unrar|p7zip|mediainfo
```

## 📚 Complete Documentation

- **[Examples & Use Cases](EXAMPLES.md)** - Detailed configuration examples
- **[VPN Provider Setup](docs/VPN_PROVIDERS.md)** - Provider-specific guides
- **[Docker Secrets](docs/DOCKER_SECRETS.md)** - Secure credential management
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 🔄 Migration from haugene/transmission-openvpn

| haugene Variable | transmissionvpn Equivalent |
|------------------|---------------------------|
| `OPENVPN_PROVIDER` | Use `VPN_CONFIG` with your `.ovpn` file |
| `OPENVPN_CONFIG` | `VPN_CONFIG` |
| `OPENVPN_USERNAME` | `VPN_USER` |
| `OPENVPN_PASSWORD` | `VPN_PASS` |
| `LOCAL_NETWORK` | `LAN_NETWORK` |
| `WEBPROXY_ENABLED` | `ENABLE_PRIVOXY` |

**Volume changes:**

- `/data` → `/downloads` (for downloads)
- `/data/transmission-home` → `/config` (for settings)

## 🆘 Getting Help

1. **Check the logs**: `docker logs transmissionvpn`
2. **Read the docs**: Links above for detailed guides
3. **Search issues**: [GitHub Issues](https://github.com/magicalyak/transmissionvpn/issues)
4. **Create an issue**: Use our [issue templates](.github/ISSUE_TEMPLATE/)

## ⚙️ All Environment Variables

<details>
<summary>Click to expand complete variable list</summary>

### VPN Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `VPN_CLIENT` | `openvpn` or `wireguard` | `openvpn` |
| `VPN_CONFIG` | Path to VPN config file | (required) |
| `VPN_USER` | VPN username | (required for OpenVPN) |
| `VPN_PASS` | VPN password | (required for OpenVPN) |
| `VPN_OPTIONS` | Additional VPN client options | (none) |
| `FILE__VPN_USER` | Path to file containing VPN username | (none) |
| `FILE__VPN_PASS` | Path to file containing VPN password | (none) |

### Network Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `LAN_NETWORK` | Local network CIDR | (none) |
| `NAME_SERVERS` | Comma-separated DNS servers | (auto) |
| `ADDITIONAL_PORTS` | Extra ports to allow through VPN | (none) |

### Transmission Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `TRANSMISSION_PEER_PORT` | P2P port | (random) |
| `TRANSMISSION_DOWNLOAD_DIR` | Download directory | `/downloads` |
| `TRANSMISSION_INCOMPLETE_DIR` | Incomplete downloads | `/downloads/incomplete` |
| `TRANSMISSION_WATCH_DIR` | Watch directory | `/watch` |
| `TRANSMISSION_WEB_HOME` | Alternative web UI path | (none) |
| `TRANSMISSION_RPC_USERNAME` | Web UI username | (none) |
| `TRANSMISSION_RPC_PASSWORD` | Web UI password | (none) |

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
| `ENABLE_PRIVOXY` | Enable HTTP proxy | `no` |
| `PRIVOXY_PORT` | Privoxy port | `8118` |
| `LOG_TO_STDOUT` | Log to Docker logs | `false` |
| `DEBUG` | Enable debug logging | `false` |
| `HEALTH_CHECK_HOST` | Health check target | `google.com` |
| `METRICS_ENABLED` | Enable metrics collection | `false` |
| `CHECK_DNS_LEAK` | Monitor DNS leaks | `false` |
| `CHECK_IP_LEAK` | Monitor IP leaks | `false` |

</details>
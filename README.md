# 🛡️ Transmission VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Build Status](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Supercharge your Transmission downloads with robust VPN security and an optional Privoxy web proxy! This Docker image bundles the latest Transmission (from `lscr.io/linuxserver/transmission`) with OpenVPN & WireGuard clients, all seamlessly managed by s6-overlay.

**➡️ Get it now from Docker Hub:**

```bash
docker pull magicalyak/transmissionvpn:latest
```

## ✨ Core Features

- **🔒 Secure Transmission:** Runs the latest Transmission with all its traffic automatically routed through your chosen VPN.
- **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients. You choose!
- **📄 Simplified OpenVPN Credentials:**
  - Use environment variables (`VPN_USER`/`VPN_PASS`).
  - Or, simply place a `credentials.txt` file (username on line 1, password on L2) at `/config/openvpn/credentials.txt` inside the container. The script auto-detects it!
- **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
- **💻 Easy Host Access:** Access the Transmission Web UI (port `9091`) and Privoxy (if enabled, default port `8118`) from your Docker host.
- **🗂️ Simple Volume Mounts:** Map `/config` for settings & VPN files, and `/downloads` for your media. Transmission's internal paths are automatically configured for compatibility.
- **🔧 Richly Configurable:** A comprehensive set of environment variables to tailor the container.
- **🚦 Healthcheck:** Built-in healthcheck to monitor Transmission and VPN operational status.

## 🚀 New Enterprise Features

### 🔐 Enhanced Security & Secrets Management
- **Docker Secrets Support:** Secure credential management using `FILE__VPN_USER` and `FILE__VPN_PASS` environment variables
- **Multi-tier Authentication:** Priority-based credential resolution (Docker secrets → environment variables → credential files)
- **Leak Detection:** Optional IP and DNS leak monitoring to ensure VPN integrity
- **Secure File Handling:** Automatic permission management for credential files

### 📊 Advanced Monitoring & Observability
- **Enhanced Healthchecks:** Comprehensive health monitoring with configurable checks for VPN, Transmission, DNS, and connectivity
- **Prometheus Metrics:** Built-in metrics endpoint (`/metrics`) for integration with monitoring systems
- **Real-time Notifications:** Discord, Slack, and webhook notifications for container events and health changes
- **System Metrics:** CPU, memory, disk, and network statistics collection
- **Performance Monitoring:** Response time tracking and interface statistics

### 🛠️ Production-Ready Operations
- **Monitoring Scripts:** External monitoring with `scripts/monitor.sh` for automated health checks and alerting
- **Metrics Server:** Python-based HTTP server (`scripts/metrics-server.py`) for Prometheus integration
- **State Tracking:** Persistent monitoring state with rate limiting and change detection
- **Comprehensive Logging:** Structured logging with configurable levels and automatic log rotation

### 📚 Complete Documentation Suite
- **[VPN Provider Guides](docs/VPN_PROVIDERS.md):** Step-by-step setup for NordVPN, ExpressVPN, Surfshark, ProtonVPN, Mullvad, PIA, and more
- **[Docker Secrets Guide](docs/DOCKER_SECRETS.md):** Complete guide for Docker Swarm, Compose, and Kubernetes secret management
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md):** Comprehensive diagnostic commands and common issue resolution
- **GitHub Templates:** Professional issue templates, PR templates, and community guidelines

### 🔧 Developer Experience
- **GitHub Issue Templates:** Structured bug reports, feature requests, and support templates
- **Pull Request Templates:** Comprehensive PR guidelines with testing checklists
- **Community Support:** Enhanced documentation and examples for all skill levels

## 💾 Volume Mapping: Your Data, Your Rules

Properly mapping volumes is crucial for data persistence and custom configurations.

- **`/config` (Required):** This is the heart of your persistent storage.
  - **Transmission Configuration:** Stores `settings.json`, torrent files, resume data, etc.
  - **VPN Configuration:**
    - Place OpenVPN files (`.ovpn`, certs, keys) in `your_host_config_dir/openvpn/`.
    - **OpenVPN Credentials (Optional File):** For file-based auth, put `credentials.txt` (user L1, pass L2) in `your_host_config_dir/openvpn/credentials.txt`.
    - Place WireGuard files (`.conf`) in `your_host_config_dir/wireguard/`.
- **`/downloads` (Required):** This is where Transmission saves your completed downloads.
- **`/watch` (Optional):** Transmission can monitor this directory for new `.torrent` files to add automatically.

**Example Host Directory Structure 🌳:**

```text
/opt/transmissionvpn_data/      # Your chosen base directory on the host
├── config/                    # Maps to /config in container
│   ├── settings.json          # (Transmission will create/manage this)
│   ├── torrents/              # (Transmission will store .torrent files here)
│   ├── resume/                # (Transmission will store resume data here)
│   ├── openvpn/               # For OpenVPN files
│   │   └── your_provider.ovpn
│   │   └── credentials.txt      # Optional: user on L1, pass on L2
│   │   └── ca.crt             # And any other certs/keys
│   └── wireguard/             # For WireGuard files
│       └── wg0.conf
├── downloads/                 # Maps to /downloads in container
│   ├── movies/
│   └── tv/
└── watch/                     # Optional: Maps to /watch in container
    └── new_torrents_here/
```

## 🚀 Quick Start Guide

This guide focuses on running the pre-built `magicalyak/transmissionvpn` image from Docker Hub.

> 📋 **Need more examples?** Check out [EXAMPLES.md](EXAMPLES.md) for detailed configuration examples including themes, utilities, and various use cases.

### 🐳 Option 1: Docker Run (Minimal Setup)

#### **1. Prepare Your Docker Host System 🛠️**

It's highly recommended to create your host directories *before* running the container:

```bash
# Choose your base directory (e.g., /opt/transmissionvpn_data or ~/transmissionvpn_data)
HOST_DATA_DIR="/opt/transmissionvpn_data" # CHANGEME

mkdir -p "${HOST_DATA_DIR}/config/openvpn"
mkdir -p "${HOST_DATA_DIR}/config/wireguard"
mkdir -p "${HOST_DATA_DIR}/downloads"
mkdir -p "${HOST_DATA_DIR}/watch" # Optional

echo "Host directories created under ${HOST_DATA_DIR}"
```

Place your VPN configuration files into the appropriate subfolders:

- OpenVPN: `${HOST_DATA_DIR}/config/openvpn/`
- WireGuard: `${HOST_DATA_DIR}/config/wireguard/`

#### **2. Run with Docker 🐳**

**Minimal OpenVPN Example:**

```bash
HOST_DATA_DIR="/opt/transmissionvpn_data" # CHANGEME

docker run -d \
  --name transmissionvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  -v "${HOST_DATA_DIR}/watch:/watch" \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/your_provider.ovpn \
  -e VPN_USER=your_vpn_username \
  -e VPN_PASS=your_vpn_password \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/New_York \
  magicalyak/transmissionvpn:latest
```

**Minimal WireGuard Example:**

```bash
HOST_DATA_DIR="/opt/transmissionvpn_data" # CHANGEME

docker run -d \
  --name transmissionvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  -v "${HOST_DATA_DIR}/watch:/watch" \
  -e VPN_CLIENT=wireguard \
  -e VPN_CONFIG=/config/wireguard/wg0.conf \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/New_York \
  magicalyak/transmissionvpn:latest
```

### 🐙 Option 2: Docker Compose (Recommended)

#### **1. Create Directory Structure:**

```bash
mkdir -p transmissionvpn/{data/{config/{openvpn,wireguard},downloads,watch}}
cd transmissionvpn
```

#### **2. Download Files:**

```bash
# Download docker-compose.yml
curl -o docker-compose.yml https://raw.githubusercontent.com/magicalyak/transmissionvpn/main/docker-compose.yml

# Download .env.sample and customize
curl -o .env https://raw.githubusercontent.com/magicalyak/transmissionvpn/main/.env.sample
```

#### **3. Edit `.env` File:**

```bash
nano .env  # Edit with your VPN settings
```

**Example minimal `.env` for OpenVPN:**

```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn
VPN_USER=your_vpn_username
VPN_PASS=your_vpn_password

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York
```

#### **4. Place VPN Files:**

```bash
# Copy your VPN config to data/config/openvpn/ or data/config/wireguard/
cp your_provider.ovpn data/config/openvpn/
```

#### **5. Start Container:**

```bash
docker-compose up -d
```

## 🖥️ Accessing Services

- **Transmission Web UI:** `http://localhost:9091` or `http://YOUR_DOCKER_HOST_IP:9091`
- **🌐 Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, server: `localhost`, port: `PRIVOXY_PORT` (default `8118`)

## 🔄 Migrating from `haugene/transmission-openvpn`

Coming from the popular `haugene/transmission-openvpn` image? Welcome! This section helps you migrate smoothly with key differences and environment variable mapping.

### 🎯 **Key Differences**

| Feature | `haugene/transmission-openvpn` | `magicalyak/transmissionvpn` |
|---------|--------------------------------|------------------------------|
| **Base Image** | Custom Alpine + Transmission | LinuxServer.io Transmission |
| **VPN Support** | OpenVPN only | OpenVPN + WireGuard |
| **Process Manager** | Custom scripts | s6-overlay (more robust) |
| **Volume Structure** | `/data` for downloads | `/downloads` for downloads |
| **Config Location** | `/data/transmission-home` | `/config` |
| **Web Proxy** | Built-in HTTP proxy | Optional Privoxy |
| **Provider Configs** | Built-in provider templates | Bring your own config files |

### 🗂️ **Volume Migration**

**Before (haugene):**
```bash
-v /host/data:/data
-v /host/config:/config
```

**After (magicalyak):**
```bash
-v /host/config:/config          # Transmission settings + VPN configs
-v /host/downloads:/downloads    # Your downloads
-v /host/watch:/watch           # Optional: watch folder
```

**Migration Steps:**
1. **Move Downloads:** Copy `/host/data/completed/*` to `/host/downloads/`
2. **Move Transmission Config:** Copy `/host/data/transmission-home/settings.json` to `/host/config/settings.json`
3. **Copy VPN Files:** Move your `.ovpn` files to `/host/config/openvpn/`

### 📝 **Environment Variable Mapping**

| haugene Variable | magicalyak Equivalent | Notes |
|------------------|----------------------|-------|
| `OPENVPN_PROVIDER` | *Not needed* | Use `VPN_CONFIG` to specify your `.ovpn` file |
| `OPENVPN_CONFIG` | `VPN_CONFIG` | Full path inside container: `/config/openvpn/your.ovpn` |
| `OPENVPN_USERNAME` | `VPN_USER` | Same functionality |
| `OPENVPN_PASSWORD` | `VPN_PASS` | Same functionality |
| `LOCAL_NETWORK` | `LAN_NETWORK` | Same functionality - your LAN CIDR |
| `TRANSMISSION_PEER_PORT` | `TRANSMISSION_PEER_PORT` | Same functionality |
| `TRANSMISSION_DOWNLOAD_DIR` | *Auto-configured* | Always `/downloads` inside container |
| `TRANSMISSION_INCOMPLETE_DIR` | `TRANSMISSION_INCOMPLETE_DIR` | Default: `/downloads/incomplete` |
| `TRANSMISSION_WATCH_DIR` | `TRANSMISSION_WATCH_DIR` | Default: `/watch` inside container |
| `TRANSMISSION_WEB_UI` | *Not needed* | Base image handles UI selection |
| `WEBPROXY_ENABLED` | `ENABLE_PRIVOXY` | Use `yes`/`no` instead of `true`/`false` |
| `WEBPROXY_PORT` | `PRIVOXY_PORT` | Default port changed from `8888` to `8118` |

### 🚀 **Quick Migration Example**

**Your old haugene setup:**
```bash
docker run -d \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -p 8888:8888 \
  -v /opt/transmission:/data \
  -v /opt/transmission/config:/config \
  -e OPENVPN_PROVIDER=PIA \
  -e OPENVPN_CONFIG=netherlands \
  -e OPENVPN_USERNAME=myuser \
  -e OPENVPN_PASSWORD=mypass \
  -e LOCAL_NETWORK=192.168.1.0/24 \
  -e WEBPROXY_ENABLED=true \
  -e WEBPROXY_PORT=8888 \
  haugene/transmission-openvpn
```

**Equivalent magicalyak setup:**
```bash
# 1. Prepare migration (one time)
mkdir -p /opt/transmissionvpn/{config/openvpn,downloads,watch}
cp /opt/transmission/completed/* /opt/transmissionvpn/downloads/
cp /opt/transmission/transmission-home/settings.json /opt/transmissionvpn/config/
cp your_pia_netherlands.ovpn /opt/transmissionvpn/config/openvpn/

# 2. New container
docker run -d \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 9091:9091 \
  -p 8118:8118 \
  -v /opt/transmissionvpn/config:/config \
  -v /opt/transmissionvpn/downloads:/downloads \
  -v /opt/transmissionvpn/watch:/watch \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/your_pia_netherlands.ovpn \
  -e VPN_USER=myuser \
  -e VPN_PASS=mypass \
  -e LAN_NETWORK=192.168.1.0/24 \
  -e ENABLE_PRIVOXY=yes \
  -e PRIVOXY_PORT=8118 \
  -e PUID=1000 \
  -e PGID=1000 \
  magicalyak/transmissionvpn
```

### ⚠️ **Important Migration Notes**

1. **🔧 Provider Configs:** This image doesn't include built-in provider templates. Download your VPN provider's `.ovpn` files manually.

2. **🌐 Proxy Port Change:** Default HTTP proxy port changed from `8888` to `8118`. Update your applications accordingly.

3. **📂 Volume Structure:** The volume mapping is different - plan your directory migration carefully.

4. **🔐 Auth Files:** If you used `/config/openvpn-credentials.txt` with haugene, rename it to `/config/openvpn/credentials.txt` and ensure it has username on line 1, password on line 2.

5. **🎛️ Transmission Settings:** Your existing `settings.json` should work, but some paths may need adjustment in the UI after first run.

### 💡 **Migration Tips**

- **Test First:** Run the new container with temporary volumes to verify your VPN config works
- **Keep Backups:** Don't delete your old data until you've verified everything works
- **Check Logs:** Use `docker logs container_name` to troubleshoot any issues
- **Port Conflicts:** Stop your old container before starting the new one to avoid port conflicts

### ✨ **New Compatible Features**

We've added several features inspired by haugene for compatibility:

| Feature | Environment Variable | Notes |
|---------|---------------------|-------|
| **Alternative Web UIs** | `TRANSMISSION_WEB_UI` | Same as haugene! Supports: `combustion`, `kettu`, `flood-for-transmission`, `transmission-web-control` |
| **Custom Health Check** | `HEALTH_CHECK_HOST` | Same as haugene! Ping custom host instead of `google.com` |
| **Docker Logs Support** | `LOG_TO_STDOUT` | Same as haugene! Send Transmission logs to `docker logs` |

## 📊 Monitoring & Observability Quick Reference

### 🔍 Enhanced Health Monitoring

The container includes comprehensive health monitoring with configurable options:

```bash
# Enable advanced health features
-e METRICS_ENABLED=true          # Enable metrics collection
-e CHECK_DNS_LEAK=true          # Monitor for DNS leaks
-e CHECK_IP_LEAK=true           # Monitor for IP leaks
-e HEALTH_CHECK_HOST=1.1.1.1    # Custom connectivity test host
```

### 📈 Prometheus Metrics Endpoint

Access real-time metrics for monitoring integration:

```bash
# Enable metrics server (runs on port 8080 by default)
docker exec transmissionvpn python3 /scripts/metrics-server.py &

# Access metrics
curl http://localhost:8080/metrics     # Prometheus format
curl http://localhost:8080/health      # JSON health status
curl http://localhost:8080/            # Web interface
```

**Available Metrics:**
- Container health and uptime
- VPN interface status and traffic
- Transmission daemon status and torrent counts
- System resources (CPU, memory, disk)
- Network connectivity and response times

### 🔔 Real-time Notifications

Monitor your container with external notifications:

```bash
# Download monitoring script
curl -o monitor.sh https://raw.githubusercontent.com/magicalyak/transmissionvpn/main/scripts/monitor.sh
chmod +x monitor.sh

# Discord notifications
./monitor.sh --discord "https://discord.com/api/webhooks/YOUR_WEBHOOK"

# Slack notifications  
./monitor.sh --slack "https://hooks.slack.com/services/YOUR_WEBHOOK"

# Multiple notification types with custom interval
./monitor.sh --discord "DISCORD_URL" --slack "SLACK_URL" --interval 30 --level warn
```

**Notification Events:**
- Container start/stop
- Health check failures
- VPN connection issues
- IP address changes
- Transmission daemon status

### 🔐 Docker Secrets Integration

Secure credential management for production deployments:

```yaml
# Docker Compose with secrets
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
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

### 📋 Health Check Commands

Manual health verification commands:

```bash
# Check overall container health
docker exec transmissionvpn /root/healthcheck.sh

# View detailed health logs
docker exec transmissionvpn cat /tmp/healthcheck.log

# Check VPN connectivity
docker exec transmissionvpn ping -c 3 -I tun0 google.com

# Verify external IP (should be VPN IP)
docker exec transmissionvpn curl -s ifconfig.me

# Check Transmission status
docker exec transmissionvpn transmission-remote localhost:9091 -si
```

### 📚 Documentation Links

- **[Complete VPN Provider Setup](docs/VPN_PROVIDERS.md)** - Detailed guides for major VPN providers
- **[Docker Secrets Guide](docs/DOCKER_SECRETS.md)** - Comprehensive secret management documentation  
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and diagnostic commands
- **[Examples](EXAMPLES.md)** - Configuration examples and use cases

## ⚙️ Environment Variables

| Variable | Purpose | Example | Default |
|----------|---------|---------|---------|
| `VPN_CLIENT` | `openvpn` or `wireguard` | `openvpn` | `openvpn` |
| `VPN_CONFIG` | Full path to VPN configuration file | `/config/openvpn/your_provider.ovpn` |
| `VPN_USER` | VPN username | `your_vpn_username` |
| `VPN_PASS` | VPN password | `your_vpn_password` |
| `LAN_NETWORK` | Local network CIDR | `192.168.1.0/24` |
| `TRANSMISSION_PEER_PORT` | Transmission peer port | `9091` |
| `TRANSMISSION_DOWNLOAD_DIR` | Transmission download directory | `/downloads` |
| `TRANSMISSION_INCOMPLETE_DIR` | Transmission incomplete download directory | `/downloads/incomplete` |
| `TRANSMISSION_WATCH_DIR` | Transmission watch directory | `/watch` |
| `ENABLE_PRIVOXY` | Enable Privoxy | `yes` |
| `PRIVOXY_PORT` | Privoxy port | `8118` |
| `PUID` | User ID | `1000` |
| `PGID` | Group ID | `1000` |
| `TZ` | Timezone | `America/New_York` |
| `HEALTH_CHECK_HOST` | Health check host | `google.com` |
| `LOG_TO_STDOUT` | Log to stdout | `yes` |
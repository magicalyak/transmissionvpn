# 🛡️ Transmission VPN Docker

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Build Status](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

An all-in-one Docker container that provides an Alpine-based Transmission Bittorrent client with an OpenVPN or WireGuard connection, plus Privoxy, and DNS-over-HTTPS. It includes a health check to monitor the VPN connection and restart the container if it fails.

## ✨ Key Features

* **🛡️ Enhanced Kill Switch:** Strict iptables rules with default DROP policies prevent any IP leaks
* **🔒 DNS Leak Prevention:** Blocks all DNS queries (port 53) on non-VPN interfaces
* **👁️ Active VPN Monitoring:** Continuously monitors VPN health and stops Transmission if VPN fails
* **⚡ Auto-Recovery:** Optional automatic VPN restart on failure (configurable)
* **🏥 Smart Health Checks:** Container health focuses on Transmission functionality, not VPN status
* **⚡ Lightweight:** Built on Alpine Linux for a minimal footprint
* **🧩 Extensible:** Supports custom scripts and alternative web UIs
* **📊 Metrics & Monitoring:** Built-in Prometheus-compatible metrics endpoint
* **🌐 DNS Over-HTTPS:** Encrypts DNS queries to prevent snooping

## 🏷️ Versioning

This project follows a versioning scheme aligned with the upstream [LinuxServer.io transmission releases](https://github.com/linuxserver/docker-transmission/releases):

### Version Format: `4.0.6-rX`

- **`4.0.6`** - Matches the upstream Transmission version from LinuxServer.io
- **`-rX`** - Our revision number (increments with each release)

### Examples:
- `4.0.6-r1` - First release based on Transmission 4.0.6
- `4.0.6-r2` - Second release with bug fixes/features
- `4.0.6-r7` - Release with comprehensive monitoring stack, Prometheus fixes, troubleshooting tools
- `4.0.6-r20` - Current release (DNS fixes, updated base image and dependencies)

### When We Update:
- **Major/Minor**: When LinuxServer.io updates Transmission (e.g., `4.0.6` → `4.1.0`)
- **Revision**: For our bug fixes, features, or documentation updates

This ensures compatibility with the upstream base image while tracking our enhancements.

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
| `TRANSMISSION_WEB_UI_AUTO` | Auto-download web UI | (none) | `flood` |
| `METRICS_ENABLED` | Enable built-in custom metrics server | `false` | `true` |
| `METRICS_PORT` | Prometheus metrics port | `9099` | `8080` |
| `METRICS_INTERVAL` | Metrics update interval (seconds) | `30` | `60` |
| `TRANSMISSION_PEER_PORT` | BitTorrent peer port | (none) | `51413` |
| `PRIVOXY_PORT` | Privoxy HTTP proxy port | `8118` | `8119` |
| `INTERNAL_METRICS_ENABLED` | Enable internal health metrics | `false` | `true` |
| `CHECK_DNS_LEAK` | Enable DNS leak detection | `false` | `true` |
| `CHECK_IP_LEAK` | Enable IP leak detection | `false` | `true` |

## 📁 Volumes

| Volume | Function | Example |
|--------|----------|---------|
| `/config` | Configuration files and VPN configs | `./config:/config` |
| `/downloads` | Completed downloads | `./downloads:/downloads` |
| `/watch` | Auto-add torrent files | `./watch:/watch` |

## 🌐 Ports

| Port | Function | Required | Configurable |
|------|----------|----------|--------------|
| `9091` | Transmission Web UI | Yes | No |
| `8118` | Privoxy HTTP proxy | No | Via `PRIVOXY_PORT` |
| `9099` | Prometheus metrics endpoint | No | Via `METRICS_PORT` |
| `51413` | BitTorrent peer port | No | Via `TRANSMISSION_PEER_PORT` |

**Dynamic Port Configuration:**
- **Metrics Port**: Set `METRICS_PORT=8080` to use port 8080 instead of 9099
- **BitTorrent Port**: Set `TRANSMISSION_PEER_PORT=6881` to use port 6881 instead of 51413
- **Privoxy Port**: Set `PRIVOXY_PORT=8119` to use port 8119 instead of 8118

The container automatically configures iptables rules for your custom ports. No manual firewall configuration needed!

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

Open <http://localhost:9091> in your browser.

### 5. Verify Everything is Working

```bash
# Run the verification script
./scripts/verify-fixes.sh

# Or manually check
docker exec transmissionvpn /root/healthcheck-fixed.sh
```

## 📊 Monitoring & Metrics

This container provides **two complementary monitoring systems**:

### 🔧 Built-in Custom Metrics Server (Recommended)

**Built-in custom metrics server** that exposes Transmission metrics directly from within the container. No separate services required! This replaces the problematic transmission-exporter with a reliable Python-based solution.

#### 🚀 Quick Setup

1. **Enable the metrics server** in your `.env` file:
   ```bash
   METRICS_ENABLED=true
   METRICS_PORT=9099
   METRICS_INTERVAL=30
   ```

2. **Expose the port** in your `docker-compose.yml`:
   ```yaml
   ports:
     - "9091:9091"    # Transmission Web UI
     - "9099:9099"    # Prometheus metrics (if enabled)
   ```

3. **Start the container**:
   ```bash
   docker-compose up -d
   ```

4. **Verify metrics** are available:
   ```bash
   curl http://localhost:9099/metrics
   curl http://localhost:9099/health
   ```

#### 📈 Prometheus Configuration

Add this scrape configuration to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'transmissionvpn'
    static_configs:
      - targets: ['localhost:9099']  # or your Docker host IP
    scrape_interval: 30s
```

#### 📊 Grafana Dashboards

The custom metrics server provides these key metrics for dashboards:

- **`transmission_torrent_count`** - Total number of torrents
- **`transmission_active_torrents`** - Number of active torrents
- **`transmission_downloading_torrents`** - Number of downloading torrents
- **`transmission_seeding_torrents`** - Number of seeding torrents
- **`transmission_download_rate_bytes_per_second`** - Current download rate
- **`transmission_upload_rate_bytes_per_second`** - Current upload rate
- **`transmission_session_downloaded_bytes`** - Session downloaded bytes
- **`transmission_session_uploaded_bytes`** - Session uploaded bytes

#### 🔧 Features

✅ **Reliable**: No hanging issues like transmission-exporter
✅ **Lightweight**: Pure Python, minimal dependencies
✅ **Session-aware**: Properly handles Transmission's CSRF protection
✅ **Environment-driven**: Configured via environment variables
✅ **Health endpoint**: `/health` for monitoring checks
✅ **Error-resilient**: Continues working even if Transmission restarts

### 🩺 Internal Health Metrics (Advanced)

**Internal metrics collection** for system monitoring and debugging. These metrics are stored in `/tmp/metrics.txt` inside the container.

#### Configuration

```bash
INTERNAL_METRICS_ENABLED=true   # Enable internal metrics collection
CHECK_DNS_LEAK=true             # Enable DNS leak detection
CHECK_IP_LEAK=true              # Enable IP leak detection
```

#### Available Internal Metrics

- **System Health**: CPU usage, memory usage, disk usage
- **VPN Status**: Interface status, connectivity, ping times
- **Network**: Total RX/TX bytes, DNS resolution times
- **Transmission**: Response times, active torrents count
- **Security**: IP leak detection, DNS leak detection

#### Accessing Internal Metrics

```bash
# View current metrics
docker exec transmissionvpn cat /tmp/metrics.txt

# View health logs
docker exec transmissionvpn cat /tmp/healthcheck.log
```

### 🏗️ Advanced Integration

**InfluxDB v2 Scraper:**
- **Target URL**: `http://your-host:9099/metrics`
- **Schedule**: `30s` (or desired interval)
- **Bucket**: Choose your metrics bucket

**Docker Networks:**
If running Prometheus in Docker, ensure both containers are on the same network:
```yaml
networks:
  monitoring:
    external: true
```

### 📋 Metrics Comparison

| Feature | Custom Metrics Server | Internal Health Metrics |
|---------|----------------------|------------------------|
| **Purpose** | External monitoring | Internal debugging |
| **Format** | Prometheus standard | Custom text format |
| **Access** | HTTP endpoint | File inside container |
| **Metrics** | Transmission-focused | System health focused |
| **Use Case** | Grafana dashboards | Troubleshooting |
| **Default** | Disabled | Disabled |
| **Reliability** | High (custom solution) | High |

## 🛡️ VPN Providers

This container works with any OpenVPN or WireGuard provider:

* **NordVPN** - Download configs from account dashboard
* **ExpressVPN** - Get configs from manual setup page  
* **Surfshark** - Download from manual setup section
* **ProtonVPN** - Get configs from downloads page
* **Private Internet Access** - Download from client support
* **PrivadoVPN** - Generate configs from account dashboard
* **Mullvad** - Generate configs from account page

📖 **Provider-specific guides**: [VPN Setup Documentation](docs/VPN_PROVIDERS.md)

## 🎨 Alternative Web UIs

This image supports several alternative web UIs for Transmission. To use one, set the `TRANSMISSION_WEB_UI` environment variable to one of the following values:

* **`flood`** - Modern, feature-rich UI for torrent management.
* **`kettu`** - Clean and responsive web interface.
* **`combustion`** - Sleek, modern, and mobile-friendly.
* **`transmission-web-control`** - A popular alternative with more advanced features.

### Benefits

* ✅ **Automatic download** during the build process.
* ✅ **No additional volumes** or configuration is required.
* ✅ **Seamless integration** with the base image.
* ✅ **Always up-to-date** with the latest version of the UI.

### Manual Installation

For custom UIs, mount your files and use `TRANSMISSION_WEB_HOME`:

```yaml
volumes:
  - ./my-custom-ui:/web-ui:ro
environment:
  - TRANSMISSION_WEB_HOME=/web-ui
```

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

## 🔒 Security Features

### Enhanced VPN Kill Switch
The container implements a multi-layer kill switch to prevent IP leaks:

* **Strict iptables rules** - Default DROP policies on all chains
* **DNS leak prevention** - Blocks port 53 on all non-VPN interfaces
* **Active monitoring** - VPN monitor service checks connectivity every 30 seconds
* **Automatic protection** - Stops Transmission immediately if VPN fails

### Testing the Kill Switch
```bash
# Run the automated test script
./test-killswitch.sh

# Or manually verify
docker exec transmissionvpn /usr/local/bin/vpn-killswitch.sh verify
```

### VPN Monitoring
The VPN monitor service continuously checks:
- VPN interface status
- Network connectivity through VPN
- DNS resolution (optional)
- External IP verification (optional)

Configure monitoring behavior:
```yaml
environment:
  - VPN_CHECK_INTERVAL=30      # Check every 30 seconds
  - VPN_MAX_FAILURES=3         # Stop after 3 failures
  - AUTO_RESTART_VPN=true      # Auto-restart VPN on failure
```

## 🚦 Health Checks

The container includes automatic health monitoring:

* **VPN Connectivity** - Verifies tunnel is active
* **IP Leak Protection** - Blocks traffic if VPN fails
* **DNS Leak Prevention** - Routes DNS through VPN
* **Kill Switch Status** - Monitors firewall rules

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

* **[Configuration Examples](EXAMPLES.md)** - Real-world usage examples
* **[VPN Provider Setup](docs/VPN_PROVIDERS.md)** - Provider-specific guides
* **[Docker Secrets](docs/DOCKER_SECRETS.md)** - Secure credential management
* **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

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

* `/downloads/completed` → `/downloads/complete`
* `/data` → `/downloads`

This means **both directory structures work simultaneously** without requiring configuration changes! Your existing Sonarr/Radarr setup should continue working after migration.

### Migration Options

#### Option 1: Use Automatic Compatibility (Recommended)

This image includes a compatibility layer that automatically maps many of `haugene`'s environment variables to the new ones. For most users, this will be enough.

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
   * **Host:** `transmissionvpn` (or your container name)
   * **Port:** `9091`
   * **Category:** Set appropriate category for TV/Movies
   * **Directory:** Leave empty or use `/downloads/complete/`

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
<summary>Click to expand for a full list of environment variables</summary>

### VPN Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `VPN_CLIENT` | `openvpn` or `wireguard` | `openvpn` |
| `VPN_CONFIG` | Path to VPN config file | (required) |
| `VPN_USER` | VPN username | (required for OpenVPN) |
| `VPN_PASS` | VPN password | (required for OpenVPN) |
| `VPN_OPTIONS` | Additional VPN options | (none) |

### VPN Monitoring & Kill Switch

| Variable | Description | Default |
|----------|-------------|---------|
| `VPN_CHECK_INTERVAL` | Seconds between VPN health checks | `30` |
| `VPN_MAX_FAILURES` | Max failures before stopping Transmission | `3` |
| `CHECK_DNS` | Enable DNS resolution testing | `true` |
| `CHECK_EXTERNAL_IP` | Verify external IP through VPN | `true` |
| `AUTO_RESTART_VPN` | Auto-restart VPN on failure | `false` |

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
| `METRICS_ENABLED` | Built-in custom metrics server | `false` |
| `METRICS_PORT` | Metrics endpoint port | `9099` |
| `METRICS_INTERVAL` | Metrics update interval (seconds) | `30` |
| `INTERNAL_METRICS_ENABLED` | Internal health metrics | `false` |
| `CHECK_DNS_LEAK` | DNS leak detection | `false` |
| `CHECK_IP_LEAK` | IP leak detection | `false` |
| `TRANSMISSION_WEB_UI_AUTO` | Auto-download web UI | (none) |

</details>

A huge thank you to the developers of `haugene/transmission-openvpn` for their incredible work over the years. This project would not be possible without their efforts.

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

## ⚙️ Environment Variables

| Variable | Purpose | Example | Default |
|----------|---------|---------|---------|
| `VPN_CLIENT` | `openvpn` or `wireguard` | `openvpn` | `openvpn` |
| `VPN_CONFIG` | Path to VPN config file **inside container** | `/config/openvpn/your.ovpn` | (auto-detect) |
| `VPN_USER` | OpenVPN username | `myuser` | |
| `VPN_PASS` | OpenVPN password | `mypassword` | |
| `ENABLE_PRIVOXY` | Enable Privoxy (`yes`/`no`) | `no` | `no` |
| `PRIVOXY_PORT` | Internal port for Privoxy service | `8118` | `8118` |
| `PUID` | User ID for Transmission process | `1000` | `911` |
| `PGID` | Group ID for Transmission process | `1000` | `911` |
| `TZ` | Your local timezone | `America/New_York` | `Etc/UTC` |
| `LAN_NETWORK` | Your LAN CIDR to bypass VPN for local access | `192.168.1.0/24` | |
| `DEBUG` | Enable verbose script logging (`true`/`false`) | `false` | `false` |

### Transmission Specific Settings

- `TRANSMISSION_RPC_AUTHENTICATION_REQUIRED`: (`true`|`false`) - Enable/disable password protection for the Web UI. Default: `false`.
- `TRANSMISSION_RPC_USERNAME`: Username for Web UI if authentication is enabled.
- `TRANSMISSION_RPC_PASSWORD`: Password for Web UI if authentication is enabled.
- `TRANSMISSION_PEER_PORT`: Port for incoming P2P connections. Set this for fixed port forwarding.
- `TRANSMISSION_BLOCKLIST_ENABLED`: (`true`|`false`) - Enable/disable peer blocklist. Default: `true`.

For a complete list of variables, see [.env.sample](https://github.com/magicalyak/transmissionvpn/blob/main/.env.sample).

### Setting Environment Variables from Files (Docker Secrets)

This image supports setting any environment variable from a file by prepending `FILE__` to the variable name:

```bash
# Create password file
echo "your_vpn_password" > ./data/config/vpn_password.txt

# In .env file:
FILE__VPN_PASS=/config/vpn_password.txt
```

## 🤔 Troubleshooting Tips

- **Container Exits or VPN Not Connecting?**
  - `docker logs transmissionvpn` for clues
  - Check `VPN_CONFIG` path in `.env` (must be container path, e.g., `/config/...`)
  - Verify credentials and VPN config file contents

- **Transmission UI Not Accessible?**
  - `docker ps` - is it running?
  - `docker logs transmissionvpn` - any errors?
  - Verify `-p` port mappings

- **File Permission Issues?**
  - Ensure `PUID`/`PGID` in `.env` match the owner of your host data directories

## 🩺 Healthcheck

Verifies Transmission UI and VPN tunnel interface activity. If the container is unhealthy, check logs!

## 🧑‍💻 For Developers / Building from Source

Want to tinker or build it yourself?

```bash
git clone https://github.com/magicalyak/transmissionvpn.git
cd transmissionvpn
cp .env.sample .env && nano .env
make build && make run
```

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.

Base image (`lscr.io/linuxserver/transmission`) and bundled software (OpenVPN, WireGuard, Privoxy, Transmission) have their own respective licenses.

## 🙏 Acknowledgements

This project is inspired by the need for a secure, easy-to-use Transmission setup with VPN support. Thanks to the `linuxserver` team for their excellent base image and to the OpenVPN, WireGuard, and Privoxy communities for their contributions to open-source software.

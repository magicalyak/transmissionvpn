# 🛡️ Transmission VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/transmissionvpn)](https://hub.docker.com/r/magicalyak/transmissionvpn) [![Build Status](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/transmissionvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Supercharge your Transmission downloads with robust VPN security and an optional Privoxy web proxy! This Docker image bundles the latest Transmission (from `lscr.io/linuxserver/transmission`) with OpenVPN & WireGuard clients, all seamlessly managed by s6-overlay.

**➡️ Get it now from Docker Hub:**
```bash
docker pull magicalyak/transmissionvpn:latest
```

## ✨ Core Features

*   **🔒 Secure Transmission:** Runs the latest Transmission with all its traffic automatically routed through your chosen VPN.
*   **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients. You choose!
*   **📄 Simplified OpenVPN Credentials:**
    *   Use environment variables (`VPN_USER`/`VPN_PASS`).
    *   Or, simply place a `credentials.txt` file (username on line 1, password on L2) at `/config/openvpn/credentials.txt` inside the container. The script auto-detects it!
*   **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
*   **💻 Easy Host Access:** Access the Transmission Web UI (port `9091`) and Privoxy (if enabled, default port `8118`) from your Docker host as if they were local services.
*   **🗂️ Simple Volume Mounts:** Just map `/config` for Transmission data & all VPN configurations, and `/downloads` for your completed media.
*   **⚙️ Highly Configurable:** A rich set of environment variables to perfectly tailor the container to your needs.
*   **🚦 Healthcheck:** Built-in healthcheck to monitor Transmission and VPN operational status.

## 💾 Volume Mapping: Your Data, Your Rules

Properly mapping volumes is crucial for data persistence and custom configurations.

*   **`/config` (Required):** This is the heart of your persistent storage.
    *   **Transmission Configuration:** Stores all Transmission settings, torrent files, and resume data (managed by the `lscr.io/linuxserver/transmission` base).
    *   **VPN Configuration:**
        *   Place OpenVPN files (`.ovpn`, certs, keys) in `your_host_config_dir/openvpn/`.
        *   **OpenVPN Credentials (Optional File):** For file-based auth, put `credentials.txt` (user L1, pass L2) in `your_host_config_dir/openvpn/credentials.txt`. It's used if `VPN_USER`/`VPN_PASS` are unset.
        *   Place WireGuard files (`.conf`) in `your_host_config_dir/wireguard/`.
*   **`/downloads` (Required):** This is where Transmission saves your completed downloads.
*   **`/watch` (Optional):** Transmission can monitor this directory for new `.torrent` files to add automatically. Map a host directory here if you use this feature.

**Example Host Directory Structure 🌳:**
```
/opt/transmissionvpn_data/      # Your chosen base directory on the host
├── config/                    # Maps to /config in container
│   ├── settings.json          # (Transmission will create/manage this)
│   ├── torrents/              # (Transmission will store .torrent files here)
│   ├── resume/                # (Transmission will store resume data here)
│   ├── openvpn/               # For OpenVPN files
│   │   └── your_provider.ovpn
│   │   └── credentials.txt      # Optional: user on L1, pass on L2
│   │   └── ca.crt             # And any other certs/keys
│   ├── wireguard/             # For WireGuard files
│   │   └── wg0.conf
├── downloads/                 # Maps to /downloads in container
│   ├── movies/
│   └── tv/
└── watch/                     # Optional: Maps to /watch in container
    └── new_torrents_here/
```

**🔄 Migrating from a similar setup?**
*   Host directory previously for `/data` or `/downloads` ➡️ Map to **`/downloads`**.
*   Host directory previously for `/config` (Transmission settings & VPN files) ➡️ Map to **`/config`**. Ensure VPN files are in `openvpn/` or `wireguard/` subfolders. For credentials, use `openvpn/credentials.txt`.

## 🚀 Getting Started: Quick Launch Guide

This guide focuses on running the pre-built `magicalyak/transmissionvpn` image from Docker Hub.

**1. Prepare Your Docker Host System 🛠️**

Create your configuration and downloads directories on your Docker host (as shown in "💾 Volume Mapping"). Example:
```bash
# Create base directory (choose your own path!)
HOST_DATA_DIR="/opt/transmissionvpn_data"

mkdir -p "${HOST_DATA_DIR}/config/openvpn"
mkdir -p "${HOST_DATA_DIR}/config/wireguard"
mkdir -p "${HOST_DATA_DIR}/downloads"
mkdir -p "${HOST_DATA_DIR}/watch" # Optional
```

Place your VPN configuration files into the appropriate subfolders on your host:
*   OpenVPN Config: e.g., `${HOST_DATA_DIR}/config/openvpn/your_provider.ovpn`
*   OpenVPN Credentials (if using file method): Create `${HOST_DATA_DIR}/config/openvpn/credentials.txt` (user L1, pass L2).
*   WireGuard Config: e.g., `${HOST_DATA_DIR}/config/wireguard/wg0.conf`

**2. Create Your `.env` Configuration File 📝**

Create a file named `.env` (e.g., `${HOST_DATA_DIR}/.env`). Refer to `.env.sample` for all options.

**Minimal `.env` for OpenVPN (using `VPN_USER`/`VPN_PASS`):**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # Path *inside the container*
VPN_USER=your_vpn_username
VPN_PASS=your_vpn_password

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York # Set to your timezone!
```

**Minimal `.env` for OpenVPN (using `/config/openvpn/credentials.txt`):**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # Path *inside the container*
# Ensure your_host_config_dir/openvpn/credentials.txt exists.
# VPN_USER and VPN_PASS must be empty or commented out.
# VPN_USER=
# VPN_PASS=

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York # Set to your timezone!
```

**Minimal `.env` for WireGuard:**
```ini
# ---- VPN Settings ----
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/wg0.conf # Path *inside the container*

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York # Set to your timezone!
```

**❗️ Important Notes for `.env`:**
*   `VPN_CONFIG` path is **always the *container's internal path***.
*   If using `credentials.txt`, ensure `VPN_USER`/`VPN_PASS` are unset/empty.
*   Set `PUID`, `PGID`, and `TZ` to match your system and preferences.
*   Consult `.env.sample` for all available environment variables.

**3. Run the Container! 🐳**

Use the following command, adjusting paths to your `.env` file and host directories.

```bash
# Define your host data directory (must match where you put config and downloads)
HOST_DATA_DIR="/opt/transmissionvpn_data"

docker run -d \
  --name transmissionvpn \
  --rm \
  --cap-add=NET_ADMIN \
  # --cap-add=SYS_MODULE \ # Add for WireGuard if kernel module loading is needed
  # --sysctl="net.ipv4.conf.all.src_valid_mark=1" \ # Add for WireGuard
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \  # Add for WireGuard if using IPv6
  --device=/dev/net/tun \
  -p 9091:9091 \
  # -p 8118:8118 \  # Uncomment if ENABLE_PRIVOXY=yes and you want to map it
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  -v "${HOST_DATA_DIR}/watch:/watch" \ # Optional: For auto-adding .torrent files
  --env-file "${HOST_DATA_DIR}/.env" \
  magicalyak/transmissionvpn:latest
```
*Tip: For WireGuard, you might need `--cap-add=SYS_MODULE` and relevant `--sysctl` flags if not already handled by your system. The `Makefile` includes these in its WireGuard example.*

## 🖥️ Accessing Services

*   **Transmission Web UI:** `http://localhost:9091` or `http://YOUR_DOCKER_HOST_IP:9091`
    *   Note: Default Transmission authentication can vary. Check Transmission's `settings.json` in your `/config` volume or its documentation for auth details (RPC username/password). You may need to configure this after the first run.
*   **🌐 Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, server: `localhost`, port: `PRIVOXY_PORT` (default `8118`).

## ⚙️ Environment Variables

| Variable                 | Purpose                                                                    | Example                                  | Default                     |
|--------------------------|----------------------------------------------------------------------------|------------------------------------------|-----------------------------|
| `VPN_CLIENT`             | `openvpn` or `wireguard`                                                   | `openvpn`                                | `openvpn`                   |
| `VPN_CONFIG`             | Path to VPN config file **inside container** (`.ovpn` for OpenVPN, `.conf` for WireGuard). Auto-detects first file if unset. | `/config/openvpn/your.ovpn` or `/config/wireguard/wg0.conf` | (auto-detect)   |
| `VPN_USER`               | OpenVPN username. Used if set with `VPN_PASS`. Overrides `credentials.txt`. | `myuser`                                 |                             |
| `VPN_PASS`               | OpenVPN password. Used if set with `VPN_USER`. Overrides `credentials.txt`. | `mypassword`                             |                             |
| `ENABLE_PRIVOXY`         | Enable Privoxy (`yes`/`no`)                                                | `no`                                     | `no`                        |
| `PRIVOXY_PORT`           | Internal port for Privoxy service                                          | `8118`                                   | `8118`                      |
| `PUID`                   | User ID for Transmission process.                                          | `1000`                                   | (from base image)           |
| `PGID`                   | Group ID for Transmission process.                                         | `1000`                                   | (from base image)           |
| `TZ`                     | Your local timezone.                                                       | `America/New_York`                       | `Etc/UTC`                   |
| `LAN_NETWORK`            | Your LAN CIDR to bypass VPN for local Transmission access.                 | `192.168.1.0/24`                         |                             |
| `NAME_SERVERS`           | Custom DNS servers (comma-separated).                                      | `1.1.1.1,8.8.8.8`                        | (VPN/defaults)              |
| `DEBUG`                  | Enable verbose script logging (`true`/`false`).                            | `false`                                  | `false`                     |
| `VPN_OPTIONS`            | Additional OpenVPN client command-line options.                            | `--inactive 3600 --ping-restart 60`      |                             |
| `UMASK`                  | File creation mask for Transmission.                                       | `002` (LSIO default for Transmission)     | (from base image `022`) |
| `ADDITIONAL_PORTS`       | Comma-separated TCP/UDP ports for outbound allow via iptables.             | `51413,51413/udp`                        |                             |
| `TRANSMISSION_VERSION`   | Informational, corresponds to base image version.                          | `4.0.6` (example)                      | (from Dockerfile)           |


**🔑 OpenVPN Credential Priority:**
1.  If `VPN_USER` and `VPN_PASS` are both set, they will be used.
2.  Else, if `/config/openvpn/credentials.txt` exists and is valid, it's used.
3.  If neither, and your `.ovpn` needs auth, connection may fail.

**💡 A Note on `VPN_PROV` (from other images):**
This image prioritizes flexibility. It doesn't use `VPN_PROV` for auto-provider setup. Instead, you:
1.  **Download** your provider's `.ovpn` or `.conf` file.
2.  **Place it** in `your_host_config_dir/openvpn/` or `your_host_config_dir/wireguard/`.
3.  **Set `VPN_CONFIG`** to its path inside the container (e.g., `/config/openvpn/your_file.ovpn`). Or let it auto-detect if it's the only one.
4.  **Provide credentials** via `VPN_USER`/`VPN_PASS` or `credentials.txt` if needed.
This gives you full control over the exact configuration used.

## 🤔 Troubleshooting Tips

*   **Container Exits or VPN Not Connecting?**
    *   `docker logs transmissionvpn` for clues.
    *   Check `VPN_CONFIG` path in `.env` (must be container path, e.g., `/config/...`).
    *   Verify credentials (in `.env` or `credentials.txt`) and `.ovpn`/`.conf` file contents.
*   **Transmission UI / Privoxy Not Accessible?**
    1.  `docker ps` - is it running?
    2.  `docker logs transmissionvpn` - any errors from Transmission, Privoxy, or VPN setup?
    3.  Verify `-p` port mappings in your `docker run` command.
*   **File Permission Issues?**
    *   Ensure `PUID`/`PGID` in `.env` match the owner of your host data directories (`config/`, `downloads/`, `watch/`). The default umask for `linuxserver/transmission` is usually `002` which is more permissive for group write access than `022`. Consider setting `UMASK=002` in your `.env` file if you face permission issues with other services accessing the downloaded files.

## 🩺 Healthcheck

Verifies Transmission UI and VPN tunnel interface activity. If the container is unhealthy, check logs!

## 🧑‍💻 For Developers / Building from Source

Want to tinker or build it yourself?
1.  **Clone:** `git clone https://github.com/magicalyak/transmissionvpn.git && cd transmissionvpn`
2.  **Customize `.env`:** `cp .env.sample .env && nano .env`
3.  **Build & Run via Makefile:** Explore `make build`, `make run`, `make shell`, etc. The `Makefile` provides convenient targets.
    *   You can also build directly with `docker build -t yourname/transmissionvpn .`

*(The GitHub Container Registry `ghcr.io/magicalyak/transmissionvpn` is also available if you prefer it over Docker Hub for development builds or specific versions.)*

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.
Base image (`lscr.io/linuxserver/transmission`) and bundled software (OpenVPN, WireGuard, Privoxy, Transmission) have their own respective licenses.

## 🙏 Acknowledgements
This project is inspired by the need for a secure, easy-to-use Transmission setup with VPN support. Thanks to the `linuxserver` team for their excellent base image and to the OpenVPN, WireGuard, and Privoxy communities for their contributions to open-source software.

<!-- Workflow trigger -->

### `ADDITIONAL_PORTS`

Comma-separated list of additional TCP or UDP ports (e.g., `51413`, `51413/udp`) that should be allowed for *outbound* traffic originating from within the container, through the VPN tunnel. This does NOT publish these ports from the container to the host. For Transmission, you might need to allow its listening port (`TRANSMISSION_PEER_PORT`) here if UPnP/NAT-PMP fails and you want to ensure connectivity *through the VPN* for incoming peer connections.

### `TRANSMISSION_VERSION` (Informational)

Reflects the version of the `lscr.io/linuxserver/transmission` base image, set in the `Dockerfile`.

### Transmission Specific Settings

These variables are passed directly to the underlying `linuxserver/transmission` base image and control the behavior of the Transmission daemon. Many of these correspond to settings in Transmission's `settings.json` file.

*   `TRANSMISSION_RPC_AUTHENTICATION_REQUIRED`: (`true`|`false`) - Enable/disable password protection for the Web UI. Default: `false`.
*   `TRANSMISSION_RPC_USERNAME`: Username for Web UI if authentication is enabled.
*   `TRANSMISSION_RPC_PASSWORD`: Password for Web UI if authentication is enabled.
*   `TRANSMISSION_RPC_HOST_WHITELIST`: Comma-separated list of IP addresses/ranges to allow Web UI access from (e.g., `'127.0.0.1,192.168.*.*,10.*.*.*,172.16.*.*'`). Default allows common private networks.
*   `TRANSMISSION_RPC_WHITELIST_ENABLED`: (`true`|`false`) - Enable/disable the host whitelist. Default: `true`.
*   `TRANSMISSION_PEER_PORT`: Port Transmission uses for incoming P2P connections (TCP and UDP). If blank, a random port is usually chosen. Set this if you need a fixed port (e.g., for port forwarding). Ensure this port is also listed in `ADDITIONAL_PORTS` if you want to allow it through the VPN.
*   `TRANSMISSION_INCOMPLETE_DIR`: Path *inside the container* for partially downloaded files. If enabled, the base image usually defaults this to `/downloads/incomplete`.
*   `TRANSMISSION_INCOMPLETE_DIR_ENABLED`: (`true`|`false`) - Enable/disable the incomplete downloads directory feature. Default: `true`.
*   `TRANSMISSION_WATCH_DIR_ENABLED`: (`true`|`false`) - Enable/disable watching the `/watch` directory for `.torrent` files. The watch directory itself is fixed at `/watch` via volume mount. Default: `true`.
*   `TRANSMISSION_BLOCKLIST_ENABLED`: (`true`|`false`) - Enable/disable the peer blocklist feature. Default: `true`.
*   `TRANSMISSION_BLOCKLIST_URL`: URL of the blocklist to download. The base image has a default. Example: `"http://john.bitsurge.net/public/biglist.p2p.gz"`.

For more details on some of these, refer to the [linuxserver/transmission documentation](https://docs.linuxserver.io/images/docker-transmission).

### Setting Environment Variables from Files (Docker Secrets)

This image, by virtue of using a `linuxserver.io` base, supports setting any environment variable from a file. This is useful for sensitive information like passwords if you prefer not to have them directly in your `.env` file or `docker-compose.yml`.

To use this feature, prepend `FILE__` to the environment variable name and set its value to the path of a file *inside the container* that contains the secret.

For example, to set `VPN_PASS` from a file named `vpn_password.txt` located in your host's `./config` directory (which is mounted to `/config` in the container):

1.  Create `./config/vpn_password.txt` on your host with your VPN password as its content.
2.  In your `.env` file, set:
    ```env
    FILE__VPN_PASS=/config/vpn_password.txt
    ```

This will instruct the container to read the contents of `/config/vpn_password.txt` and use that as the value for the `VPN_PASS` environment variable.

## Volumes
# 🛡️ NZBGet VPN Docker 🚀

<!-- DOCKER_PULLS_BADGE --> <!-- DOCKER_STARS_BADGE --> <!-- BUILD_STATUS_BADGE --> <!-- LICENSE_BADGE -->

Supercharge your NZBGet downloads with robust VPN security and an optional Privoxy web proxy! This Docker image bundles the latest NZBGet (from `linuxserver/nzbget`) with OpenVPN & WireGuard clients, all seamlessly managed by s6-overlay.

**➡️ Get it now from Docker Hub:**
```bash
docker pull magicalyak/nzbgetvpn:latest
```

## ✨ Core Features

*   **🔒 Secure NZBGet:** Runs the latest NZBGet with all its traffic automatically routed through your chosen VPN.
    *   🔑 **Default Login:** Username: `nzbget`, Password: `tegbzn6789` (Don't forget to change this in NZBGet settings!)
*   **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients. You choose!
*   **📄 Simplified OpenVPN Credentials:**
    *   Use environment variables (`VPN_USER`/`VPN_PASS`).
    *   Or, simply place a `credentials.txt` file (username on line 1, password on L2) at `/config/openvpn/credentials.txt` inside the container. The script auto-detects it!
*   **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
*   **💻 Easy Host Access:** Access the NZBGet Web UI (port `6789`) and Privoxy (if enabled, default port `8118`) from your Docker host as if they were local services.
*   **🗂️ Simple Volume Mounts:** Just map `/config` for NZBGet data & all VPN configurations, and `/downloads` for your completed media.
*   **⚙️ Highly Configurable:** A rich set of environment variables to perfectly tailor the container to your needs.
*   **🚦 Healthcheck:** Built-in healthcheck to monitor NZBGet and VPN operational status.

## 💾 Volume Mapping: Your Data, Your Rules

Properly mapping volumes is crucial for data persistence and custom configurations.

*   **`/config` (Required):** This is the heart of your persistent storage.
    *   **NZBGet Configuration:** Stores all NZBGet settings, history, scripts, and queue files (managed by the `linuxserver/nzbget` base).
    *   **VPN Configuration:**
        *   Place OpenVPN files (`.ovpn`, certs, keys) in `your_host_config_dir/openvpn/`.
        *   **OpenVPN Credentials (Optional File):** For file-based auth, put `credentials.txt` (user L1, pass L2) in `your_host_config_dir/openvpn/credentials.txt`. It's used if `VPN_USER`/`VPN_PASS` are unset.
        *   Place WireGuard files (`.conf`) in `your_host_config_dir/wireguard/`.
*   **`/downloads` (Required):** This is where NZBGet saves your completed downloads. Subdirectories (`intermediate`, `completed`, `nzb`, etc.) are managed by NZBGet's settings within this volume.

**Example Host Directory Structure 🌳:**
```
/opt/nzbgetvpn_data/      # Your chosen base directory on the host
├── config/                # Maps to /config in container
│   ├── nzbget.conf        # (NZBGet will create/manage this)
│   ├── openvpn/           # For OpenVPN files
│   │   └── your_provider.ovpn
│   │   └── credentials.txt  # Optional: user on L1, pass on L2
│   │   └── ca.crt         # And any other certs/keys
│   ├── wireguard/         # For WireGuard files
│   │   └── wg0.conf
└── downloads/             # Maps to /downloads in container
    ├── movies/            # (NZBGet might create these, or you can)
    └── tv/
```

**🔄 Migrating from `jshridha/docker-nzbgetvpn` or similar?**
*   Host directory previously for `/data` (downloads) ➡️ Map to **`/downloads`**.
*   Host directory previously for `/config` (NZBGet settings & VPN files) ➡️ Map to **`/config`**. Ensure VPN files are in `openvpn/` or `wireguard/` subfolders. For credentials, use `openvpn/credentials.txt`.

## 🚀 Getting Started: Quick Launch Guide

This guide focuses on running the pre-built `magicalyak/nzbgetvpn` image from Docker Hub.

**1. Prepare Your Docker Host System 🛠️**

Create your configuration and downloads directories on your Docker host (as shown in "💾 Volume Mapping"). Example:
```bash
# Create base directory (choose your own path!)
HOST_DATA_DIR="/opt/nzbgetvpn_data"

mkdir -p "${HOST_DATA_DIR}/config/openvpn"
mkdir -p "${HOST_DATA_DIR}/config/wireguard"
mkdir -p "${HOST_DATA_DIR}/downloads"
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
HOST_DATA_DIR="/opt/nzbgetvpn_data"

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  # --cap-add=SYS_MODULE \ # Add for WireGuard if kernel module loading is needed
  # --sysctl="net.ipv4.conf.all.src_valid_mark=1" \ # Add for WireGuard
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \  # Add for WireGuard if using IPv6
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p 8118:8118 \  # Uncomment if ENABLE_PRIVOXY=yes and you want to map it
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  --env-file "${HOST_DATA_DIR}/.env" \
  magicalyak/nzbgetvpn:latest
```
*Tip: For WireGuard, you might need `--cap-add=SYS_MODULE` and relevant `--sysctl` flags if not already handled by your system. The `Makefile` includes these in its WireGuard example.*

## 🖥️ Accessing Services

*   **NZBGet Web UI:** `http://localhost:6789`
    *   🔑 **Default Login:** Username: `nzbget`, Password: `tegbzn6789`
    *   *(Remember to change the password in NZBGet settings after your first login!)*
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
| `PUID`                   | User ID for NZBGet process.                                                | `1000`                                   | (from base image)           |
| `PGID`                   | Group ID for NZBGet process.                                               | `1000`                                   | (from base image)           |
| `TZ`                     | Your local timezone.                                                       | `America/New_York`                       | `Etc/UTC`                   |
| `LAN_NETWORK`            | Your LAN CIDR to bypass VPN for local NZBGet access.                     | `192.168.1.0/24`                         |                             |
| `NAME_SERVERS`           | Custom DNS servers (comma-separated).                                      | `1.1.1.1,8.8.8.8`                        | (VPN/defaults)              |
| `DEBUG`                  | Enable verbose script logging (`true`/`false`).                            | `false`                                  | `false`                     |
| `VPN_OPTIONS`            | Additional OpenVPN client command-line options.                            | `--inactive 3600 --ping-restart 60`      |                             |
| `UMASK`                  | File creation mask for NZBGet.                                             | `022`                                    | (from base image)           |
| `ADDITIONAL_PORTS`       | Comma-separated TCP/UDP ports for outbound allow via iptables.             | `9090,53/udp`                          |                             |

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
    *   `docker logs nzbgetvpn` for clues.
    *   Check `VPN_CONFIG` path in `.env` (must be container path, e.g., `/config/...`).
    *   Verify credentials (in `.env` or `credentials.txt`) and `.ovpn`/`.conf` file contents.
*   **NZBGet UI / Privoxy Not Accessible?**
    1.  `docker ps` - is it running?
    2.  `docker logs nzbgetvpn` - any errors from NZBGet, Privoxy, or VPN setup?
    3.  Verify `-p` port mappings in your `docker run` command.
*   **File Permission Issues?**
    *   Ensure `PUID`/`PGID` in `.env` match the owner of your host data directories (`config/` and `downloads/`).

## 🩺 Healthcheck

Verifies NZBGet UI and VPN tunnel interface activity. If the container is unhealthy, check logs!

## 🧑‍💻 For Developers / Building from Source

Want to tinker or build it yourself?
1.  **Clone:** `git clone https://github.com/magicalyak/nzbgetvpn.git && cd nzbgetvpn`
2.  **Customize `.env`:** `cp .env.sample .env && nano .env`
3.  **Build & Run via Makefile:** Explore `make build`, `make run`, `make shell`, etc. The `Makefile` provides convenient targets.
    *   You can also build directly with `docker build -t yourname/nzbgetvpn .`

*(The GitHub Container Registry `ghcr.io/magicalyak/nzbgetvpn` is also available if you prefer it over Docker Hub for development builds or specific versions.)*

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.
Base image (`linuxserver/nzbget`) and bundled software (OpenVPN, WireGuard, Privoxy, NZBGet) have their own respective licenses.
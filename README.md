# NZBGet with VPN & Privoxy Docker Image 🛡️🚀

Secure your NZBGet downloads and optionally proxy your web traffic through a VPN! This Docker image bundles NZBGet with OpenVPN/WireGuard clients and an optional Privoxy HTTP proxy, all managed with the reliable s6-overlay.

**Ready to go? Pull it from Docker Hub:**
```bash
docker pull magicalyak/nzbgetvpn:latest
```

## ✨ Core Features

*   **🔒 Secure NZBGet:** Runs the latest NZBGet from `linuxserver/nzbget` with all its traffic routed through your chosen VPN.
*   **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients using a single `VPN_CONFIG` variable.
*   **📄 Flexible OpenVPN Credentials:** Use environment variables (`VPN_USER`/`VPN_PASS`) or a dedicated credentials file (`VPN_CREDENTIALS_FILE`).
*   **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
*   **💻 Host Access:** Easily access the NZBGet Web UI (port `6789`) and Privoxy (if enabled, default port `8118`) from your Docker host.
*   ** ਸਿੰ Simple Volume Mounts:** Mount a single `/config` volume for NZBGet data and VPN configurations.
*   **⚙️ Highly Configurable:** Extensive environment variables to tailor it to your needs.
*   **🚦 Healthcheck:** Built-in healthcheck to monitor NZBGet and VPN status.

## 🚀 Getting Started: Running the Docker Container

This guide will walk you through running the pre-built image from Docker Hub.

**1. Prepare Your Docker Host System 🛠️**

You'll need to create a main directory on your Docker host. This directory will be mounted into the container at `/config` and will store:
*   Your OpenVPN configuration files (e.g., `.ovpn`, credentials file) in a subfolder named `openvpn`.
*   Your WireGuard configuration files (e.g., `.conf`) in a subfolder named `wireguard`.
*   NZBGet's persistent application data (this will also be stored under the main `/config` path by NZBGet).

You also need a directory for your downloads.

Create these directories, for example:
```bash
mkdir -p /opt/nzbgetvpn_data/config # This will be mounted to /config in the container
mkdir -p /opt/nzbgetvpn_data/downloads
```
*(Feel free to choose a different location than `/opt/nzbgetvpn_data/`!)*

Now, place your VPN configuration files into the appropriate subfolders within your `config` directory on the host:
*   For OpenVPN: `/opt/nzbgetvpn_data/config/openvpn/your_provider.ovpn`
*   For WireGuard: `/opt/nzbgetvpn_data/config/wireguard/wg0.conf`
*   If using an OpenVPN credentials file: `/opt/nzbgetvpn_data/config/vpn_credentials.txt`

**2. Create Your `.env` Configuration File 📝**

Create a file named `.env` alongside your `config` and `downloads` directories (e.g., `/opt/nzbgetvpn_data/.env`).

**Minimal `.env` for OpenVPN (using user/pass variables):**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # Path *inside the container*
VPN_USER=your_vpn_username
VPN_PASS=your_vpn_password

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York
```

**Minimal `.env` for OpenVPN (using a credentials file):**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn     # Path *inside the container*
VPN_CREDENTIALS_FILE=/config/vpn_credentials.txt # Path *inside the container*
# Ensure vpn_credentials.txt exists in your host's config directory
# with username on line 1, password on line 2.

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York
```

**Minimal `.env` for WireGuard:**
```ini
# ---- VPN Settings ----
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/wg0.conf # Path *inside the container*

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York
```

**Important Notes for `.env`:**
*   The `VPN_CONFIG` and `VPN_CREDENTIALS_FILE` paths **must point to the location *inside the container***.
*   Set `PUID`, `PGID`, and `TZ` according to your host system.
*   See the full "⚙️ Environment Variables" section for all options.

**3. Run the Container! 🏃‍♀️**

(Docker run examples remain the same as they already use a single `/config` mount and `--env-file`)

**Example for OpenVPN / WireGuard (adjust `.env` file for client type):**
```bash
docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  # --cap-add=SYS_MODULE \ # Add for WireGuard if kernel module loading is needed
  # --sysctl="net.ipv4.conf.all.src_valid_mark=1" \ # Add for WireGuard
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \  # Add for WireGuard if using IPv6
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p 8118:8118 \  # Uncomment for Privoxy
  -v /opt/nzbgetvpn_data/config:/config \
  -v /opt/nzbgetvpn_data/downloads:/downloads \
  --env-file /opt/nzbgetvpn_data/.env \
  magicalyak/nzbgetvpn:latest
```
*Note: The WireGuard example in the `Makefile` includes `--cap-add=SYS_MODULE` and relevant `--sysctl` flags. Add these to your manual `docker run` command if using WireGuard and they are needed on your system.*

## 🖥️ Accessing Services

*   **NZBGet Web UI:** `http://localhost:6789`
*   **Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, server: `localhost`, port: `PRIVOXY_PORT` (default `8118`).

## ⚙️ Environment Variables

| Variable                 | Purpose                                                                    | Example                                  | Default                     |
|--------------------------|----------------------------------------------------------------------------|------------------------------------------|-----------------------------|
| `VPN_CLIENT`             | `openvpn` or `wireguard`                                                   | `openvpn`                                | `openvpn`                   |
| `VPN_CONFIG`             | Path to VPN config file **inside container** (`.ovpn` for OpenVPN, `.conf` for WireGuard) | `/config/openvpn/your.ovpn` or `/config/wireguard/wg0.conf` | (auto-detect first file)   |
| `VPN_USER`               | OpenVPN username (if not using `VPN_CREDENTIALS_FILE`)                     | `myuser`                                 |                             |
| `VPN_PASS`               | OpenVPN password (if not using `VPN_CREDENTIALS_FILE`)                     | `mypassword`                             |                             |
| `VPN_CREDENTIALS_FILE`   | Path to OpenVPN credentials file **inside `/config/`** (user on L1, pass on L2) | `/config/vpn_credentials.txt`            |                             |
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

## 🤔 Troubleshooting Tips

*   **Container Exits or VPN Not Connecting?**
    *   Run `docker logs nzbgetvpn`.
    *   Check `VPN_CONFIG` / `VPN_CREDENTIALS_FILE` paths in `.env` (must be container paths).
    *   Verify credentials and VPN config file contents.
*   **NZBGet UI / Privoxy Not Accessible?**
    1.  `docker ps` to confirm it's running.
    2.  `docker logs nzbgetvpn` for NZBGet/VPN status.
    3.  Verify `-p` port mappings.
*   **File Permission Issues?**
    *   Ensure `PUID`/`PGID` in `.env` match owner of host data dirs.

## 🩺 Healthcheck

Verifies NZBGet UI and VPN tunnel interface activity.

## 🧑‍💻 For Developers / Building from Source

(Details remain largely the same, ensure `.env.sample` is updated)

1.  **Clone:** `git clone https://github.com/magicalyak/nzbgetvpn.git && cd nzbgetvpn`
2.  **`.env`:** `cp .env.sample .env && nano .env`
3.  **Makefile:** `make build`, `make run`, etc.

## 📄 License

MIT License. Base image and bundled software have their own licenses.
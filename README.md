# NZBGet with VPN & Privoxy Docker Image 🛡️🚀

Secure your NZBGet downloads and optionally proxy your web traffic through a VPN! This Docker image bundles NZBGet with OpenVPN/WireGuard clients and an optional Privoxy HTTP proxy, all managed with the reliable s6-overlay.

**Ready to go? Pull it from Docker Hub:**
```bash
docker pull magicalyak/nzbgetvpn:latest
```

## ✨ Core Features

*   **🔒 Secure NZBGet:** Runs the latest NZBGet from `linuxserver/nzbget` with all its traffic routed through your chosen VPN.
*   **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients.
*   **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
*   **💻 Host Access:** Easily access the NZBGet Web UI (port `6789`) and Privoxy (if enabled, default port `8118`) from your Docker host.
*   **⚙️ Highly Configurable:** Extensive environment variables to tailor it to your needs.
*   **🚦 Healthcheck:** Built-in healthcheck to monitor NZBGet and VPN status.

## 🚀 Getting Started: Running the Docker Container

This guide will walk you through running the pre-built image from Docker Hub.

**1. Prepare Your Docker Host System 🛠️**

You'll need to create a few directories on your Docker host. These will be used to store:
*   Your VPN configuration files (`.ovpn` or `.conf`).
*   NZBGet's persistent application data (so your settings aren't lost when the container restarts).
*   Your downloaded files.

Create a main directory for this container's data, for example:
```bash
mkdir -p /opt/nzbgetvpn_data/openvpn_configs
mkdir -p /opt/nzbgetvpn_data/wireguard_configs
mkdir -p /opt/nzbgetvpn_data/nzbget_config
mkdir -p /opt/nzbgetvpn_data/downloads
```
*(Feel free to choose a different location than `/opt/nzbgetvpn_data/`!)*

**2. Create Your `.env` Configuration File 📝**

This is the most important step! The `.env` file tells the container how to connect to your VPN, your user/group IDs for file permissions, your timezone, and other settings.

Create a file named `.env` inside your main data directory (e.g., `/opt/nzbgetvpn_data/.env`).

**Minimal `.env` for OpenVPN:**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # IMPORTANT: This is the path *inside the container*
VPN_USER=your_vpn_username
VPN_PASS=your_vpn_password

# ---- System Settings ----
PUID=1000 # Your user ID (run `id -u` on your host)
PGID=1000 # Your group ID (run `id -g` on your host)
TZ=America/New_York # Your timezone (e.g., Europe/London, Australia/Sydney)

# ---- Optional Privoxy ----
# ENABLE_PRIVOXY=yes
# PRIVOXY_PORT=8118
```

**Minimal `.env` for WireGuard:**
```ini
# ---- VPN Settings ----
VPN_CLIENT=wireguard
WG_CONFIG_FILE=/config/wireguard/wg0.conf # IMPORTANT: This is the path *inside the container*

# ---- System Settings ----
PUID=1000 # Your user ID (run `id -u` on your host)
PGID=1000 # Your group ID (run `id -g` on your host)
TZ=America/New_York # Your timezone

# ---- Optional Privoxy ----
# ENABLE_PRIVOXY=yes
# PRIVOXY_PORT=8118
```

**Important Notes for `.env`:**
*   Place your actual VPN configuration file (e.g., `your_provider.ovpn` or `wg0.conf`) into the corresponding `openvpn_configs` or `wireguard_configs` directory you created on your host.
*   The `VPN_CONFIG` and `WG_CONFIG_FILE` paths in the `.env` file **must point to the location *inside the container*** (e.g., `/config/openvpn/your_file.ovpn` or `/config/wireguard/your_file.conf`). The `docker run` command (next step) will map your host directories to these container paths.
*   For `PUID` and `PGID`, use the user and group ID that owns the `nzbget_config` and `downloads` directories on your host to avoid permission issues. You can find these by running `id -u yourusername` and `id -g yourusername` on your Linux host.
*   See the full "⚙️ Environment Variables" section below for all available options!

**3. Run the Container! 🏃‍♀️**

Now, open your terminal and use one of the following `docker run` commands. Remember to:
*   Replace `/opt/nzbgetvpn_data/` with the actual path to your data directory.
*   Adjust other settings (like ports if you changed `PRIVOXY_PORT`) as needed.

**Example for OpenVPN:**
```bash
docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p 8118:8118 \  # Uncomment if you set ENABLE_PRIVOXY=yes (and PRIVOXY_PORT is 8118)
  -v /opt/nzbgetvpn_data/openvpn_configs:/config/openvpn:ro \
  -v /opt/nzbgetvpn_data/nzbget_config:/config \
  -v /opt/nzbgetvpn_data/downloads:/downloads \
  --env-file /opt/nzbgetvpn_data/.env \
  magicalyak/nzbgetvpn:latest
```

**Example for WireGuard:**
```bash
docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --sysctl="net.ipv6.conf.all.disable_ipv6=0" \ # Recommended if using IPv6 with WireGuard
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p 8118:8118 \  # Uncomment if you set ENABLE_PRIVOXY=yes (and PRIVOXY_PORT is 8118)
  -v /opt/nzbgetvpn_data/wireguard_configs:/config/wireguard:ro \
  -v /opt/nzbgetvpn_data/nzbget_config:/config \
  -v /opt/nzbgetvpn_data/downloads:/downloads \
  --env-file /opt/nzbgetvpn_data/.env \
  magicalyak/nzbgetvpn:latest
```

**Quick Port Explanation for `docker run`:**
*   `-p 6789:6789`: Maps port `6789` on your host to port `6789` in the container (for NZBGet UI).
*   `-p <host_privoxy_port>:<container_privoxy_port>`: If you enable Privoxy and use a custom `PRIVOXY_PORT` in your `.env` file, make sure to map it. For example, if `PRIVOXY_PORT=8119`, you would use `-p 8119:8119`.

## 🖥️ Accessing Services

*   **NZBGet Web UI:** Open your browser to `http://localhost:6789` (or `http://your-docker-host-ip:6789`).
*   **Privoxy HTTP Proxy:** If you set `ENABLE_PRIVOXY=yes` in your `.env` file:
    *   Proxy Server/Host: `localhost` (or `your-docker-host-ip`).
    *   Port: The value of `PRIVOXY_PORT` from your `.env` file (defaults to `8118`).

## ⚙️ Environment Variables

This container is highly configurable using environment variables set in your `.env` file.

| Variable         | Purpose                                                                 | Example                              | Default (if any) |
|------------------|-------------------------------------------------------------------------|--------------------------------------|------------------|
| `VPN_CLIENT`     | `openvpn` or `wireguard`                                                | `openvpn`                            | `openvpn`        |
| `VPN_CONFIG`     | Path to OpenVPN `.ovpn` file **inside the container**                   | `/config/openvpn/your_provider.ovpn` | (auto-detect first .ovpn)    |
| `VPN_USER`       | OpenVPN username                                                        | `myuser`                             |                  |
| `VPN_PASS`       | OpenVPN password                                                        | `mypassword`                         |                  |
| `WG_CONFIG_FILE` | Path to WireGuard `.conf` file **inside the container**                 | `/config/wireguard/wg0.conf`         | (auto-detect first .conf)    |
| `ENABLE_PRIVOXY` | Enable Privoxy (`yes`/`no`)                                             | `no`                                 | `no`             |
| `PRIVOXY_PORT`   | Internal port for Privoxy service (also used for host mapping)          | `8118`                               | `8118`           |
| `PUID`           | User ID for NZBGet process. Set to match owner of host data dirs.       | `1000`                               | (from base image)      |
| `PGID`           | Group ID for NZBGet process. Set to match owner of host data dirs.      | `1000`                               | (from base image)      |
| `TZ`             | Your local timezone.                                                    | `America/New_York`                   | `Etc/UTC`        |
| `LAN_NETWORK`    | Your LAN CIDR (e.g., `192.168.1.0/24`) to bypass VPN for local NZBGet access. | `192.168.1.0/24`                     |                  |
| `NAME_SERVERS`   | Custom DNS servers (comma-separated). Overrides VPN-provided DNS.       | `1.1.1.1,8.8.8.8`                    | (VPN/defaults)   |
| `DEBUG`          | Enable verbose script logging (`true`/`false`) for troubleshooting.     | `false`                              | `false`          |
| `VPN_OPTIONS`    | Additional OpenVPN client command-line options.                         | `--inactive 3600 --ping-restart 60`  |                  |
| `UMASK`          | File creation mask for NZBGet (e.g., `002` for more permissive).        | `022`                                | (from base image, often 022) |
| `ADDITIONAL_PORTS`| Comma-separated TCP/UDP ports for outbound allow via iptables (e.g., for specific trackers). | `9090,53/udp`                      |                  |


## 🤔 Troubleshooting Tips

*   **Container Exits or VPN Not Connecting?**
    *   Run `docker logs nzbgetvpn` (or whatever you named your container) to see the startup logs.
    *   The `50-vpn-setup` script (part of the container startup) provides detailed VPN connection logs.
    *   Double-check `VPN_CONFIG` / `WG_CONFIG_FILE` paths in your `.env` file – they must be the *container paths*.
    *   Verify `VPN_USER` / `VPN_PASS` for OpenVPN.
    *   Ensure your `.ovpn` or `.conf` file is correctly formatted and placed in the host directory mapped to `/config/openvpn` or `/config/wireguard`.
*   **NZBGet UI / Privoxy Not Accessible?**
    1.  Confirm the container is running: `docker ps`.
    2.  Check `docker logs nzbgetvpn`. Look for NZBGet startup messages (e.g., `nzbget runs on 0.0.0.0:6789`) and successful VPN connection. The firewall rules for host access depend on the VPN being active.
    3.  Verify your `-p` port mappings in your `docker run` command.
*   **File Permission Issues in `/config` or `/downloads`?**
    *   Ensure `PUID` and `PGID` in your `.env` file match the user/group ID that owns the corresponding data directories on your Docker host.

## 🩺 Healthcheck

This image includes a healthcheck that periodically verifies:
*   NZBGet's web interface is responsive.
*   The VPN tunnel interface (e.g., `tun0` for OpenVPN, or the interface name in your WireGuard config) is active.
Docker uses this to determine if the container is operating correctly.

## 🧑‍💻 For Developers / Building from Source

If you prefer to build the image yourself or want to contribute:

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/magicalyak/nzbgetvpn.git
    cd nzbgetvpn
    ```
2.  **Prepare `.env` File:**
    Copy `.env.sample` to `.env` in the repository root and customize it.
    ```bash
    cp .env.sample .env
    nano .env
    ```
3.  **Use the `Makefile`:**
    *   `make build`: Build the Docker image.
    *   `make run` or `make run-openvpn`: Run with OpenVPN (uses settings from `.env`).
    *   `make run-wireguard`: Run with WireGuard (uses settings from `.env`).
    *   `make logs`: Follow container logs.
    *   `make stop`: Stop and remove the container.
    *   `make shell`: Get a shell inside the running container.
    *   `make clean`: Stop container and offer to remove the image.
    *   `make help`: Show all available targets.

The `Dockerfile`, VPN setup scripts (`root/`), and s6-overlay service scripts (`root_s6/`) are available for inspection and modification if you're customizing the build.

## 📄 License

This project is licensed under the [MIT License](LICENSE).
Base image (`linuxserver/nzbget`) and bundled software (NZBGet, OpenVPN, WireGuard, Privoxy) have their own respective licenses.
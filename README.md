# NZBGet with VPN and Privoxy Docker Image

This Docker image provides a convenient way to run NZBGet, a popular binary newsreader, with all its traffic (and optionally other HTTP/HTTPS traffic via Privoxy) routed through a VPN connection. It supports both OpenVPN and WireGuard VPN clients. The image is based on the robust `linuxserver/nzbget` base image from [linuxserver.io](https://www.linuxserver.io/).

## What it Does

*   **NZBGet:** Downloads files from Usenet newsgroups.
*   **VPN Client (OpenVPN or WireGuard):** Encrypts and routes all of NZBGet's internet traffic (and Privoxy's, if enabled) through a VPN server of your choice. This enhances privacy and can bypass ISP throttling or blocking.
*   **Privoxy (Optional):** A non-caching web proxy with advanced filtering capabilities. When enabled, Privoxy listens on port 8118 within the container. Any application configured to use this proxy will also have its traffic routed through the VPN. This is useful if you want other applications (e.g., web browsers, other download tools running on your host or other containers, if configured appropriately) to benefit from the VPN connection established by this container.

## Features

*   NZBGet (via `linuxserver/nzbget` base image).
*   **OpenVPN** and **WireGuard** client support, auto-connects on startup.
*   Optional **Privoxy** HTTP proxy (port 8118), traffic also routed via VPN.
    *   **Note:** Accessing Privoxy from the Docker host machine (e.g., `localhost:8118`) may currently be unreliable or hang for external requests. Internal use (e.g., other containers using `container_name:8118`) should work.
*   Flexible OpenVPN credential handling.
*   Based on s6-overlay for service management.
*   Customizable with standard `linuxserver.io` PUID/PGID and TZ environment variables.
*   Easy to build and manage with the provided `Makefile`.

## Prerequisites

*   Docker and Docker Compose (or just Docker if not using Compose) installed.
*   A VPN service subscription and its configuration files:
    *   For OpenVPN: An `.ovpn` configuration file and your VPN username/password.
    *   For WireGuard: A `.conf` configuration file (e.g., `wg0.conf`).

## Directory Structure

It's recommended to set up the following directory structure on your host machine to manage configuration and downloads:

```
nzbgetvpn/
├── config/
│   ├── openvpn/          # Place your .ovpn files and (optionally) credential files here
│   │   └── yourvpn.ovpn
│   ├── wireguard/        # Place your .conf files (e.g., wg0.conf) here
│   │   └── wg0.conf
│   └── privoxy/
│       └── config        # Custom Privoxy configuration (if needed, usually not)
├── nzbget_config/        # For NZBGet's persistent configuration (nzbget.conf)
├── downloads/            # For NZBGet's downloaded files
├── .env                  # For environment variables (see below)
├── Dockerfile
├── Makefile
└── README.md
```

*   Create these directories before running the container for the first time.
*   The `config/privoxy/config` file provided in this repository is a standard one; you typically don't need to modify it unless you have advanced Privoxy needs.

## Configuration

### 1. Environment Variables (`.env` file)

Create a `.env` file in the root of your project (alongside `Dockerfile` and `Makefile`). **Add `.env` to your `.gitignore` file to avoid committing secrets.**
A `.env.example` file is provided in the repository; you can copy it to `.env` and modify it.

```env
# .env - Docker Run Configuration

# --- VPN Settings ---
# Choose your VPN client: "openvpn" or "wireguard"
VPN_CLIENT=openvpn

# --- OpenVPN Specific (only if VPN_CLIENT=openvpn) ---
# Path to your .ovpn file inside the container (mounted from ./config/openvpn/)
# If left empty, the script will try to use the first .ovpn file found in ./config/openvpn/.
VPN_CONFIG=/config/openvpn/yourvpn.ovpn
# Your OpenVPN username and password.
# These are the primary way to provide credentials.
# Other methods (credential files) are secondary. See "OpenVPN Credential Handling".
VPN_USER=your_openvpn_username
VPN_PASS=your_openvpn_password
# Optional: Additional command-line options for the OpenVPN client.
# VPN_OPTIONS=--inactive 3600 --ping-exit 60

# --- WireGuard Specific (only if VPN_CLIENT=wireguard) ---
# Path to your WireGuard config file inside the container (mounted from ./config/wireguard/)
# If left empty, the script will try to use the first .conf file found in ./config/wireguard/ (e.g. wg0.conf).
WG_CONFIG_FILE=/config/wireguard/wg0.conf

# --- Privoxy Settings ---
# Enable Privoxy HTTP proxy (yes/no or true/false)
ENABLE_PRIVOXY=yes

# --- Network & DNS Settings ---
# Optional: Comma-separated list of DNS servers to use (e.g., "1.1.1.1,8.8.8.8").
# If empty and using OpenVPN, attempts to use DNS servers pushed by the VPN provider.
# If still no DNS, falls back to defaults (e.g., 198.18.0.1, 198.18.0.2 for some providers, or common public ones).
# NAME_SERVERS=1.1.1.1,8.8.8.8
# Optional: Your LAN network (CIDR notation, e.g., 192.168.1.0/24).
# Allows access to your local network while VPN is active.
# LAN_NETWORK=192.168.1.0/24
# Optional: Comma-separated list of additional TCP/UDP ports to allow outbound through the VPN.
# E.g., for a script that needs to connect on port 9090:
# ADDITIONAL_PORTS=9090

# --- General Container Settings (from linuxserver.io base) ---
# User and Group ID for NZBGet process. Match to your host user for easy file permissions.
# Find yours with `id -u` and `id -g` on Linux/macOS.
PUID=1000
PGID=1000
# Timezone for the container, e.g., America/New_York, Europe/London
TZ=Etc/UTC
# File creation mask for NZBGet. 022 is a common default (user rwx, group rx, other rx).
# 002 would give group write access as well.
UMASK=022

# --- NZBGet Specific (Optional - can be set in NZBGet UI later) ---
# NZBGET_USER=nzbget_ui_username
# NZBGET_PASS=nzbget_ui_password

# --- Debugging ---
# Enable verbose script logging (set -x) by setting to "true"
# DEBUG=false
```

**Replace placeholder values with your actual settings.**

### 2. VPN Configuration Files

*   **OpenVPN:** Place your `.ovpn` file (e.g., `yourvpn.ovpn`) into the `./config/openvpn/` directory on your host.
*   **WireGuard:** Place your WireGuard configuration file (e.g., `wg0.conf`) into the `./config/wireguard/` directory on your host. Ensure it's correctly configured with your private key and peer information.

### 3. OpenVPN Credential Handling

The startup script (`50-vpn-setup`) prioritizes OpenVPN credentials as follows:
1.  **Direct Environment Variables:** `VPN_USER` and `VPN_PASS` from the `.env` file (or passed via `docker run -e`). **This is the recommended method.**
2.  **Project Root `.env` (legacy):** If the project root is mounted to `/app` and `/app/.env` contains `VPN_USER`/`VPN_PASS`. (Less common now with `--env-file` support).
3.  **Override File (`/config/openvpn-credentials.txt`):** A file inside the container at this path, with username on the first line and password on the second. You can provide this by placing `openvpn-credentials.txt` in your local `./config/openvpn/` directory.
4.  **Legacy File (`/config/openvpn/CREDENTIALS`):** Same format as above, in your local `./config/openvpn/` directory.

### 4. WireGuard Credentials
WireGuard credentials (private keys, peer public keys) are part of the WireGuard configuration file itself (`.conf`). No separate `VPN_USER`/`VPN_PASS` variables are used.

## How to Run

### Using `Makefile` (Recommended)

The provided `Makefile` simplifies common operations. Ensure your `.env` file is configured.

1.  **Build the Docker Image:**
    ```bash
    make build
    ```

2.  **Run with OpenVPN:**
    ```bash
    make run
    # or make run-openvpn
    ```

3.  **Run with WireGuard:**
    (Ensure `VPN_CLIENT=wireguard` and `WG_CONFIG_FILE` are set in `.env`)
    ```bash
    make run-wireguard
    ```

4.  **View Logs:**
    ```bash
    make logs
    ```

5.  **Stop the Container:**
    ```bash
    make stop
    ```

6.  **Access Container Shell (for debugging):**
    ```bash
    make shell
    ```
    
7.  **Clean up (stops container, optionally removes image):**
    ```bash
    make clean
    ```
    
8.  **View all Makefile targets:**
    ```bash
    make help
    ```

### Using `docker run` (Manual)

If you prefer not to use the `Makefile`, here are example `docker run` commands.

**For OpenVPN:**
```bash
docker run -d \
  --name nzbgetvpn-container \
  --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -p 8118:8118 \
  -v "$(pwd)/config/openvpn:/config/openvpn" \
  -v "$(pwd)/nzbget_config:/config" \
  -v "$(pwd)/downloads:/downloads" \
  --env-file .env \
  -e VPN_CLIENT=openvpn \
  nzbgetvpn # Or your custom image name
```

**For WireGuard:**
WireGuard often requires broader capabilities.
```bash
docker run -d \
  --name nzbgetvpn-container \
  --rm \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --sysctl="net.ipv6.conf.all.disable_ipv6=0" \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -p 8118:8118 \
  -v "$(pwd)/config/wireguard:/config/wireguard" \
  -v "$(pwd)/nzbget_config:/config" \
  -v "$(pwd)/downloads:/downloads" \
  --env-file .env \
  -e VPN_CLIENT=wireguard \
  nzbgetvpn # Or your custom image name
```
*Note on WireGuard privileges: The `--cap-add=SYS_MODULE` and `--sysctl` settings are common. If you encounter issues, some setups might require `--privileged=true` as a last resort for testing, though it's less secure.*

## Accessing Services

*   **NZBGet Web UI:** `http://<your_docker_host_ip>:6789` (e.g., `http://localhost:6789`)
*   **Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, configure your applications to use proxy server `<your_docker_host_ip>` on port `8118`.

## Troubleshooting

*   **Container Exits Quickly:** Check logs with `make logs` or `docker logs nzbgetvpn-container`. The `50-vpn-setup` script provides detailed startup logs for VPN connection attempts.
*   **OpenVPN "Cannot open TUN/TAP dev" Error:** Ensure `--cap-add=NET_ADMIN` and `--device=/dev/net/tun` are used.
*   **OpenVPN Authentication Errors:** Double-check `VPN_USER`, `VPN_PASS` in your `.env` file, the `VPN_CONFIG` path, and the content of your `.ovpn` file.
*   **WireGuard Interface Not Coming Up:** Verify your `.conf` file is correct and has the right permissions. Check WireGuard-specific privileges in your `docker run` command or `Makefile`.
*   **"RTNETLINK answers: File exists" (OpenVPN):** This is a common, often harmless, error if `redirect-gateway def1` is used and routes already exist or conflict. The VPN usually still functions.
*   **Privoxy Not Working From Host:** Ensure `ENABLE_PRIVOXY=yes` in `.env`. Check logs for Privoxy startup messages. Ensure port 8118 is mapped.
    *   Currently, there's a known issue where connections to Privoxy from the Docker host (e.g., `curl -x http://localhost:8118 http://ifconfig.me/ip`) may establish a TCP connection but then hang without Privoxy processing the request or logging an error.
    *   Privoxy *does* appear to function correctly for requests originating *from within the container itself* (e.g., if NZBGet were configured to use `http://localhost:8118` as a proxy).
    *   This issue is under investigation. For now, rely on Privoxy primarily for internal container-to-container proxying if needed.

## License

This project is licensed under the [MIT License](LICENSE).
The base image `linuxserver/nzbget`, OpenVPN, WireGuard, and Privoxy have their own respective licenses.


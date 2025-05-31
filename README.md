# NZBGet with VPN and Optional Privoxy

Run NZBGet with all its traffic (and optionally other HTTP/HTTPS traffic via Privoxy) routed through an OpenVPN or WireGuard VPN connection. Based on the `linuxserver/nzbget` image.

**Docker Hub:** `docker pull magicalyak/nzbgetvpn:latest`

## Core Features

*   **NZBGet:** Latest version from `linuxserver/nzbget`.
*   **VPN Client:** Supports **OpenVPN** and **WireGuard**. All container traffic is routed through the VPN.
*   **Privoxy (Optional):** HTTP proxy on port 8118. If enabled, Privoxy's traffic also goes via the VPN.
*   **Host Access:** NZBGet UI (port 6789) and Privoxy (if enabled, port 8118) are accessible from the Docker host.
*   **Easy Management:** Uses s6-overlay and includes a `Makefile`.

## Quick Setup

This guide helps you prepare your host system to run the `magicalyak/nzbgetvpn` Docker image.

1.  **Prerequisites:**
    *   Docker installed.
    *   VPN service subscription and configuration files:
        *   OpenVPN: `.ovpn` file and username/password.
        *   WireGuard: `.conf` file.

2.  **Prepare Host Directories & VPN Files:**
    You'll need to create directories on your Docker host to store persistent NZBGet configuration, downloads, and your VPN configuration files. These directories will be mounted as volumes into the container.

    Example host directory structure:
    ```
    /path/to/your/nzbgetvpn_data/
    ├── openvpn_config/       # Place .ovpn file(s) here (if using OpenVPN)
    │   └── your_provider.ovpn
    ├── wireguard_config/     # Place .conf file(s) here (e.g., wg0.conf) (if using WireGuard)
    │   └── wg0.conf
    ├── nzbget_config/        # For NZBGet's persistent configuration (container path: /config)
    ├── downloads/            # For NZBGet's download destination (container path: /downloads)
    └── .env                  # Your environment settings (see next step)
    ```
    *Replace `/path/to/your/nzbgetvpn_data/` with your preferred location.*

3.  **Configure Environment (`.env` file):**
    Create an `.env` file in your chosen directory (e.g., `/path/to/your/nzbgetvpn_data/.env`). You can copy the structure from `.env.sample` in the source repository or create it manually.
    Key variables to set:

    *   `VPN_CLIENT`: `openvpn` or `wireguard`.
    *   **OpenVPN:**
        *   `VPN_CONFIG`: Path to your `.ovpn` file (e.g., `/config/openvpn/your_provider.ovpn`). If empty, tries the first `.ovpn` found.
        *   `VPN_USER`: Your OpenVPN username.
        *   `VPN_PASS`: Your OpenVPN password.
    *   **WireGuard:**
        *   `WG_CONFIG_FILE`: Path to your WireGuard `.conf` file (e.g., `/config/wireguard/wg0.conf`). If empty, tries the first `.conf` found.
    *   `ENABLE_PRIVOXY`: `yes` or `no` (defaults to `no`).
    *   `PRIVOXY_PORT`: Internal port for Privoxy service (defaults to 8118).
    *   `PUID`, `PGID`: User/Group IDs for file permissions. Match your host user (e.g., `1000`).
    *   `TZ`: Your timezone (e.g., `America/New_York`).
    *   `LAN_NETWORK`: (Optional) Your LAN CIDR (e.g., `192.168.1.0/24`) to bypass VPN for local access.
    *   `NAME_SERVERS`: (Optional) Comma-separated DNS servers (e.g., `1.1.1.1,8.8.8.8`).

    *(See `.env.sample` for more options like `DEBUG`, `VPN_OPTIONS`)*.
    **Important:** Add `.env` to your `.gitignore` file.

## How to Run (Makefile Recommended)

1.  **Build Image:**
    ```bash
    make build
    ```
2.  **Run Container:**
    *   For OpenVPN (default if `VPN_CLIENT=openvpn` in `.env`):
        ```bash
        make run
        # or make run-openvpn
        ```
    *   For WireGuard (ensure `VPN_CLIENT=wireguard` in `.env`):
        ```bash
        make run-wireguard
        ```
3.  **Other Useful Commands:**
    *   View logs: `make logs`
    *   Stop container: `make stop`
    *   Access container shell: `make shell`
    *   Clean up: `make clean`
    *   See all commands: `make help`

## Accessing Services

*   **NZBGet Web UI:** `http://localhost:6789` (or your Docker host IP if not running Docker Desktop locally).
*   **Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, use proxy server `localhost`
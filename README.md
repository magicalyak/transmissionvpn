# NZBGet with VPN and Optional Privoxy

Run NZBGet with all its traffic (and optionally other HTTP/HTTPS traffic via Privoxy) routed through an OpenVPN or WireGuard VPN connection. Based on the `linuxserver/nzbget` image.

## Core Features

*   **NZBGet:** Latest version from `linuxserver/nzbget`.
*   **VPN Client:** Supports **OpenVPN** and **WireGuard**. All container traffic is routed through the VPN.
*   **Privoxy (Optional):** HTTP proxy on port 8118. If enabled, Privoxy's traffic also goes via the VPN.
*   **Host Access:** NZBGet UI (port 6789) and Privoxy (if enabled, port 8118) are accessible from the Docker host.
*   **Easy Management:** Uses s6-overlay and includes a `Makefile`.

## Quick Setup

1.  **Prerequisites:**
    *   Docker installed.
    *   VPN service subscription and configuration files:
        *   OpenVPN: `.ovpn` file and username/password.
        *   WireGuard: `.conf` file.

2.  **Directory Structure & VPN Files:**
    Create these directories and place your VPN files:
    ```
    nzbgetvpn/
    ├── config/
    │   ├── openvpn/          # Place .ovpn file(s) here
    │   │   └── your_provider.ovpn
    │   └── wireguard/        # Place .conf file(s) here (e.g., wg0.conf)
    │       └── wg0.conf
    ├── nzbget_config/        # NZBGet's persistent configuration (created automatically)
    ├── downloads/            # NZBGet's download destination
    ├── .env                  # Your environment settings (see next step)
    ├── Dockerfile
    ├── Makefile
    └── README.md
    ```

3.  **Configure Environment (`.env` file):**
    Copy `.env.sample` to `.env` and edit it. Key variables:

    *   `VPN_CLIENT`: `openvpn` or `wireguard`.
    *   **OpenVPN:**
        *   `VPN_CONFIG`: Path to your `.ovpn` file (e.g., `/config/openvpn/your_provider.ovpn`). If empty, tries the first `.ovpn` found.
        *   `VPN_USER`: Your OpenVPN username.
        *   `VPN_PASS`: Your OpenVPN password.
    *   **WireGuard:**
        *   `WG_CONFIG_FILE`: Path to your WireGuard `.conf` file (e.g., `/config/wireguard/wg0.conf`). If empty, tries the first `.conf` found.
    *   `ENABLE_PRIVOXY`: `yes` or `no` (defaults to `no`).
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

*   **NZBGet Web UI:** `http://localhost:6789` (or your Docker host IP).
*   **Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, use proxy server `localhost` (or Docker host IP) on port `8118`.

## Key Environment Variables

| Variable         | Purpose                                                                 | Example                              | Default (if any) |
|------------------|-------------------------------------------------------------------------|--------------------------------------|------------------|
| `VPN_CLIENT`     | `openvpn` or `wireguard`                                                | `openvpn`                            | `openvpn`        |
| `VPN_CONFIG`     | Path to OpenVPN `.ovpn` file in container                             | `/config/openvpn/your_provider.ovpn` | (auto-detect)    |
| `VPN_USER`       | OpenVPN username                                                        | `myuser`                             |                  |
| `VPN_PASS`       | OpenVPN password                                                        | `mypassword`                         |                  |
| `WG_CONFIG_FILE` | Path to WireGuard `.conf` file in container                           | `/config/wireguard/wg0.conf`         | (auto-detect)    |
| `ENABLE_PRIVOXY` | Enable Privoxy (`yes`/`no`)                                             | `no`                                 | `no`             |
| `PUID`           | User ID for NZBGet process                                              | `1000`                               | (from base)      |
| `PGID`           | Group ID for NZBGet process                                             | `1000`                               | (from base)      |
| `TZ`             | Timezone                                                                | `America/New_York`                   | `Etc/UTC`        |
| `LAN_NETWORK`    | LAN CIDR to bypass VPN (e.g., for local NAS access from NZBGet scripts) | `192.168.1.0/24`                     |                  |
| `NAME_SERVERS`   | Custom DNS servers (comma-separated)                                    | `1.1.1.1,8.8.8.8`                    | (VPN/defaults)   |
| `DEBUG`          | Enable verbose script logging (`true`/`false`)                          | `false`                              | `false`          |
| `VPN_OPTIONS`    | Additional OpenVPN client options                                       | `--inactive 3600`                    |                  |
| `UMASK`          | File creation mask                                                      | `022`                                | `022`            |
| `ADDITIONAL_PORTS`| Comma-separated TCP/UDP ports for outbound allow via iptables          | `9090,53/udp`                      |                  |


## Troubleshooting

*   **Container Exits / VPN Issues:** Run `make logs`. The `50-vpn-setup` script provides detailed VPN connection logs. Common issues:
    *   Incorrect `VPN_CONFIG` path or file content.
    *   Wrong `VPN_USER`/`VPN_PASS` for OpenVPN.
    *   Malformed WireGuard `.conf` file.
*   **File Permissions:** Ensure `PUID`/`PGID` in `.env` match your host user's IDs for the `nzbget_config` and `downloads` directories.
*   **NZBGet UI Inaccessible:**
    1.  Confirm container is running: `docker ps`.
    2.  Check `make logs` for NZBGet startup messages (e.g., `nzbget runs on 0.0.0.0:6789`).
    3.  Ensure VPN connected successfully in logs. The PBR rules depend on this.

## OpenVPN Credential Handling (Simplified)

The primary and recommended method for OpenVPN credentials is via the `VPN_USER` and `VPN_PASS` environment variables set in your `.env` file.

Alternative methods (like `openvpn-credentials.txt`) exist but are secondary. For simplicity, use `VPN_USER` and `VPN_PASS`.

## Docker Run (Manual Examples)

If not using the `Makefile`:

**OpenVPN:**
```bash
docker run -d \\
  --name nzbgetvpn-container \\
  --rm \\
  --cap-add=NET_ADMIN \\
  --device=/dev/net/tun \\
  -p 6789:6789 \\
  -p 8118:8118 \\
  -v "$(pwd)/config/openvpn:/config/openvpn" \\
  -v "$(pwd)/nzbget_config:/config" \\
  -v "$(pwd)/downloads:/downloads" \\
  --env-file .env \\
  -e VPN_CLIENT=openvpn \\
  nzbgetvpn
```

**WireGuard:**
```bash
docker run -d \\
  --name nzbgetvpn-container \\
  --rm \\
  --cap-add=NET_ADMIN \\
  --cap-add=SYS_MODULE \\
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \\
  --sysctl="net.ipv6.conf.all.disable_ipv6=0" \\
  --device=/dev/net/tun \\
  -p 6789:6789 \\
  -p 8118:8118 \\
  -v "$(pwd)/config/wireguard:/config/wireguard" \\
  -v "$(pwd)/nzbget_config:/config" \\
  -v "$(pwd)/downloads:/downloads" \\
  --env-file .env \\
  -e VPN_CLIENT=wireguard \\
  nzbgetvpn
```
*Note: For WireGuard, `--cap-add=SYS_MODULE` and specific `--sysctl` flags are often needed. Avoid `--privileged` if possible.*


## License

This project is licensed under the [MIT License](LICENSE).
Base image and bundled software (NZBGet, OpenVPN, WireGuard, Privoxy) have their own licenses.


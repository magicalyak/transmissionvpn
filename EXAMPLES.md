# 📋 transmissionvpn Examples

This document provides practical examples for common use cases of the `magicalyak/transmissionvpn` container.

## 🎨 Basic Setup with Theme

Add a beautiful dark theme to your Transmission web UI:

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
      - "8118:8118"
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/nordvpn.ovpn
      - VPN_USER=your_vpn_username
      - VPN_PASS=your_vpn_password
      - DOCKER_MODS=ghcr.io/gilbn/theme.park:transmission
      - TP_THEME=hotline
    restart: unless-stopped
```

## 🔧 Enhanced Setup with Utilities

Add useful packages for post-processing and troubleshooting:

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
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - VPN_CLIENT=wireguard
      - VPN_CONFIG=/config/wireguard/wg0.conf
      - DOCKER_MODS=lscr.io/linuxserver/mods:universal-package-install|lscr.io/linuxserver/mods:universal-unrar6
      - INSTALL_PACKAGES=mediainfo|curl|rsync|p7zip
    restart: unless-stopped
```

## 🌈 Full-Featured Setup

Combine multiple mods for the ultimate experience:

```yaml
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "9091:9091"
      - "8118:8118"
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
      - ./flood-for-transmission:/web-ui:ro  # Alternative UI
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Los_Angeles
      - VPN_CLIENT=wireguard
      - VPN_CONFIG=/config/wireguard/wg0.conf
      - ENABLE_PRIVOXY=yes
      - LOG_TO_STDOUT=true
      - HEALTH_CHECK_HOST=cloudflare.com
      - TRANSMISSION_WEB_HOME=/web-ui
      - DOCKER_MODS=ghcr.io/gilbn/theme.park:transmission|lscr.io/linuxserver/mods:universal-package-install|lscr.io/linuxserver/mods:universal-tshoot
      - TP_THEME=dracula
      - INSTALL_PACKAGES=unrar|p7zip|mediainfo|curl|git|ffmpeg
      - INSTALL_PIP_PACKAGES=apprise|requests
    restart: unless-stopped
```

## 🔄 Migration from haugene/transmission-openvpn

Quick migration example with equivalent functionality:

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
      - "8118:8118"  # Changed from 8888
    volumes:
      - ./config:/config
      - ./downloads:/downloads  # Changed from /data
      - ./watch:/watch
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/your_provider.ovpn  # Changed from OPENVPN_CONFIG
      - VPN_USER=your_vpn_username  # Changed from OPENVPN_USERNAME
      - VPN_PASS=your_vpn_password  # Changed from OPENVPN_PASSWORD
      - LAN_NETWORK=192.168.1.0/24  # Changed from LOCAL_NETWORK
      - ENABLE_PRIVOXY=yes  # Changed from WEBPROXY_ENABLED
      - PRIVOXY_PORT=8118  # Changed from WEBPROXY_PORT=8888
      - HEALTH_CHECK_HOST=google.com
      - LOG_TO_STDOUT=true
    restart: unless-stopped
```

## 🎯 Specialized Configurations

### Media Server Integration

Perfect for integration with Sonarr, Radarr, etc.:

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
      - /media/downloads:/downloads
      - /media/watch:/watch
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - VPN_USER=username
      - VPN_PASS=password
      - TRANSMISSION_INCOMPLETE_DIR_ENABLED=true
      - TRANSMISSION_INCOMPLETE_DIR=/downloads/incomplete
      - TRANSMISSION_WATCH_DIR_ENABLED=true
      - TRANSMISSION_PEER_PORT=51413
      - ADDITIONAL_PORTS=51413
    restart: unless-stopped

  # Your other *arr services here
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    # ... sonarr config
```

### Development/Testing Setup

Includes troubleshooting tools and staging certificates:

```yaml
version: "3.8"
services:
  transmissionvpn:
    image: magicalyak/transmissionvpn:latest
    container_name: transmissionvpn-dev
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
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/test.ovpn
      - VPN_USER=testuser
      - VPN_PASS=testpass
      - DEBUG=true
      - LOG_TO_STDOUT=true
      - DOCKER_MODS=lscr.io/linuxserver/mods:universal-tshoot|lscr.io/linuxserver/mods:universal-package-install
      - INSTALL_PACKAGES=tcpdump|nmap|strace|htop
    restart: "no"  # Don't auto-restart for development
```

## 🔐 Security Best Practices

Use Docker secrets for credentials:

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
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - FILE__VPN_USER=/run/secrets/vpn_username
      - FILE__VPN_PASS=/run/secrets/vpn_password
      - FILE__TRANSMISSION_RPC_PASSWORD=/run/secrets/transmission_password
      - TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true
      - TRANSMISSION_RPC_USERNAME=admin
    secrets:
      - vpn_username
      - vpn_password
      - transmission_password
    restart: unless-stopped

secrets:
  vpn_username:
    file: ./secrets/vpn_username.txt
  vpn_password:
    file: ./secrets/vpn_password.txt
  transmission_password:
    file: ./secrets/transmission_password.txt
```

## 🌐 Network Scenarios

### Custom Network with Other Containers

```yaml
version: "3.8"

networks:
  vpn-network:
    driver: bridge

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
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/provider.ovpn
      - VPN_USER=username
      - VPN_PASS=password
      - LAN_NETWORK=192.168.1.0/24,172.20.0.0/16
    networks:
      - vpn-network
    restart: unless-stopped

  # Container sharing the VPN connection
  jackett:
    image: lscr.io/linuxserver/jackett:latest
    container_name: jackett
    network_mode: "service:transmissionvpn"
    volumes:
      - ./jackett-config:/config
    environment:
      - PUID=1000
      - PGID=1000
    depends_on:
      - transmissionvpn
```

---

For more advanced configurations and troubleshooting, see the main [README.md](README.md) file. 
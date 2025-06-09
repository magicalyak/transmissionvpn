# 🛡️ VPN Provider Setup Guides

This document provides specific setup instructions for popular VPN providers with transmissionvpn.

## 📋 Table of Contents

- [NordVPN](#nordvpn)
- [ExpressVPN](#expressvpn)
- [Surfshark](#surfshark)
- [ProtonVPN](#protonvpn)
- [Mullvad](#mullvad)
- [Private Internet Access (PIA)](#private-internet-access-pia)
- [PrivadoVPN](#privadovpn)
- [CyberGhost](#cyberghost)
- [IPVanish](#ipvanish)
- [Custom/Self-hosted](#customself-hosted)
- [Troubleshooting](#troubleshooting)

## NordVPN

### NordVPN OpenVPN Setup

1. **Download OpenVPN Configuration Files:**
   - Download the configuration files from the [NordVPN website](https://nordvpn.com/ovpn/).
   - Unzip the files into your `./config/openvpn/` directory.

2. **Docker Compose Example:**

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
    environment:
      - VPN_PROVIDER=nordvpn
      - VPN_CONFIG=us9999.nordvpn.com.udp.ovpn
      - VPN_USER=your_nordvpn_username
      - VPN_PASS=your_nordvpn_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

### NordVPN WireGuard (NordLynx) Setup

NordVPN uses a custom WireGuard implementation called NordLynx, which requires manual configuration.

1. **Follow a community guide** to extract the necessary information.
2. Create a `nordlynx.conf` file in `./config/wireguard/`.

## ExpressVPN

### OpenVPN Setup

1. **Download Configuration:**
   - Log in to ExpressVPN account
   - Go to Setup → Manual Configuration → OpenVPN
   - Download `.ovpn` files for your preferred locations

2. **Docker Compose Example:**

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
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/my_expressvpn_usa_-_new_york_udp.ovpn
      - VPN_USER=your_expressvpn_username
      - VPN_PASS=your_expressvpn_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - LAN_NETWORK=192.168.1.0/24
    restart: unless-stopped
```

3. **Important Notes:**
   - ExpressVPN requires specific authentication
   - Use the credentials from your account setup page
   - Some servers may require additional certificates

## Surfshark

### Surfshark OpenVPN Setup

1. **Download OpenVPN Configuration Files:**
   - Download the configuration files from your [Surfshark account page](https://my.surfshark.com/vpn/manual-setup/main/openvpn).
   - Unzip the files into your `./config/openvpn/` directory.

2. **Docker Compose Example:**

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
    environment:
      - VPN_PROVIDER=surfshark
      - VPN_CONFIG=us-dal.prod.surfshark.com_udp.ovpn
      - VPN_USER=your_surfshark_username
      - VPN_PASS=your_surfshark_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

### Surfshark WireGuard Setup

1. **Generate WireGuard Configuration:**
   - Follow the instructions on the [Surfshark website](https://support.surfshark.com/hc/en-us/articles/360018115799-How-to-set-up-WireGuard-on-a-router) to get your private key.
   - Create a `.conf` file in `./config/wireguard/`.

2. **Docker Compose Example:**

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
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    environment:
      - VPN_CLIENT=wireguard
      - VPN_PROVIDER=surfshark
      - VPN_CONFIG=surfshark.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## ProtonVPN

### OpenVPN Setup

1. **Download Configuration:**
   - Log in to ProtonVPN account
   - Go to Downloads → OpenVPN configuration files
   - Select your preferred servers and download

2. **Docker Compose Example:**

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
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/us-ny-01.protonvpn.net.udp.ovpn
      - VPN_USER=your_protonvpn_username
      - VPN_PASS=your_protonvpn_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

3. **Important Notes:**
   - Use your ProtonVPN/ProtonMail credentials
   - Free tier has limited server access
   - P2P is allowed on specific servers only

## Mullvad

### Mullvad OpenVPN Setup

1. **Download OpenVPN Configuration Files:**
   - Download the configuration files from the [Mullvad website](https://mullvad.net/en/download/openvpn-config).
   - Unzip the files into your `./config/openvpn/` directory.

2. **Docker Compose Example:**

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
    environment:
      - VPN_PROVIDER=mullvad
      - VPN_CONFIG=mullvad_us-ny.ovpn
      - VPN_USER=your_mullvad_account_number
      - VPN_PASS=m
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### Mullvad WireGuard Setup

1. **Generate WireGuard Configuration:**
   - Generate a WireGuard key on the [Mullvad website](https://mullvad.net/en/account/#/wireguard-config/).
   - Download the configuration file and place it in `./config/wireguard/`.

2. **Docker Compose Example:**

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
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    environment:
      - VPN_CLIENT=wireguard
      - VPN_PROVIDER=mullvad
      - VPN_CONFIG=mullvad.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## Private Internet Access (PIA)

### OpenVPN Setup

1. **Download OpenVPN Configuration Files:**
   - Download the "OpenVPN Configuration Files (Default)" from the [PIA website](https://www.privateinternetaccess.com/pages/ovpn-config-generator).
   - Unzip the files into your `./config/openvpn/` directory.
   - Your `VPN_CONFIG` will be the name of the `.ovpn` file (e.g., `us_east.ovpn`).

2. **Docker Compose Example:**

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
    environment:
      - VPN_PROVIDER=pia
      - VPN_CONFIG=us_east.ovpn
      - VPN_USER=p1234567
      - VPN_PASS=supersecret
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### WireGuard Setup

1. **Generate WireGuard Configuration:**
   - Use the [PIA WireGuard Config Generator](https://www.privateinternetaccess.com/pages/wireguard-config-generator).
   - Save the generated `.conf` file to `./config/wireguard/`.
   - Your `VPN_CONFIG` will be the name of the `.conf` file (e.g., `pia.conf`).

2. **Docker Compose Example:**

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
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    environment:
      - VPN_CLIENT=wireguard
      - VPN_PROVIDER=pia
      - VPN_CONFIG=pia.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## PrivadoVPN

### OpenVPN Setup

1. **Download Configuration:**
   - Log in to PrivadoVPN account
   - Go to Downloads → OpenVPN configuration files
   - Select your preferred servers and download

2. **Docker Compose Example:**

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
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/privado.ams-026.tcp.1194.ovpn
      - VPN_USER=your_privadovpn_username
      - VPN_PASS=your_privadovpn_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

3. **Important Notes:**
   - Use your PrivadoVPN username (not email) for authentication
   - Manual configuration is available to Premium users only
   - Configuration files use airport codes to shorten file names
   - Both TCP and UDP protocols are available

### WireGuard Setup

1. **Generate WireGuard Config:**
   - Use PrivadoVPN's WireGuard config generator
   - Download the configuration file

2. **Docker Compose Example:**

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
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    environment:
      - VPN_CLIENT=wireguard
      - VPN_CONFIG=/config/wireguard/privadovpn-us.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## CyberGhost

### OpenVPN Setup

1. **Get Configuration Files:**
   - Log in to CyberGhost account
   - Go to My Account → Configure new device → Router
   - Download OpenVPN configuration files

2. **Docker Compose Example:**

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
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/CyberGhost_US_optimized.ovpn
      - VPN_USER=your_cyberghost_username
      - VPN_PASS=your_cyberghost_password
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## IPVanish

### OpenVPN Setup

1. **Download Configuration:**
   - Log in to IPVanish account
   - Go to Setup Guides → Router Setup
   - Download OpenVPN configuration files

2. **Docker Compose Example:**

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
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/ipvanish-US-New-York-nyc-a01.ovpn
      - VPN_USER=your_ipvanish_username
      - VPN_PASS=your_ipvanish_password
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## Custom/Self-hosted

### OpenVPN Setup

For custom OpenVPN servers:

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
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/custom-server.ovpn
      - VPN_USER=your_username  # Optional if using certificates
      - VPN_PASS=your_password  # Optional if using certificates
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### WireGuard Setup

For custom WireGuard servers:

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
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    environment:
      - VPN_CLIENT=wireguard
      - VPN_CONFIG=/config/wireguard/custom-wg.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## Troubleshooting

### Common Issues

1. **VPN Connection Fails:**
   - Check VPN credentials
   - Verify configuration file path
   - Ensure proper file permissions
   - Check provider-specific requirements

2. **DNS Leaks:**
   - Use DNS leak test websites
   - Consider custom DNS settings
   - Check VPN provider's DNS servers

3. **Port Forwarding:**
   - Some providers support port forwarding
   - Configure `ADDITIONAL_PORTS` if needed
   - Check provider documentation

4. **IP Leaks:**
   - Verify kill switch is working
   - Test with IP leak detection tools
   - Ensure no WebRTC leaks

### Debug Commands

```bash
# Check container logs
docker logs transmissionvpn

# Check VPN connection status
docker exec transmissionvpn curl ifconfig.me

# Check DNS resolution
docker exec transmissionvpn nslookup google.com

# Check routing table
docker exec transmissionvpn ip route

# Test VPN connectivity
docker exec transmissionvpn ping 8.8.8.8
```

### Performance Optimization

1. **Server Selection:**
   - Choose geographically close servers
   - Use servers optimized for P2P
   - Avoid overcrowded servers

2. **Protocol Selection:**
   - WireGuard generally offers better performance
   - OpenVPN UDP is faster than TCP
   - Test different configurations

3. **Transmission Settings:**
   - Adjust peer limits
   - Configure proper port forwarding
   - Optimize bandwidth allocation

### Provider-Specific Notes

- **NordVPN:** Use P2P-optimized servers for best performance
- **ExpressVPN:** Some servers may have connection limits
- **Surfshark:** MultiHop feature available for extra security
- **ProtonVPN:** Secure Core feature for enhanced privacy
- **Mullvad:** Privacy-focused with no logging
- **PIA:** Port forwarding available on most servers
- **CyberGhost:** Optimized servers for torrenting
- **IPVanish:** SOCKS5 proxy also available

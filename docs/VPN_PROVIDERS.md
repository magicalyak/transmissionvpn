# 🛡️ VPN Provider Setup Guides

This document provides specific setup instructions for popular VPN providers with transmissionvpn.

## 📋 Table of Contents

- [NordVPN](#nordvpn)
- [ExpressVPN](#expressvpn)
- [Surfshark](#surfshark)
- [ProtonVPN](#protonvpn)
- [Mullvad](#mullvad)
- [Private Internet Access (PIA)](#private-internet-access-pia)
- [CyberGhost](#cyberghost)
- [IPVanish](#ipvanish)
- [Custom/Self-hosted](#customself-hosted)
- [Troubleshooting](#troubleshooting)

## NordVPN

### OpenVPN Setup

1. **Download Configuration Files:**
   - Log in to your NordVPN account
   - Go to [NordVPN Downloads](https://nordvpn.com/ovpn/)
   - Download individual `.ovpn` files for your preferred servers

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
      - ./watch:/watch
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/us8923.nordvpn.com.udp.ovpn
      - VPN_USER=your_nordvpn_username
      - VPN_PASS=your_nordvpn_password
      - LAN_NETWORK=192.168.1.0/24
    restart: unless-stopped
```

3. **File Structure:**
```
./config/openvpn/
├── us8923.nordvpn.com.udp.ovpn
└── credentials.txt  # Optional: username on line 1, password on line 2
```

### WireGuard Setup

1. **Get WireGuard Configuration:**
   - Install NordVPN app on your device
   - Enable WireGuard in settings
   - Export configuration or use NordLynx

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
      - VPN_CONFIG=/config/wireguard/nordvpn-us.conf
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

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

### OpenVPN Setup

1. **Get Configuration Files:**
   - Log in to Surfshark account
   - Go to Manual Setup → OpenVPN
   - Download configuration files for your preferred locations

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
      - VPN_CONFIG=/config/openvpn/us-nyc.prod.surfshark.com_udp.ovpn
      - VPN_USER=your_surfshark_username
      - VPN_PASS=your_surfshark_password
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    restart: unless-stopped
```

### WireGuard Setup

1. **Get WireGuard Configuration:**
   - Use Surfshark's WireGuard configuration generator
   - Download the `.conf` file

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
      - VPN_CONFIG=/config/wireguard/surfshark-us.conf
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

### OpenVPN Setup

1. **Generate Configuration:**
   - Log in to Mullvad account
   - Go to OpenVPN config generator
   - Select platform: Linux, servers, and download

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
      - VPN_CONFIG=/config/openvpn/mullvad_us_all.conf
      - VPN_USER=your_mullvad_account_number
      - VPN_PASS=m  # Mullvad uses 'm' as password
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### WireGuard Setup

1. **Generate WireGuard Config:**
   - Use Mullvad's WireGuard config generator
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
      - VPN_CONFIG=/config/wireguard/mullvad-us.conf
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## Private Internet Access (PIA)

### OpenVPN Setup

1. **Download Configuration:**
   - Log in to PIA account
   - Go to Client Support → OpenVPN/L2TP/PPTP/IPSec Setup
   - Download configuration files

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
      - VPN_CONFIG=/config/openvpn/us_new_york_city.ovpn
      - VPN_USER=your_pia_username
      - VPN_PASS=your_pia_password
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

### WireGuard Setup

1. **Generate WireGuard Config:**
   - Use PIA's WireGuard configuration generator
   - Download configuration file

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
      - VPN_CONFIG=/config/wireguard/pia-us.conf
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
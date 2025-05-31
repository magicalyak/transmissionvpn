FROM ghcr.io/linuxserver/nzbget:latest

# ENV NZBGET_VERSION=25.0

# Add ARG for VPN credentials
ARG VPN_USER
ARG VPN_PASS

# Set ENV from ARG
ENV VPN_USER=$VPN_USER
ENV VPN_PASS=$VPN_PASS

# Additional ENV for runtime variables needed by s6 scripts
ENV VPN_CLIENT=${VPN_CLIENT:-openvpn}
ENV VPN_CONFIG=${VPN_CONFIG:-}
ENV ENABLE_PRIVOXY=${ENABLE_PRIVOXY:-no}
ENV DEBUG=${DEBUG:-false}
# Default umask, gives rwxr-xr-x for dirs, rw-r--r-- for files. Handled by LSIO base scripts.
ENV UMASK=${UMASK:-022}
ENV NAME_SERVERS=${NAME_SERVERS:-}
ENV VPN_OPTIONS=${VPN_OPTIONS:-}
ENV LAN_NETWORK=${LAN_NETWORK:-}
ENV ADDITIONAL_PORTS=${ADDITIONAL_PORTS:-}
ENV PRIVOXY_PORT=${PRIVOXY_PORT:-8118}
ENV VPN_CREDENTIALS_FILE=${VPN_CREDENTIALS_FILE:-}

# Install OpenVPN, WireGuard, Privoxy and tools
RUN apk add --no-cache openvpn iptables bash curl iproute2 wireguard-tools privoxy && \
    for f in /etc/privoxy/*.new; do mv -n "$f" "${f%.new}"; done

# Copy s6-overlay init scripts
COPY root/etc/cont-init.d/01-ensure-vpn-config-dirs.sh /etc/cont-init.d/01-ensure-vpn-config-dirs
COPY root/vpn-setup.sh /etc/cont-init.d/50-vpn-setup

# Copy healthcheck script
COPY root/healthcheck.sh /root/healthcheck.sh

# Copy Privoxy configuration template and s6 service files
COPY config/privoxy/config /etc/privoxy/config.template
COPY root_s6/privoxy/run /etc/s6-overlay/s6-rc.d/privoxy/run
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/privoxy/type && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/privoxy

# Make scripts executable
RUN chmod +x /etc/cont-init.d/* /root/healthcheck.sh /etc/s6-overlay/s6-rc.d/privoxy/run

# Healthcheck
HEALTHCHECK --interval=1m --timeout=10s --start-period=2m --retries=3 \
  CMD /root/healthcheck.sh

# CMD is inherited from linuxserver base

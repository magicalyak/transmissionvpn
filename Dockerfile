FROM lscr.io/linuxserver/transmission:latest

# TRANSMISSION_VERSION is inherited from the upstream linuxserver/transmission image
ENV PUID=911
ENV PGID=911

# Add ARG for VPN credentials
ARG VPN_USER
ARG VPN_PASS

# Add ARG for VPN configuration variables
ARG VPN_CLIENT
ARG VPN_CONFIG
ARG ENABLE_PRIVOXY

# Add ARG for general configuration variables
ARG DEBUG
ARG UMASK
ARG NAME_SERVERS
ARG VPN_OPTIONS
ARG LAN_NETWORK
ARG ADDITIONAL_PORTS
ARG PRIVOXY_PORT
ARG DISABLE_HAUGENE_COMPATIBILITY

# Add ARG for Transmission configuration variables
ARG TRANSMISSION_RPC_AUTHENTICATION_REQUIRED
ARG TRANSMISSION_RPC_USERNAME
ARG TRANSMISSION_RPC_PASSWORD
ARG TRANSMISSION_RPC_HOST_WHITELIST
ARG TRANSMISSION_RPC_WHITELIST_ENABLED
ARG TRANSMISSION_PEER_PORT
ARG TRANSMISSION_INCOMPLETE_DIR
ARG TRANSMISSION_INCOMPLETE_DIR_ENABLED
ARG TRANSMISSION_WATCH_DIR
ARG TRANSMISSION_WATCH_DIR_ENABLED
ARG TRANSMISSION_BLOCKLIST_ENABLED
ARG TRANSMISSION_BLOCKLIST_URL
ARG TRANSMISSION_WEB_UI
ARG TRANSMISSION_WEB_UI_AUTO
ARG HEALTH_CHECK_HOST
ARG LOG_TO_STDOUT

# Add ARG for built-in exporter
ARG TRANSMISSION_EXPORTER_ENABLED
ARG TRANSMISSION_EXPORTER_PORT

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
ENV DISABLE_HAUGENE_COMPATIBILITY=${DISABLE_HAUGENE_COMPATIBILITY:-false}

# Transmission Specific Settings (picked up by linuxserver.io base image init scripts)
ENV TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=${TRANSMISSION_RPC_AUTHENTICATION_REQUIRED:-false}
ENV TRANSMISSION_RPC_USERNAME=${TRANSMISSION_RPC_USERNAME:-}
# hadolint ignore=DL3002,SecretsUsedInArgOrEnv
ENV TRANSMISSION_RPC_PASSWORD=${TRANSMISSION_RPC_PASSWORD:-}
ENV TRANSMISSION_RPC_HOST_WHITELIST=${TRANSMISSION_RPC_HOST_WHITELIST:-"127.0.0.1,192.168.*.*,10.*.*.*,172.16.*.*"}
ENV TRANSMISSION_RPC_WHITELIST_ENABLED=${TRANSMISSION_RPC_WHITELIST_ENABLED:-true}
ENV TRANSMISSION_PEER_PORT=${TRANSMISSION_PEER_PORT:-}
# Default for incomplete directory path. Base image usually defaults to /downloads/incomplete if this is enabled and path is empty.
ENV TRANSMISSION_INCOMPLETE_DIR=${TRANSMISSION_INCOMPLETE_DIR:-/downloads/incomplete}
ENV TRANSMISSION_INCOMPLETE_DIR_ENABLED=${TRANSMISSION_INCOMPLETE_DIR_ENABLED:-true}
# Watch directory path. Default to /watch which matches our volume mount.
ENV TRANSMISSION_WATCH_DIR=${TRANSMISSION_WATCH_DIR:-/watch}
# Watch directory itself is fixed to /watch via volume mount. This toggles the feature.
ENV TRANSMISSION_WATCH_DIR_ENABLED=${TRANSMISSION_WATCH_DIR_ENABLED:-true}
ENV TRANSMISSION_BLOCKLIST_ENABLED=${TRANSMISSION_BLOCKLIST_ENABLED:-true}
# Base image provides its own default URL for the blocklist if this is empty and blocklist is enabled.
ENV TRANSMISSION_BLOCKLIST_URL=${TRANSMISSION_BLOCKLIST_URL:-}

# Additional features from haugene compatibility
ENV TRANSMISSION_WEB_UI=${TRANSMISSION_WEB_UI:-}
ENV TRANSMISSION_WEB_UI_AUTO=${TRANSMISSION_WEB_UI_AUTO:-}
ENV HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-google.com}
ENV LOG_TO_STDOUT=${LOG_TO_STDOUT:-false}

# Built-in Prometheus exporter settings
ENV TRANSMISSION_EXPORTER_ENABLED=${TRANSMISSION_EXPORTER_ENABLED:-false}
ENV TRANSMISSION_EXPORTER_PORT=${TRANSMISSION_EXPORTER_PORT:-9099}

# Install OpenVPN, WireGuard, Privoxy and tools
RUN apk add --no-cache openvpn iptables bash curl iproute2 wireguard-tools privoxy unzip git && \
    for f in /etc/privoxy/*.new; do mv -n "$f" "${f%.new}"; done

# Install transmission-exporter binary
RUN curl -L "https://github.com/metalmatze/transmission-exporter/releases/download/v0.3.0/transmission-exporter_0.3.0_linux_amd64.tar.gz" \
    -o /tmp/exporter.tar.gz && \
    tar -xzf /tmp/exporter.tar.gz -C /usr/local/bin/ && \
    rm /tmp/exporter.tar.gz && \
    chmod +x /usr/local/bin/transmission-exporter

# Expose metrics port
EXPOSE 9099

# Copy s6-overlay init scripts
COPY root/etc/cont-init.d/01-ensure-vpn-config-dirs.sh /etc/cont-init.d/01-ensure-vpn-config-dirs
COPY root/etc/cont-init.d/02-setup-transmission-features.sh /etc/cont-init.d/02-setup-transmission-features
COPY root/etc/cont-init.d/03-setup-directory-compatibility.sh /etc/cont-init.d/03-setup-directory-compatibility
COPY root/etc/cont-init.d/04-setup-web-ui-auto-download.sh /etc/cont-init.d/04-setup-web-ui-auto-download
COPY root/vpn-setup.sh /etc/cont-init.d/50-vpn-setup

# Copy healthcheck script
COPY root/healthcheck.sh /root/healthcheck.sh

# Copy Privoxy configuration template and s6 service files
COPY config/privoxy/config /etc/privoxy/config.template
COPY root_s6/privoxy/run /etc/s6-overlay/s6-rc.d/privoxy/run

# Copy transmission-exporter s6 service
COPY root_s6/transmission-exporter/run /etc/s6-overlay/s6-rc.d/transmission-exporter/run

# Set up s6 services
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/privoxy/type && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/transmission-exporter/type && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/privoxy && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/transmission-exporter

# Make scripts executable
RUN chmod +x /etc/cont-init.d/* /root/healthcheck.sh /etc/s6-overlay/s6-rc.d/privoxy/run /etc/s6-overlay/s6-rc.d/transmission-exporter/run

# Healthcheck
HEALTHCHECK --interval=1m --timeout=10s --start-period=2m --retries=3 \
  CMD /root/healthcheck.sh

# CMD is inherited from linuxserver base

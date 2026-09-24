# Main image - Pin to specific version for better security tracking
# Updated to latest stable release (4.1.3-r0-ls362 from 2026-09-15)
FROM lscr.io/linuxserver/transmission:4.1.3-r0-ls362

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
ARG DNS_CHECK_HOST
ARG LOG_TO_STDOUT

# Add ARG for built-in metrics
ARG METRICS_ENABLED
ARG METRICS_PORT
ARG METRICS_INTERVAL

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
# Default to public DNS to avoid local DNS blocking issues
ENV NAME_SERVERS=${NAME_SERVERS:-8.8.8.8,1.1.1.1}
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
# Connectivity probe target. An IP on purpose: the ping is then a pure
# reachability test through the tunnel and does not also depend on DNS.
ENV HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-1.1.1.1}
# DNS probe target, kept separate because it must be a NAME. getent returns
# success for a literal IP without resolving anything, so pointing the DNS
# check at HEALTH_CHECK_HOST made it pass unconditionally.
ENV DNS_CHECK_HOST=${DNS_CHECK_HOST:-one.one.one.one}
ENV LOG_TO_STDOUT=${LOG_TO_STDOUT:-false}

# Built-in custom metrics server settings
ENV METRICS_ENABLED=${METRICS_ENABLED:-false}
ENV METRICS_PORT=${METRICS_PORT:-9099}
ENV METRICS_INTERVAL=${METRICS_INTERVAL:-30}

# VPN Monitoring and Kill Switch settings
ENV VPN_CHECK_INTERVAL=${VPN_CHECK_INTERVAL:-30}
ENV VPN_MAX_FAILURES=${VPN_MAX_FAILURES:-3}
ENV CHECK_DNS=${CHECK_DNS:-true}
ENV CHECK_EXTERNAL_IP=${CHECK_EXTERNAL_IP:-true}
ENV AUTO_RESTART_VPN=${AUTO_RESTART_VPN:-false}
ENV RESTART_COOLDOWN_SECONDS=${RESTART_COOLDOWN_SECONDS:-300}
ENV MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS:-3}
# Stop the container (non-zero exit) once MAX_RESTART_ATTEMPTS is used up, so the
# orchestrator restarts it with fresh state. false keeps the old wait-for-a-human behaviour.
ENV EXIT_ON_MAX_RESTARTS=${EXIT_ON_MAX_RESTARTS:-true}
ENV NOTIFICATION_WEBHOOK_URL=${NOTIFICATION_WEBHOOK_URL:-}

# PIA Port Forwarding settings
# Set to true to enable PIA port forwarding (requires non-US PIA server)
ENV PIA_PORT_FORWARD=${PIA_PORT_FORWARD:-false}

# Update package index and upgrade existing packages first for security
# Then install required packages
# hadolint ignore=DL3018
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache \
    openvpn \
    iptables \
    bash \
    curl \
    iproute2 \
    wireguard-tools \
    openresolv \
    privoxy \
    unzip \
    python3 \
    py3-requests \
    py3-psutil \
    jq \
    bind-tools && \
    # Remove git as it's not needed at runtime (reduces attack surface)
    # Clean up package cache
    rm -rf /var/cache/apk/* && \
    for f in /etc/privoxy/*.new; do mv -n "$f" "${f%.new}" 2>/dev/null || true; done && \
    # Create non-root user for security (use different UID to avoid conflicts)
    adduser -D -s /bin/bash -u 1002 transmission-user && \
    # Ensure proper permissions for required directories
    mkdir -p /config /downloads /watch && \
    chown -R transmission-user:transmission-user /config /downloads /watch

# Copy custom metrics server
COPY --chmod=755 scripts/transmission-metrics-server.py /usr/local/bin/transmission-metrics-server.py

# Expose metrics port
EXPOSE 9099

# Copy s6-overlay init scripts with proper permissions
COPY --chmod=755 root/etc/cont-init.d/01-ensure-vpn-config-dirs.sh /etc/cont-init.d/01-ensure-vpn-config-dirs
COPY --chmod=755 root/etc/cont-init.d/02-setup-transmission-features.sh /etc/cont-init.d/02-setup-transmission-features
COPY --chmod=755 root/etc/cont-init.d/03-setup-directory-compatibility.sh /etc/cont-init.d/03-setup-directory-compatibility
COPY --chmod=755 root/etc/cont-init.d/05-reset-vpn-monitor-state.sh /etc/cont-init.d/05-reset-vpn-monitor-state
COPY --chmod=755 root/vpn-setup.sh /etc/cont-init.d/50-vpn-setup
# After vpn-setup, so the web UI download goes through the tunnel.
COPY --chmod=755 root/etc/cont-init.d/60-setup-web-ui-auto-download.sh /etc/cont-init.d/60-setup-web-ui-auto-download

# Copy healthcheck script and the tunnel probe it shares with vpn-monitor
COPY --chmod=755 root/healthcheck.sh /root/healthcheck.sh
COPY --chmod=755 root/vpn-probe.sh /usr/local/bin/vpn-probe.sh
# OpenVPN remote parsing, sourced by vpn-setup.sh, vpn-monitor and pia-port-forward.sh
COPY --chmod=755 root/vpn-remotes.sh /usr/local/bin/vpn-remotes.sh

# Copy Privoxy configuration template and s6 service files
COPY config/privoxy/config /etc/privoxy/config.template
COPY --chmod=755 root_s6/privoxy/run /etc/s6-overlay/s6-rc.d/privoxy/run

# Copy custom metrics s6 service
COPY --chmod=755 root_s6/custom-metrics/run /etc/s6-overlay/s6-rc.d/custom-metrics/run

# Copy VPN monitor s6 service
COPY --chmod=755 root_s6/vpn-monitor/run /etc/s6-overlay/s6-rc.d/vpn-monitor/run
COPY --chmod=755 root_s6/vpn-monitor/finish /etc/s6-overlay/s6-rc.d/vpn-monitor/finish

# Copy PIA port forwarding s6 service
COPY --chmod=755 root_s6/pia-port-forward/run /etc/s6-overlay/s6-rc.d/pia-port-forward/run
COPY --chmod=755 root_s6/pia-port-forward/finish /etc/s6-overlay/s6-rc.d/pia-port-forward/finish

# Copy PIA port forwarding script and its shared firewall helper.
# The helper is sourced by pia-port-forward.sh and exec'd by vpn-setup.sh, so
# it must be copied alongside both.
COPY --chmod=755 root/pia-port-forward.sh /usr/local/bin/pia-port-forward.sh
COPY --chmod=755 root/pia-pf-firewall.sh /usr/local/bin/pia-pf-firewall.sh

# Set up s6 services
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/privoxy/type && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/custom-metrics/type && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/vpn-monitor/type && \
    echo "oneshot" > /etc/s6-overlay/s6-rc.d/pia-port-forward/type && \
    echo "/etc/s6-overlay/s6-rc.d/pia-port-forward/run" > /etc/s6-overlay/s6-rc.d/pia-port-forward/up && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/privoxy && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/custom-metrics && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/vpn-monitor && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/pia-port-forward && \
    # s6-overlay starts the user bundle in parallel with the cont-init scripts, so
    # Transmission, cron and Privoxy used to run on the container's empty, all-ACCEPT
    # firewall until vpn-setup (cont-init 50) locked it down. Make them wait for
    # cont-init to finish, i.e. for the tunnel and the kill switch.
    mkdir -p /etc/s6-overlay/s6-rc.d/init-services/dependencies.d \
             /etc/s6-overlay/s6-rc.d/svc-transmission/dependencies.d \
             /etc/s6-overlay/s6-rc.d/privoxy/dependencies.d && \
    touch /etc/s6-overlay/s6-rc.d/init-services/dependencies.d/legacy-cont-init \
          /etc/s6-overlay/s6-rc.d/svc-transmission/dependencies.d/legacy-cont-init \
          /etc/s6-overlay/s6-rc.d/privoxy/dependencies.d/legacy-cont-init && \
    # Set proper ownership for metrics script
    chown -R transmission-user:transmission-user /usr/local/bin/transmission-metrics-server.py

# Add security labels
LABEL security.scan="enabled" \
      security.updates="auto" \
      org.opencontainers.image.title="transmissionvpn" \
      org.opencontainers.image.description="Transmission with VPN kill switch" \
      org.opencontainers.image.vendor="magicalyak" \
      org.opencontainers.image.licenses="GPL-3.0"

# Healthcheck
HEALTHCHECK --interval=1m --timeout=10s --start-period=2m --retries=3 \
  CMD /root/healthcheck.sh

# Note: LinuxServer.io base image handles user switching via PUID/PGID
# The non-root user created above satisfies security scanning requirements
# while maintaining compatibility with the base image's user management

# CMD is inherited from linuxserver base
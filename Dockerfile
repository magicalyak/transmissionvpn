FROM ghcr.io/linuxserver/nzbget:latest

# Override with NZBGet v25
ENV NZBGET_VERSION=25.0

# Install OpenVPN and tools
RUN apk add --no-cache openvpn iptables bash curl iproute2

# Copy scripts
COPY root/ /root/
RUN chmod +x /root/init.sh /root/healthcheck.sh

# Set entrypoint script
CMD ["/root/init.sh"]

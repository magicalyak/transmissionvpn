#!/bin/bash
# shellcheck shell=bash
# Shared tunnel reachability probe.
#
# Sourced by /root/healthcheck.sh and by the vpn-monitor service, so there is one
# definition of "the tunnel carries traffic". vpn-monitor used to run its own
# single-packet ping to a hardcoded 1.1.1.1 while the health check used the
# multi-packet, two-target probe below; the two could disagree about the same tunnel.
#
# vpn-monitor publishes the result of this probe to /tmp/vpn_tunnel_state, which is
# what the unprivileged metrics server reports as transmissionvpn_vpn_connected.

# Primary connectivity probe target. Default is Cloudflare (1.1.1.1), which
# answers ICMP reliably. Avoid Google anycast IPs (e.g. 8.8.8.8) as the primary
# target: they aggressively rate-limit/drop ICMP from VPN exit IPs, which causes
# the connectivity check to false-fail and trip the kill switch.
HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-1.1.1.1}
# Secondary connectivity probe target. Only counts a connectivity failure when
# BOTH the primary and fallback fail, so a single host's ICMP filtering can't
# trip the kill switch. Set to empty to disable the fallback.
HEALTH_CHECK_HOST_FALLBACK=${HEALTH_CHECK_HOST_FALLBACK-9.9.9.9}

# Callers may define probe_warn before sourcing this file to route warnings into
# their own log format.
if ! declare -F probe_warn >/dev/null; then
    probe_warn() { echo "[VPN-PROBE] WARN: $*" >&2; }
fi

# A private address cannot answer "is the tunnel carrying traffic": it is not
# routed through the VPN interface, so the probe fails no matter how healthy the
# tunnel is. Substitute a public target and say so loudly, rather than reporting
# a connectivity failure that is really a configuration mistake.
override_lan_probe_target() {
    case "$HEALTH_CHECK_HOST" in
        10.*|192.168.*|127.*|169.254.*|\
        172.1[6-9].*|172.2[0-9].*|172.3[01].*)
            probe_warn "HEALTH_CHECK_HOST ($HEALTH_CHECK_HOST) is a private address and is not routed through the VPN, so it cannot test tunnel connectivity. Using 1.1.1.1 instead; set HEALTH_CHECK_HOST to a public address to silence this."
            HEALTH_CHECK_HOST="1.1.1.1"
            ;;
    esac
}

# Probe a single host through the VPN interface.
# Sends multiple ICMP packets so a single dropped/rate-limited reply doesn't
# register as a failure: ping exits 0 if any one of the packets is answered.
ping_host_via_vpn() {
    local vpn_if="$1"
    local host="$2"
    # -c 3: send 3 packets, -i 0.5: short interval to keep latency low,
    # -W 3: wait up to 3s for a reply. Success if >=1 packet is answered.
    ping -c 3 -i 0.5 -W 3 -I "$vpn_if" "$host" > /dev/null 2>&1
}

# Returns 0 if HEALTH_CHECK_HOST, or failing that HEALTH_CHECK_HOST_FALLBACK,
# answers through <vpn_if>, and prints the host that answered. Returns 1 only
# when both fail. Worst case is roughly 8 seconds.
vpn_probe_tunnel() {
    local vpn_if="$1"

    if ping_host_via_vpn "$vpn_if" "$HEALTH_CHECK_HOST"; then
        echo "$HEALTH_CHECK_HOST"
        return 0
    fi
    if [ -n "$HEALTH_CHECK_HOST_FALLBACK" ] && ping_host_via_vpn "$vpn_if" "$HEALTH_CHECK_HOST_FALLBACK"; then
        echo "$HEALTH_CHECK_HOST_FALLBACK"
        return 0
    fi
    return 1
}

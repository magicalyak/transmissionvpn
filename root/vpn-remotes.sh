#!/bin/bash
# shellcheck shell=bash
# Shared OpenVPN remote handling.
#
# Sourced by vpn-setup.sh, vpn-monitor (run and finish) and pia-port-forward.sh.
# Each of them used to read only the first "remote" line of the .ovpn, so the kill
# switch opened a hole for that one server and every fallback remote was dropped.
# OpenVPN moves down the remote list when a server stops answering (and shuffles it
# with remote-random), so a fallback without an exception can never connect.
#
# Callers may define remote_log before sourcing this file to route messages into
# their own log format.

VPN_REMOTE_STATE_FILE="${VPN_REMOTE_STATE_FILE:-/tmp/openvpn_connected_remote}"
OPENVPN_LOG_FILE="${OPENVPN_LOG_FILE:-/tmp/openvpn.log}"

if ! declare -F remote_log >/dev/null; then
    remote_log() { echo "[VPN-REMOTES] $*"; }
fi

vpn_is_ipv4() {
    [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

# Print one "host port proto" line per remote directive in CONFIG.
# A remote line is "remote HOST [PORT] [PROTO]". Missing fields come from the
# global port/proto directives, then OpenVPN's defaults (1194, udp). OpenVPN
# accepts udp4, udp6, tcp-client, tcp4 and so on; iptables wants udp or tcp.
vpn_list_remotes() {
    local config="$1" default_port default_proto host port proto

    [ -r "$config" ] || return 1
    default_port=$(tr -d '\r' < "$config" | awk '$1 == "port" { print $2; exit }')
    default_proto=$(tr -d '\r' < "$config" | awk '$1 == "proto" { print $2; exit }')
    default_port="${default_port:-1194}"
    default_proto="${default_proto:-udp}"

    while read -r _ host port proto _; do
        [ -n "$host" ] || continue
        port="${port:-$default_port}"
        proto="${proto:-$default_proto}"
        case "${proto,,}" in
            tcp*) proto="tcp" ;;
            *) proto="udp" ;;
        esac
        echo "$host $port $proto"
    done < <(tr -d '\r' < "$config" | grep -E '^[[:space:]]*remote[[:space:]]')
}

# Print every IPv4 address HOST resolves to, one per line. OpenVPN may connect to
# any of them, so all of them need an exception.
vpn_resolve_ipv4() {
    local host="$1" ips

    if vpn_is_ipv4 "$host"; then
        echo "$host"
        return 0
    fi
    # The server lines in nslookup output end in #53 or :53 and are filtered out here.
    ips=$(nslookup "$host" 2>/dev/null | awk '/^Address:/ { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)
    if [ -z "$ips" ]; then
        ips=$({ getent ahostsv4 "$host" 2>/dev/null || getent hosts "$host" 2>/dev/null; } | awk '{ print $1 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)
    fi
    [ -n "$ips" ] || return 1
    echo "$ips"
}

# Add an OUTPUT rule unless an identical one is already there.
# Returns 0 when added, 1 when already present, 2 when iptables refused it.
vpn_ensure_output_rule() {
    local mode="$1"
    shift
    iptables -C OUTPUT "$@" 2>/dev/null && return 1
    if [ "$mode" = "insert" ]; then
        iptables -I OUTPUT 1 "$@" || return 2
    else
        iptables -A OUTPUT "$@" || return 2
    fi
}

# Allow OpenVPN to reach every address of every remote in CONFIG over eth0.
# MODE is "append" (building a chain) or "insert" (a live chain that already ends
# in DROP). Without any remote directive, OpenVPN's default port 1194 is allowed
# on udp and tcp so a config that sets its server some other way still connects.
# Sets VPN_REMOTE_COUNT and VPN_EXCEPTION_COUNT for the caller.
vpn_allow_remotes() {
    local config="$1" mode="${2:-append}" host port proto ips ip rc

    VPN_REMOTE_COUNT=0
    VPN_EXCEPTION_COUNT=0

    while read -r host port proto; do
        VPN_REMOTE_COUNT=$((VPN_REMOTE_COUNT + 1))
        case "$port" in
            '' | *[!0-9]*)
                remote_log "WARN: Skipping VPN remote $host: invalid port '$port'"
                continue
                ;;
        esac
        if ! ips=$(vpn_resolve_ipv4 "$host"); then
            remote_log "WARN: Could not resolve VPN remote $host. OpenVPN will not be able to use this remote."
            continue
        fi
        for ip in $ips; do
            rc=0
            vpn_ensure_output_rule "$mode" -o eth0 -d "$ip" -p "$proto" --dport "$port" -j ACCEPT || rc=$?
            case "$rc" in
                0)
                    remote_log "Kill switch exception for VPN remote $host: $ip:$port ($proto)"
                    VPN_EXCEPTION_COUNT=$((VPN_EXCEPTION_COUNT + 1))
                    ;;
                2) remote_log "WARN: Failed to add kill switch exception for $ip:$port ($proto)" ;;
            esac
        done
    done < <(vpn_list_remotes "$config")

    if [ "$VPN_REMOTE_COUNT" -eq 0 ]; then
        remote_log "WARN: No remote directive found in $config. Allowing OpenVPN's default port 1194 (udp and tcp)."
        for proto in udp tcp; do
            if vpn_ensure_output_rule "$mode" -o eth0 -p "$proto" --dport 1194 -j ACCEPT; then
                VPN_EXCEPTION_COUNT=$((VPN_EXCEPTION_COUNT + 1))
            fi
        done
        return 0
    fi

    remote_log "Added $VPN_EXCEPTION_COUNT kill switch exception(s) for $VPN_REMOTE_COUNT OpenVPN remote(s)"
}

# Print the remote OpenVPN is connected to, as written in CONFIG (hostname or IP).
# The address comes from $trusted_ip, which the up script records, or failing that
# from the last "link remote" line in the OpenVPN log. It is mapped back to the
# remote line it came from; if none matches (DNS changed since), the address itself
# is printed. Returns 1 when the connected address is unknown.
vpn_connected_remote() {
    local config="$1" ip="" host ips

    if [ -r "$VPN_REMOTE_STATE_FILE" ]; then
        read -r ip _ < "$VPN_REMOTE_STATE_FILE" || true
    fi
    if ! vpn_is_ipv4 "$ip"; then
        ip=$(grep -oE 'link remote: \[AF_INET\][0-9.]+' "$OPENVPN_LOG_FILE" 2>/dev/null | tail -1 | sed 's/.*\]//' || true)
    fi
    vpn_is_ipv4 "$ip" || return 1

    # Literal addresses first, so a match never costs a DNS lookup.
    while read -r host _; do
        if [ "$host" = "$ip" ]; then
            echo "$host"
            return 0
        fi
    done < <(vpn_list_remotes "$config")
    while read -r host _; do
        vpn_is_ipv4 "$host" && continue
        if ips=$(vpn_resolve_ipv4 "$host") && grep -qxF "$ip" <<< "$ips"; then
            echo "$host"
            return 0
        fi
    done < <(vpn_list_remotes "$config")

    echo "$ip"
}

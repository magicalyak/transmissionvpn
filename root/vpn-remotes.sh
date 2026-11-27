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
# in DROP). Any further arguments are added to each rule, e.g. a comment match.
# Without any remote directive, OpenVPN's default port 1194 is allowed on udp and
# tcp so a config that sets its server some other way still connects.
# Sets VPN_REMOTE_COUNT and VPN_EXCEPTION_COUNT for the caller.
vpn_allow_remotes() {
    local config="$1" mode="${2:-append}" host port proto ips ip rc
    shift 2 || shift $#

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
            vpn_ensure_output_rule "$mode" -o eth0 -d "$ip" -p "$proto" --dport "$port" "$@" -j ACCEPT || rc=$?
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
            if vpn_ensure_output_rule "$mode" -o eth0 -p "$proto" --dport 1194 "$@" -j ACCEPT; then
                VPN_EXCEPTION_COUNT=$((VPN_EXCEPTION_COUNT + 1))
            fi
        done
        return 0
    fi

    remote_log "Added $VPN_EXCEPTION_COUNT kill switch exception(s) for $VPN_REMOTE_COUNT OpenVPN remote(s)"
}

# Succeed if any remote in CONFIG is a hostname, i.e. OpenVPN needs DNS to reach it.
vpn_remotes_need_dns() {
    local host
    while read -r host _; do
        vpn_is_ipv4 "$host" || return 0
    done < <(vpn_list_remotes "$1")
    return 1
}

# Print one "host port" line per WireGuard peer Endpoint in CONFIG. IPv6 endpoints
# are skipped: IPv6 is dropped outright by the kill switch.
vpn_list_wg_endpoints() {
    local config="$1" endpoint
    [ -r "$config" ] || return 1
    while read -r endpoint; do
        case "$endpoint" in
            \[*) continue ;;
            *:*) echo "${endpoint%:*} ${endpoint##*:}" ;;
        esac
    done < <(tr -d '\r' < "$config" | awk -F= 'tolower($1) ~ /^[[:space:]]*endpoint[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2 }')
}

# Succeed if any WireGuard endpoint in CONFIG is a hostname.
vpn_wg_endpoints_need_dns() {
    local host
    while read -r host _; do
        vpn_is_ipv4 "$host" || return 0
    done < <(vpn_list_wg_endpoints "$1")
    return 1
}

# Allow WireGuard to reach every peer endpoint in CONFIG over eth0 (udp).
# MODE and any further arguments work as for vpn_allow_remotes.
# Returns 1 if any endpoint got no exception, so a caller never reports a working
# kill switch whose tunnel cannot reach its server.
vpn_allow_wg_endpoints() {
    local config="$1" mode="${2:-append}" host port ips ip rc failed=0
    shift 2 || shift $#
    while read -r host port; do
        case "$port" in
            '' | *[!0-9]*)
                remote_log "WARN: Skipping WireGuard endpoint $host: invalid port '$port'"
                failed=1
                continue
                ;;
        esac
        if ! ips=$(vpn_resolve_ipv4 "$host"); then
            remote_log "WARN: Could not resolve WireGuard endpoint $host."
            failed=1
            continue
        fi
        for ip in $ips; do
            rc=0
            vpn_ensure_output_rule "$mode" -o eth0 -d "$ip" -p udp --dport "$port" "$@" -j ACCEPT || rc=$?
            case "$rc" in
                0) remote_log "Kill switch exception for WireGuard endpoint $host: $ip:$port (udp)" ;;
                2) remote_log "WARN: Failed to add kill switch exception for $ip:$port (udp)"; failed=1 ;;
            esac
        done
    done < <(vpn_list_wg_endpoints "$config")
    return "$failed"
}

# --- WireGuard effective config ----------------------------------------------
#
# wg-quick never sees the user's file. vpn_wg_prepare writes a copy to
# $WG_EFFECTIVE_DIR/<interface>.conf (tmpfs, mode 600, never in /config) with:
#  - every Endpoint hostname replaced by the IPv4 address it resolved to during
#    bootstrap, so the tunnel and the permanent kill switch exception use the same
#    address and nothing needs DNS after the bootstrap rules are gone;
#  - DNS lines removed (written to <conf>.dns instead): vpn-setup owns
#    /etc/resolv.conf, so wg-quick never calls resolvconf, which fails in Docker
#    with "signature mismatch";
#  - IPv6 entries removed from Address, AllowedIPs and DNS when IPv6 is disabled
#    in the container (wg-quick's `ip -6 address add` fails there);
#  - in compat routing, Table and FwMark set so wg-quick skips its default-route
#    code, which needs the raw table. vpn_wg_compat_up does the rest.

WG_EFFECTIVE_DIR="${WG_EFFECTIVE_DIR:-/run/wireguard}"
VPN_IPV6_SYSCTL="${VPN_IPV6_SYSCTL:-/proc/sys/net/ipv6/conf/all/disable_ipv6}"
WG_COMPAT_RULE_PRIO="${WG_COMPAT_RULE_PRIO:-32764}"

vpn_wg_effective_config() {
    echo "$WG_EFFECTIVE_DIR/$1.conf"
}

vpn_ipv6_disabled() {
    [ ! -e "$VPN_IPV6_SYSCTL" ] || [ "$(cat "$VPN_IPV6_SYSCTL" 2>/dev/null)" = 1 ]
}

# Print the value of the first KEY line in CONFIG (case-insensitive), whitespace removed.
vpn_wg_value() {
    tr -d '\r' < "$1" | awk -F= -v k="$2" 'tolower($1) ~ "^[[:space:]]*" k "[[:space:]]*$" { sub(/^[^=]*=/, ""); gsub(/[[:space:]]/, ""); print; exit }'
}

# Succeed if CONFIG routes all IPv4 traffic into the tunnel.
vpn_wg_has_default_route() {
    tr -d '\r' < "$1" | awk -F= 'tolower($1) ~ /^[[:space:]]*allowedips[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); n = split($2, a, ","); for (i = 1; i <= n; i++) if (a[i] == "0.0.0.0/0") f = 1 } END { exit !f }'
}

# The fwmark and routing table of compat routing: the config's FwMark, else 51820.
vpn_wg_compat_table() {
    local mark
    mark=$(vpn_wg_value "$1" fwmark)
    case "$mark" in
        '' | off) echo 51820 ;;
        *) printf '%d\n' "$mark" ;;
    esac
}

# vpn_wg_prepare SRC DST COMPAT(0|1)
# Endpoint addresses are cached in $WG_EFFECTIVE_DIR/endpoints. When a hostname
# cannot be resolved (an in-place restart, where resolv.conf already points into
# the tunnel that is down), the address from the last run is reused.
vpn_wg_prepare() {
    local src="$1" dst="$2" compat="${3:-0}" host port ip map="" strip6=0 cache table
    cache="$WG_EFFECTIVE_DIR/endpoints"
    mkdir -p "$WG_EFFECTIVE_DIR" && chmod 700 "$WG_EFFECTIVE_DIR" || return 1

    while read -r host port; do
        vpn_is_ipv4 "$host" && continue
        if ip=$(vpn_resolve_ipv4 "$host"); then
            ip=${ip%%$'\n'*}
        elif ip=$(awk -v h="$host" '$1 == h { print $2; exit }' "$cache" 2>/dev/null) && [ -n "$ip" ]; then
            remote_log "WARN: Could not resolve WireGuard endpoint $host; reusing $ip from the last run."
        else
            remote_log "ERROR: Could not resolve WireGuard endpoint $host. Refusing to start a tunnel the kill switch cannot allow."
            return 1
        fi
        map="$map $host=$ip"
        remote_log "WireGuard endpoint $host resolved to $ip:$port."
    done < <(vpn_list_wg_endpoints "$src")
    # Rewrite the cache from this run, keeping older entries for hosts not seen now.
    { for host in $map; do echo "${host%%=*} ${host#*=}"; done
      awk -v m="$map" 'BEGIN { n = split(m, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); s[kv[1]] = 1 } } !($1 in s)' "$cache" 2>/dev/null || true
    } > "$cache.tmp" && mv "$cache.tmp" "$cache"

    if vpn_ipv6_disabled; then
        strip6=1
        remote_log "IPv6 is disabled in this container: using only the IPv4 entries of the WireGuard config."
    fi
    table=$(vpn_wg_compat_table "$src")

    (umask 077; tr -d '\r' < "$src" | awk -v map="$map" -v strip6="$strip6" -v compat="$compat" \
        -v table="$table" -v dnsfile="$dst.dns" '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        function keep4(v,   n, a, i, out) {
            n = split(v, a, ","); out = ""
            for (i = 1; i <= n; i++) { a[i] = trim(a[i]); if (a[i] == "" || (strip6 && a[i] ~ /:/)) continue; out = out (out == "" ? "" : ", ") a[i] }
            return out
        }
        BEGIN {
            n = split(map, m, " ")
            for (i = 1; i <= n; i++) { split(m[i], kv, "="); ep[kv[1]] = kv[2] }
            printf "" > dnsfile
        }
        /^[[:space:]]*\[/ {
            sect = tolower(trim($0)); print
            if (sect == "[interface]" && compat) { print "Table = " table; print "FwMark = " table }
            next
        }
        {
            key = tolower(trim(substr($0, 1, index($0, "=") - 1))); val = trim(substr($0, index($0, "=") + 1))
        }
        index($0, "=") == 0 { print; next }
        sect == "[interface]" && key == "dns" { v = keep4(val); if (v != "") print v > dnsfile; next }
        sect == "[interface]" && compat && (key == "table" || key == "fwmark") { next }
        key == "address" || key == "allowedips" { v = keep4(val); if (v != "") print (key == "address" ? "Address" : "AllowedIPs") " = " v; next }
        sect == "[peer]" && key == "endpoint" {
            h = val; sub(/:[0-9]+$/, "", h); p = substr(val, length(h) + 1)
            if (h in ep) { print "Endpoint = " ep[h] p; next }
        }
        { print }
    ' > "$dst") || return 1

    if [ -z "$(vpn_wg_value "$dst" address)" ]; then
        remote_log "ERROR: The WireGuard config has no usable Address (IPv6 is disabled and only IPv6 addresses are set)."
        return 1
    fi
}

# Compat routing: what wg-quick's default-route code does, without the raw table.
# Idempotent: rules from an earlier run are removed first.
vpn_wg_compat_down() {
    local t="$1" p="$WG_COMPAT_RULE_PRIO"
    while ip -4 rule del priority "$p" table main suppress_prefixlength 0 2>/dev/null; do :; done
    while ip -4 rule del priority "$((p + 1))" not fwmark "$t" table "$t" 2>/dev/null; do :; done
}

# vpn_wg_compat_up INTERFACE TABLE TAG
vpn_wg_compat_up() {
    local ifc="$1" t="$2" tag="$3" p="$WG_COMPAT_RULE_PRIO" a
    vpn_wg_compat_down "$t"
    ip -4 rule add priority "$p" table main suppress_prefixlength 0 || return 1
    ip -4 rule add priority "$((p + 1))" not fwmark "$t" table "$t" || return 1
    # Replies to the WireGuard socket carry the fwmark, so rp_filter checks them
    # against the main table (needs src_valid_mark=1, as wg-quick sets).
    sysctl -q -w net.ipv4.conf.all.src_valid_mark=1 2>/dev/null ||
        [ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark 2>/dev/null)" = 1 ] ||
        remote_log "WARN: net.ipv4.conf.all.src_valid_mark is not 1; set it with --sysctl if the tunnel gets no replies."
    iptables -t mangle -A POSTROUTING -m mark --mark "$t" -p udp -m comment --comment "$tag" -j CONNMARK --save-mark || return 1
    iptables -t mangle -A PREROUTING -p udp -m comment --comment "$tag" -j CONNMARK --restore-mark || return 1
    # wg-quick's anti-spoofing rule (raw PREROUTING): nothing may reach the tunnel
    # address from outside the tunnel. In filter INPUT, first, before any ACCEPT.
    for a in $(ip -4 -o addr show dev "$ifc" | awk '{ print $4 }' | cut -d/ -f1); do
        iptables -I INPUT 1 ! -i "$ifc" -d "$a" -m addrtype ! --src-type LOCAL -m comment --comment "$tag" -j DROP || return 1
    done
    remote_log "WireGuard compat routing: fwmark/table $t, rules at priority $p and $((p + 1))."
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

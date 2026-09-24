#!/bin/bash
# The single-quoted snippets in this file are code for the inner shells, so their
# expansions are meant to happen there, not here.
# shellcheck disable=SC2016
# Tests for the OpenVPN remote handling in root/vpn-remotes.sh and its callers.
#
# The kill switch used to open a hole for the first remote only, so OpenVPN could
# never fall back to the others. The helper is sourced as shipped, and the kill
# switch block of vpn-setup.sh and the 19999 rule of pia-port-forward.sh are
# extracted from the shipped scripts. iptables, nslookup and getent are stubbed:
# no network, no root, no container.

set -e

# The code under test runs on the image's bash 5 and uses ${var,,}. macOS ships 3.2.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Needs bash 4 or newer (this is $BASH_VERSION). Run it in the image instead:"
    echo "  docker run --rm -v \"\$PWD\":/src -w /src bash:5 bash test-vpn-remotes.sh"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }

expect_eq() {
    if [ "$1" = "$2" ]; then
        log_pass "$3"
    else
        log_fail "$3"
        echo "    expected: $(printf '%q' "$2")"
        echo "    actual:   $(printf '%q' "$1")"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTES_LIB="$SCRIPT_DIR/root/vpn-remotes.sh"
VPN_SETUP="$SCRIPT_DIR/root/vpn-setup.sh"
PIA_PF="$SCRIPT_DIR/root/pia-port-forward.sh"

echo "================================================"
echo "   OpenVPN remote handling tests"
echo "================================================"
echo ""

WORK="$(mktemp -d)"
export WORK
trap 'rm -rf "$WORK"' EXIT

# A minimal iptables: rules are "CHAIN spec..." lines in $WORK/rules.
iptables() {
    local op="$1" chain="$2"
    shift 2
    case "$op" in
        -A) echo "$chain $*" >> "$WORK/rules" ;;
        -I)
            [ "$1" = "1" ] && shift
            { echo "$chain $*"; cat "$WORK/rules"; } > "$WORK/rules.new"
            mv "$WORK/rules.new" "$WORK/rules"
            ;;
        -C) grep -qxF -- "$chain $*" "$WORK/rules" ;;
        -D) grep -vxF -- "$chain $*" "$WORK/rules" > "$WORK/rules.new" || true
            mv "$WORK/rules.new" "$WORK/rules" ;;
        *) return 1 ;;
    esac
}
# busybox nslookup output. The server lines must not be taken for answers.
nslookup() {
    echo "Server:		10.43.0.10"
    echo "Address:	10.43.0.10:53"
    echo ""
    case "$1" in
        multi.example.net)
            echo "Name:	multi.example.net"
            echo "Address: 198.51.100.20"
            echo "Name:	multi.example.net"
            echo "Address: 198.51.100.21"
            echo "Name:	multi.example.net"
            echo "Address: 2001:db8::1"
            ;;
        single.example.net)
            echo "Name:	single.example.net"
            echo "Address: 198.51.100.30"
            ;;
        *)
            echo "** server can't find $1: NXDOMAIN"
            return 1
            ;;
    esac
}
getent() {
    case "$2" in
        getent-only.example.net) echo "198.51.100.40   getent-only.example.net" ;;
        *) return 2 ;;
    esac
}
export -f iptables nslookup getent

reset_rules() { : > "$WORK/rules"; }
rules() { cat "$WORK/rules"; }

VPN_REMOTE_STATE_FILE="$WORK/connected_remote"
OPENVPN_LOG_FILE="$WORK/openvpn.log"
remote_log() { echo "$*" >> "$WORK/log"; }
# shellcheck source=root/vpn-remotes.sh
. "$REMOTES_LIB"

# ---------------------------------------------------------------------------
echo "--- Three IP remotes (the production config) ---"
cat > "$WORK/three.ovpn" <<'EOF'
client
dev tun
proto udp
remote 209.200.239.8 8080
remote 209.200.239.9 8080
remote 209.200.239.10 8080
remote-random
remote-cert-tls server
#remote 192.0.2.99 8080
EOF
reset_rules
vpn_allow_remotes "$WORK/three.ovpn" append
expect_eq "$(rules)" "OUTPUT -o eth0 -d 209.200.239.8 -p udp --dport 8080 -j ACCEPT
OUTPUT -o eth0 -d 209.200.239.9 -p udp --dport 8080 -j ACCEPT
OUTPUT -o eth0 -d 209.200.239.10 -p udp --dport 8080 -j ACCEPT" \
    "every remote gets an exception; remote-random, remote-cert-tls and comments are not remotes"
expect_eq "$VPN_REMOTE_COUNT/$VPN_EXCEPTION_COUNT" "3/3" "counts three remotes and three exceptions"

vpn_allow_remotes "$WORK/three.ovpn" append
expect_eq "$(rules | wc -l | tr -d ' ')" "3" "running it again adds nothing"
expect_eq "$VPN_EXCEPTION_COUNT" "0" "and reports no new exceptions"

# ---------------------------------------------------------------------------
echo ""
echo "--- Global proto tcp-client and port 443, duplicate remote, CRLF ---"
printf 'client\r\nproto tcp-client\r\nport 443\r\nremote 203.0.113.5\r\nremote 203.0.113.6\r\nremote 203.0.113.5\r\nremote 203.0.113.7 1198 udp4\r\n  remote 203.0.113.8 8443\r\n' > "$WORK/crlf.ovpn"
expect_eq "$(vpn_list_remotes "$WORK/crlf.ovpn")" "203.0.113.5 443 tcp
203.0.113.6 443 tcp
203.0.113.5 443 tcp
203.0.113.7 1198 udp
203.0.113.8 8443 tcp" "missing port/proto come from the globals, per-remote values win, CR stripped"
reset_rules
vpn_allow_remotes "$WORK/crlf.ovpn" append
expect_eq "$(rules)" "OUTPUT -o eth0 -d 203.0.113.5 -p tcp --dport 443 -j ACCEPT
OUTPUT -o eth0 -d 203.0.113.6 -p tcp --dport 443 -j ACCEPT
OUTPUT -o eth0 -d 203.0.113.7 -p udp --dport 1198 -j ACCEPT
OUTPUT -o eth0 -d 203.0.113.8 -p tcp --dport 8443 -j ACCEPT" \
    "duplicate remote skipped, no carriage return in any rule"
expect_eq "$VPN_REMOTE_COUNT/$VPN_EXCEPTION_COUNT" "5/4" "five remotes, four exceptions"

# ---------------------------------------------------------------------------
echo ""
echo "--- Hostnames: multiple A records, unresolvable, getent fallback ---"
cat > "$WORK/hosts.ovpn" <<'EOF'
client
remote multi.example.net 1198
remote gone.example.net 1198
remote getent-only.example.net 1198
EOF
reset_rules
: > "$WORK/log"
vpn_allow_remotes "$WORK/hosts.ovpn" append
expect_eq "$(rules)" "OUTPUT -o eth0 -d 198.51.100.20 -p udp --dport 1198 -j ACCEPT
OUTPUT -o eth0 -d 198.51.100.21 -p udp --dport 1198 -j ACCEPT
OUTPUT -o eth0 -d 198.51.100.40 -p udp --dport 1198 -j ACCEPT" \
    "every IPv4 address is allowed, IPv6 and the DNS server are ignored, getent is the fallback"
expect_eq "$(grep -c 'Could not resolve VPN remote gone.example.net' "$WORK/log")" "1" \
    "an unresolvable remote is reported and skipped, not fatal"

# ---------------------------------------------------------------------------
echo ""
echo "--- No remote directive ---"
printf 'client\ndev tun\n' > "$WORK/none.ovpn"
reset_rules
vpn_allow_remotes "$WORK/none.ovpn" append
expect_eq "$(rules)" "OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT
OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT" "falls back to 1194 on udp and tcp"

# ---------------------------------------------------------------------------
echo ""
echo "--- Insert mode (vpn-monitor restart into a live chain) ---"
reset_rules
echo "OUTPUT -j DROP" > "$WORK/rules"
vpn_allow_remotes "$WORK/three.ovpn" insert
expect_eq "$(rules | tail -1)" "OUTPUT -j DROP" "exceptions go in front of the final DROP"
expect_eq "$(rules | wc -l | tr -d ' ')" "4" "one exception per remote"

# ---------------------------------------------------------------------------
echo ""
echo "--- The remote OpenVPN actually connected to ---"
cat > "$WORK/mixed.ovpn" <<'EOF'
remote 209.200.239.8 8080
remote single.example.net 8080
remote 209.200.239.10 8080
EOF
rm -f "$VPN_REMOTE_STATE_FILE" "$OPENVPN_LOG_FILE"
expect_eq "$(vpn_connected_remote "$WORK/mixed.ovpn" || echo "rc=$?")" "rc=1" "unknown when nothing is recorded"

echo "209.200.239.10 8080" > "$VPN_REMOTE_STATE_FILE"
expect_eq "$(vpn_connected_remote "$WORK/mixed.ovpn")" "209.200.239.10" "a fallback IP remote from \$trusted_ip"

echo "198.51.100.30 8080" > "$VPN_REMOTE_STATE_FILE"
expect_eq "$(vpn_connected_remote "$WORK/mixed.ovpn")" "single.example.net" "mapped back to the hostname it resolves from"

echo " " > "$VPN_REMOTE_STATE_FILE"
cat > "$OPENVPN_LOG_FILE" <<'EOF'
2026-09-24 10:00:00 UDPv4 link remote: [AF_INET]209.200.239.8:8080
2026-09-24 10:05:00 UDPv4 link remote: [AF_INET]209.200.239.10:8080
EOF
expect_eq "$(vpn_connected_remote "$WORK/mixed.ovpn")" "209.200.239.10" "without \$trusted_ip, the last link remote in the log"

echo "192.0.2.50 8080" > "$VPN_REMOTE_STATE_FILE"
expect_eq "$(vpn_connected_remote "$WORK/mixed.ovpn")" "192.0.2.50" "an address no remote maps to is reported as is"

# ---------------------------------------------------------------------------
echo ""
echo "--- vpn-setup.sh kill switch block, as shipped ---"
awk '
    /^# KILL SWITCH FIX/ { inside = 1 }
    inside && /^elif / { print "fi"; exit }
    inside { print }
' "$VPN_SETUP" > "$WORK/setup-block.sh"
if ! grep -q vpn_allow_remotes "$WORK/setup-block.sh"; then
    log_fail "Could not extract the kill switch block from $VPN_SETUP"
else
    reset_rules
    # The variables and log() are read by the extracted block.
    # shellcheck disable=SC2034,SC2329
    (
        VPN_CLIENT=OpenVPN
        OVPN_CONFIG_FILE="$WORK/three.ovpn"
        set -e
        # shellcheck disable=SC1091
        . "$WORK/setup-block.sh"
    ) > "$WORK/setup.out"
    expect_eq "$(grep -c -- '-o eth0 -d 209.200.239' "$WORK/rules")" "3" "vpn-setup.sh allows all three remotes"
    expect_eq "$(grep -c 'dport 53' "$WORK/rules")" "0" "and opens no DNS on eth0"
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- pia-port-forward.sh 19999 rule ---"
awk '
    /^# Ensure iptables allows traffic to the PIA gateway/ { inside = 1 }
    inside { print }
    inside && /^fi$/ { exit }
' "$PIA_PF" > "$WORK/pf-block.sh"
reset_rules
for _ in 1 2 3; do
    # shellcheck disable=SC2034,SC2329
    (
        log() { :; }
        PF_GATEWAY=10.25.18.1
        # shellcheck disable=SC1091
        . "$WORK/pf-block.sh"
    )
done
expect_eq "$(rules)" "OUTPUT -d 10.25.18.1 -p tcp --dport 19999 -j ACCEPT" "three runs leave exactly one rule"

echo ""
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

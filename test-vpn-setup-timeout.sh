#!/bin/bash
# Tests for openvpn_up_timeout() in vpn-setup.sh: how long setup waits for
# OpenVPN's 'up' script before giving up. It must cover one full pass over every
# remote line, or a dead first remote restart-loops the container while the
# others are up (a fixed 60s wait did exactly that).
#
# The function is extracted from the shipped root/vpn-setup.sh, so this test
# cannot drift from the code it is checking. No container or network is needed.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_SETUP="$SCRIPT_DIR/root/vpn-setup.sh"

echo "================================================"
echo "   vpn-setup.sh OpenVPN wait tests"
echo "================================================"
echo ""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

awk '/^openvpn_up_timeout\(\) \{/,/^\}/' "$VPN_SETUP" > "$WORK/fn.sh"
if [ ! -s "$WORK/fn.sh" ]; then
    log_fail "Could not extract openvpn_up_timeout from $VPN_SETUP"
    exit 1
fi
# shellcheck disable=SC1091
source "$WORK/fn.sh"

expect() {
    local desc="$1" want="$2" config="$3" got
    printf '%b' "$config" > "$WORK/test.ovpn"
    got=$(openvpn_up_timeout "$WORK/test.ovpn")
    if [ "$got" = "$want" ]; then
        log_pass "$desc ($got s)"
    else
        log_fail "$desc: expected $want, got $got"
    fi
}

unset VPN_UP_TIMEOUT
expect "one remote, OpenVPN defaults" 95 \
    "client\nremote 1.2.3.4 1198\n"
expect "three remotes, OpenVPN defaults" 225 \
    "client\nremote 1.2.3.4 8080\nremote 1.2.3.5 8080\nremote 1.2.3.6 8080\n"
expect "three remotes, server-poll-timeout below hand-window still waits for hand-window" 225 \
    "client\nremote a 1\nremote b 1\nremote c 1\nserver-poll-timeout 10\n"
expect "hand-window 15 shortens the wait" 90 \
    "client\nremote a 1\nremote b 1\nremote c 1\nhand-window 15\n"
expect "server-poll-timeout above hand-window wins" 140 \
    "client\nremote a 1\nremote b 1\nconnect-timeout 50\nhand-window 20\n"
expect "indented remotes and CRLF line endings are counted" 160 \
    "client\r\n  remote a 1\r\n\tremote b 1\r\n"
expect "remote-cert-tls and commented remotes are not counted" 95 \
    "client\nremote a 1\n# remote b 1\nremote-cert-tls server\n"
expect "no remote lines still waits for one" 95 \
    "client\n"

export VPN_UP_TIMEOUT=400
expect "VPN_UP_TIMEOUT overrides" 400 "client\nremote a 1\n"
export VPN_UP_TIMEOUT=abc
expect "non-numeric VPN_UP_TIMEOUT is ignored" 95 "client\nremote a 1\n"
unset VPN_UP_TIMEOUT

echo ""
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

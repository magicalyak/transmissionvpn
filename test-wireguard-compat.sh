#!/bin/bash
# Tests for the WireGuard effective config, compat routing and the RPC bind fix:
#   - vpn_wg_prepare, vpn_wg_compat_up/down, vpn_allow_wg_endpoints (root/vpn-remotes.sh, sourced)
#   - wg_routing_mode (extracted from root/vpn-setup.sh)
#   - root/etc/cont-init.d/04-rpc-bind-ipv4.sh (run against temp files; needs jq)
# DNS, ip and iptables are stubbed: no network, no root, no container.
# shellcheck disable=SC2016

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }
check() { if eval "$2"; then log_pass "$1"; else log_fail "$1"; fi; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "================================================"
echo "   WireGuard compat / IPv4-only / DNS / RPC tests"
echo "================================================"

export WG_EFFECTIVE_DIR="$WORK/run" VPN_IPV6_SYSCTL="$WORK/disable_ipv6"
remote_log() { echo "$*" >> "$WORK/log"; }
# shellcheck source=root/vpn-remotes.sh
. "$SCRIPT_DIR/root/vpn-remotes.sh"

# DNS stub: $WORK/dns holds "host ip" lines.
vpn_resolve_ipv4() {
    vpn_is_ipv4 "$1" && { echo "$1"; return 0; }
    awk -v h="$1" '$1 == h { print $2; f = 1 } END { exit !f }' "$WORK/dns" 2>/dev/null
}

cat > "$WORK/airvpn.conf" <<'EOF'
[Interface]
PrivateKey = KEY
Address = 10.1.2.3/32, fd7d:76ee::1/128
DNS = 10.128.0.1, fd7d:76ee::1
PostUp = echo user-hook

[Peer]
PublicKey = PUB
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ch3.vpn.example:1637
EOF
echo "ch3.vpn.example 203.0.113.7" > "$WORK/dns"

echo ""
echo "1. IPv6 disabled, compat routing"
echo 1 > "$VPN_IPV6_SYSCTL"
export OUT="$WORK/run/airvpn.conf"   # used inside the check strings
check "prepare succeeds" 'vpn_wg_prepare "$WORK/airvpn.conf" "$OUT" 1'
check "endpoint hostname replaced by its address" 'grep -qx "Endpoint = 203.0.113.7:1637" "$OUT"'
check "IPv6 removed from Address" 'grep -qx "Address = 10.1.2.3/32" "$OUT"'
check "IPv6 removed from AllowedIPs" 'grep -qx "AllowedIPs = 0.0.0.0/0" "$OUT"'
check "DNS line removed (no resolvconf)" '! grep -qi "^DNS" "$OUT"'
check "IPv4 DNS kept for vpn-setup" '[ "$(cat "$OUT.dns")" = "10.128.0.1" ]'
check "compat sets Table and FwMark" 'grep -qx "Table = 51820" "$OUT" && grep -qx "FwMark = 51820" "$OUT"'
check "user hooks and keys kept" 'grep -qx "PostUp = echo user-hook" "$OUT" && grep -qx "PrivateKey = KEY" "$OUT"'
check "effective config not world-readable" '[ "$(stat -c %a "$OUT" 2>/dev/null || echo 600)" = 600 ] || [ "$(uname -o 2>/dev/null)" = Msys ]'
check "user config untouched" 'grep -q "ch3.vpn.example" "$WORK/airvpn.conf"'

echo ""
echo "2. IPv6 enabled, standard routing"
echo 0 > "$VPN_IPV6_SYSCTL"
check "prepare succeeds" 'vpn_wg_prepare "$WORK/airvpn.conf" "$OUT" 0'
check "dual-stack kept when IPv6 works" 'grep -q "fd7d:76ee::1/128" "$OUT" && grep -q "::/0" "$OUT"'
check "no Table/FwMark in standard mode" '! grep -qiE "^(Table|FwMark)" "$OUT"'
check "DNS still removed" '! grep -qi "^DNS" "$OUT"'

echo ""
echo "3. Endpoint resolution"
: > "$WORK/dns"
check "unresolvable endpoint reuses the cached address" 'vpn_wg_prepare "$WORK/airvpn.conf" "$OUT" 0 && grep -qx "Endpoint = 203.0.113.7:1637" "$OUT"'
rm -f "$WORK/run/endpoints"
check "unresolvable endpoint without cache fails" '! vpn_wg_prepare "$WORK/airvpn.conf" "$OUT" 0'

echo ""
echo "4. IPv6-only Address with IPv6 disabled fails"
echo 1 > "$VPN_IPV6_SYSCTL"
sed 's#^Address = .*#Address = fd7d:76ee::1/128#; s#^Endpoint = .*#Endpoint = 203.0.113.7:1637#' "$WORK/airvpn.conf" > "$WORK/v6only.conf"
check "no usable Address is an error" '! vpn_wg_prepare "$WORK/v6only.conf" "$WORK/run/v6only.conf" 0'

echo ""
echo "5. Kill switch exceptions"
iptables() { echo "iptables $*" >> "$WORK/fw"; [ "$1" = -C ] && return 1; return 0; }
: > "$WORK/fw"
check "literal endpoint gets an exception" 'vpn_allow_wg_endpoints "$OUT" append && grep -q -- "-A OUTPUT -o eth0 -d 203.0.113.7 -p udp --dport 1637 -j ACCEPT" "$WORK/fw"'
check "unresolvable endpoint is reported as failure" '! vpn_allow_wg_endpoints "$WORK/airvpn.conf" append'

echo ""
echo "6. Compat routing rules"
ip() {
    echo "ip $*" >> "$WORK/ip"
    case "$*" in
        "-4 rule del"*) [ -s "$WORK/rules" ] && { sed -i 1d "$WORK/rules"; return 0; }; return 1 ;;
        "-4 rule add"*) echo "$*" >> "$WORK/rules" ;;
        "-4 -o addr show dev wg0") echo "5: wg0    inet 10.1.2.3/32 scope global wg0" ;;
    esac
}
sysctl() { return 1; }
: > "$WORK/fw"; : > "$WORK/rules"
vpn_wg_compat_up wg0 51820 vpn-setup
vpn_wg_compat_up wg0 51820 vpn-setup
check "re-run does not duplicate policy rules" '[ "$(wc -l < "$WORK/rules")" = 2 ]'
check "suppress_prefixlength rule before the tunnel table" 'grep -q "priority 32764 table main suppress_prefixlength 0" "$WORK/rules" && grep -q "priority 32765 not fwmark 51820 table 51820" "$WORK/rules"'
check "anti-spoofing replaces the raw rule" 'grep -q -- "-I INPUT 1 ! -i wg0 -d 10.1.2.3 -m addrtype ! --src-type LOCAL -m comment --comment vpn-setup -j DROP" "$WORK/fw"'
check "CONNMARK save/restore tagged for cleanup" 'grep -q -- "-t mangle -A POSTROUTING -m mark --mark 51820 -p udp -m comment --comment vpn-setup -j CONNMARK --save-mark" "$WORK/fw"'
unset -f ip sysctl

echo ""
echo "7. Routing mode selection"
awk '/^wg_routing_mode\(\) \{/,/^\}/' "$SCRIPT_DIR/root/vpn-setup.sh" > "$WORK/fn_mode.sh"
# shellcheck disable=SC1091
. "$WORK/fn_mode.sh"
iptables() { [ "$*" = "-t raw -S" ] && [ -n "$NO_RAW" ] && return 1; return 0; }
check "raw table present: standard" '[ "$(wg_routing_mode "$WORK/airvpn.conf" 2>/dev/null)" = standard ]'
check "raw table missing: compat" '[ "$(NO_RAW=1 wg_routing_mode "$WORK/airvpn.conf" 2>/dev/null)" = compat ]'
sed '/^\[Interface\]/a Table = 123' "$WORK/airvpn.conf" > "$WORK/own-table.conf"
check "own Table = is left to the user" '[ "$(NO_RAW=1 wg_routing_mode "$WORK/own-table.conf" 2>/dev/null)" = standard ]'
check "explicit compat honoured" '[ "$(WIREGUARD_ROUTING=compat wg_routing_mode "$WORK/airvpn.conf")" = compat ]'
check "invalid WIREGUARD_ROUTING fails" '! WIREGUARD_ROUTING=bogus wg_routing_mode "$WORK/airvpn.conf" 2>/dev/null'

echo ""
echo "8. RPC bind address"
RPC="$SCRIPT_DIR/root/etc/cont-init.d/04-rpc-bind-ipv4.sh"
if command -v jq >/dev/null 2>&1; then
    run_rpc() { TRANSMISSION_SETTINGS="$WORK/settings.json" TRANSMISSION_DEFAULT_SETTINGS="$WORK/none" bash "$RPC" > "$WORK/rpc.out"; }
    echo 1 > "$VPN_IPV6_SYSCTL"
    echo '{"rpc-bind-address": "[::]", "rpc-port": 9091}' > "$WORK/settings.json"; run_rpc
    check "IPv6 wildcard becomes 0.0.0.0" '[ "$(jq -r ".\"rpc-bind-address\"" "$WORK/settings.json")" = 0.0.0.0 ]'
    check "other settings kept" '[ "$(jq -r ".\"rpc-port\"" "$WORK/settings.json")" = 9091 ]'
    echo '{"rpc-bind-address": "192.168.1.5"}' > "$WORK/settings.json"; run_rpc
    check "specific IPv4 bind left alone" '[ "$(jq -r ".\"rpc-bind-address\"" "$WORK/settings.json")" = 192.168.1.5 ]'
    echo '{"rpc-bind-address": "fd00::5"}' > "$WORK/settings.json"; run_rpc
    check "specific IPv6 bind reported, not widened" '[ "$(jq -r ".\"rpc-bind-address\"" "$WORK/settings.json")" = fd00::5 ] && grep -q ERROR "$WORK/rpc.out"'
    echo 0 > "$VPN_IPV6_SYSCTL"
    echo '{"rpc-bind-address": "[::]"}' > "$WORK/settings.json"; run_rpc
    check "IPv6 enabled: nothing changed" '[ "$(jq -r ".\"rpc-bind-address\"" "$WORK/settings.json")" = "[::]" ]'
else
    echo "  (jq not installed: RPC bind tests skipped)"
fi

echo ""
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

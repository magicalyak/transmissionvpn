#!/bin/bash
# The single-quoted snippets in this file are code for the stubs, so their
# expansions are meant to happen there, not here.
# shellcheck disable=SC2016
# End-to-end test that vpn-setup.sh never opens the firewall while the tunnel comes up.
#
# vpn-setup.sh used to reset every policy to ACCEPT and flush the chains before
# starting the VPN client, and vpn-monitor re-runs it in place on every restart.
# With the tunnel routes gone, everything in the container (Transmission, Privoxy)
# could leave through eth0 until setup finished.
#
# It also flushed the nat and mangle tables. On Docker user-defined networks
# (Compose's default) the nat table holds the rules that make Docker's embedded DNS
# server at 127.0.0.11 work, so hostname VPN servers could not be resolved there.
#
# This runs the shipped vpn-setup.sh from start to finish with iptables, ip6tables,
# ip, openvpn, wg-quick and nslookup stubbed, and records the firewall at the moment
# the VPN client is launched. It writes /etc/resolv.conf, /etc/openvpn and /tmp, so it
# only runs as root in a throwaway container:
#   docker run --rm -v "$PWD":/src -w /src bash:5 bash test-vpn-setup-bootstrap.sh

set -e

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Needs bash 4 or newer (this is $BASH_VERSION)."
    exit 1
fi
if [ "$(id -u)" -ne 0 ] || { [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ -z "$KUBERNETES_SERVICE_HOST" ]; }; then
    echo "Refusing to run: this test rewrites /etc/resolv.conf and /tmp state, so it only runs"
    echo "as root inside a throwaway container:"
    echo "  docker run --rm -v \"\$PWD\":/src -w /src bash:5 bash test-vpn-setup-bootstrap.sh"
    exit 1
fi

# The up script vpn-setup.sh generates, and the stubs below, start with #!/bin/bash.
# The bash:5 image only has /usr/local/bin/bash.
[ -e /bin/bash ] || ln -s "$(command -v bash)" /bin/bash

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
VPN_SETUP="${VPN_SETUP:-$SCRIPT_DIR/root/vpn-setup.sh}"
export VPN_REMOTES_LIB="$SCRIPT_DIR/root/vpn-remotes.sh"

echo "================================================"
echo "   vpn-setup.sh tunnel bootstrap tests"
echo "================================================"
echo ""

WORK="$(mktemp -d "$SCRIPT_DIR/.bootstrap-test.XXXXXX")"
export FW="$WORK/fw"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$FW"

# fweval DIR OUT_IF DST PROTO DPORT STATE CTDIR
# First-match evaluation of DIR/OUTPUT for one packet, as the kernel would.
# Prints "ACCEPT <rule>", "DROP <rule>" or "<policy> policy". A match it does not
# know is treated as matching, so a rule it cannot read is never assumed safe.
cat > "$WORK/bin/fweval" <<'EOF'
#!/bin/bash
dir=$1 out=$2 dst=$3 proto=$4 dport=$5 state=$6 ctdir=$7
ip2int() { local IFS=.; set -- $1; n=$(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )); }
in_net() {
    local net=${1%/*} bits=32 a b m
    [ "$net" != "$1" ] && bits=${1#*/}
    m=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    ip2int "$dst"; a=$n; ip2int "$net"; b=$n
    [ $(( a & m )) -eq $(( b & m )) ]
}
tst() { if "$@"; then t=y; else t=n; fi; }
set -f
while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    set -- $rule
    neg=false match=true target=""
    while [ $# -gt 0 ]; do
        case "$1" in
            !) neg=true; shift; continue ;;
            -o) tst [ "$2" = "$out" ] ;;
            -d) tst in_net "$2" ;;
            -p) tst [ "$2" = "$proto" ] ;;
            --dport) tst [ "$2" = "$dport" ] ;;
            --state|--ctstate) case ",$2," in *",$state,"*) t=y ;; *) t=n ;; esac ;;
            --ctdir) tst [ "$2" = "$ctdir" ] ;;
            -m|--comment|--limit) shift 2; continue ;;
            -j) target=$2; break ;;
            *) echo "fweval: unknown match '$1' in: $rule" >&2; t=y ;;
        esac
        if $neg; then [ "$t" = y ] && t=n || t=y; neg=false; fi
        [ "$t" = y ] || match=false
        shift 2
    done
    if $match; then
        case "$target" in
            ACCEPT) echo "ACCEPT $rule"; exit 0 ;;
            DROP|REJECT) echo "DROP $rule"; exit 0 ;;
        esac
    fi
done < "$dir/OUTPUT"
echo "$(cat "$dir/policy.OUTPUT" 2>/dev/null || echo ACCEPT) policy"
EOF
chmod +x "$WORK/bin/fweval"

# iptables with state: one file per chain, policies in $FW/<tool>/policy.CHAIN, and
# every policy change appended to $FW/policy-history. The filter table lives in
# $FW/<tool>, other tables in $FW/<tool>.<table>, and every flush is logged to
# $FW/flushes.
cat > "$WORK/bin/iptables" <<'EOF'
#!/bin/bash
tool=$(basename "$0")
table=filter
if [ "$1" = "-t" ]; then
    table=$2
    shift 2
fi
dir="$FW/$tool"
[ "$table" = filter ] || dir="$FW/$tool.$table"
mkdir -p "$dir"
op="$1" chain="$2"
shift 2
[ -n "$chain" ] && touch "$dir/$chain"
case "$op" in
    -P) echo "$1" > "$dir/policy.$chain"; echo "$tool $chain $1" >> "$FW/policy-history" ;;
    -F) if [ -z "$chain" ]; then
            for f in "$dir"/*; do case "$f" in */policy.*) ;; *) [ -f "$f" ] && : > "$f" ;; esac; done
        else
            : > "$dir/$chain"
        fi
        echo "$table ${chain:-all}" >> "$FW/flushes" ;;
    -A) echo "$*" >> "$dir/$chain" ;;
    -I) [[ "$1" =~ ^[0-9]+$ ]] && shift
        { echo "$*"; cat "$dir/$chain"; } > "$dir/$chain.new" && mv "$dir/$chain.new" "$dir/$chain" ;;
    -C) grep -qxF -- "$*" "$dir/$chain" ;;
    -D) grep -qxF -- "$*" "$dir/$chain" || exit 1
        grep -vxF -- "$*" "$dir/$chain" > "$dir/$chain.new"; mv "$dir/$chain.new" "$dir/$chain" ;;
    -S) sed "s/^/-A $chain /" "$dir/$chain" ;;
    -X|-N) ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/iptables"
cp "$WORK/bin/iptables" "$WORK/bin/ip6tables"

cat > "$WORK/bin/ip" <<'EOF'
#!/bin/bash
args="$*"
case "$args" in
    "link show "*) echo "5: ${args##* }: <POINTOPOINT,UP,LOWER_UP> mtu 1500 state UNKNOWN" ;;
    "addr show eth0"|"-4 addr show dev eth0") echo "    inet 10.42.1.50/24 scope global eth0" ;;
    "addr show "*) echo "    inet 10.115.128.48/18 scope global ${args##* }" ;;
    "route"|"route show dev eth0") echo "default via 10.42.1.1 dev eth0" ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/ip"

# Record the firewall at launch, then do what the real client does next.
cat > "$WORK/bin/snapshot" <<'EOF'
#!/bin/bash
out="$FW/at-launch"
rm -rf "$out"; mkdir -p "$out"
cp "$FW"/iptables/* "$out"/ 2>/dev/null || true
EOF
chmod +x "$WORK/bin/snapshot"

cat > "$WORK/bin/openvpn" <<'EOF'
#!/bin/bash
snapshot
config="$2"
up=$(awk '$1 == "up" { print $2 }' "$config")
echo "UDPv4 link remote: [AF_INET]209.200.239.9:8080"
dev=tun0 trusted_ip=209.200.239.9 trusted_port=8080 "$up"
EOF
chmod +x "$WORK/bin/openvpn"

cat > "$WORK/bin/wg-quick" <<'EOF'
#!/bin/bash
snapshot
EOF
chmod +x "$WORK/bin/wg-quick"

# Docker's embedded DNS server (127.0.0.11) only answers while Docker's nat rules
# are in place: OUTPUT jumps to DOCKER_OUTPUT, which DNATs port 53 to the port the
# server listens on, over lo, and the filter table lets that through. It forwards
# to the first "# ExtServers:" entry, from the host's namespace for host(...), from
# this one (eth0) otherwise. Other nameservers always answer.
cat > "$WORK/bin/nslookup" <<'EOF'
#!/bin/bash
blocked() {
    echo "$1" >> "$FW/dns-blocked"
    echo ";; connection timed out; no servers could be reached"; exit 1
}
ns=$(awk '$1 == "nameserver" { print $2; exit }' /etc/resolv.conf)
if [ "$ns" = 127.0.0.11 ]; then
    nat="$FW/iptables.nat"
    grep -qxE -- '-d 127\.0\.0\.11(/32)? -j DOCKER_OUTPUT' "$nat/OUTPUT" 2>/dev/null ||
        blocked "$1 via $ns: nat OUTPUT has no jump to DOCKER_OUTPUT"
    dport=$(sed -n 's/.*-p udp .*--dport 53 -j DNAT --to-destination 127\.0\.0\.11:\([0-9]*\)$/\1/p' "$nat/DOCKER_OUTPUT" 2>/dev/null | head -1)
    [ -n "$dport" ] || blocked "$1 via $ns: DOCKER_OUTPUT has no DNAT for udp/53"
    verdict=$(fweval "$FW/iptables" lo "$ns" udp "$dport" NEW ORIGINAL)
    case "$verdict" in ACCEPT*) ;; *) blocked "$1 via $ns on lo: $verdict" ;; esac
    up=$(sed -n 's/^# ExtServers: \[\([^] ]*\).*/\1/p' /etc/resolv.conf)
    case "$up" in
        host\(*|"") ;;
        *) verdict=$(fweval "$FW/iptables" eth0 "$up" udp 53 NEW ORIGINAL)
           case "$verdict" in ACCEPT*) ;; *) blocked "$1 via $ns, forwarded to $up on eth0: $verdict" ;; esac ;;
    esac
fi
case "$1" in
    vpn.example.net) echo "Name: vpn.example.net"; echo "Address: 198.51.100.20"; echo "Address: 198.51.100.21" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/nslookup"

# In a pod, BusyBox cp cannot overwrite the bind-mounted /etc/resolv.conf ("File
# exists"). The image ships coreutils cp, which can, so behave like it.
cat > "$WORK/bin/cp" <<'EOF'
#!/bin/bash
if [ $# -eq 2 ] && [ "$2" = /etc/resolv.conf ]; then cat "$1" > "$2"; else exec /bin/cp "$@"; fi
EOF
chmod +x "$WORK/bin/cp"
export PATH="$WORK/bin:$PATH"

reset_state() {
    rm -rf "$FW" && mkdir -p "$FW"
    rm -f /tmp/vpn_setup_complete /tmp/openvpn_up_complete /tmp/openvpn_connected_remote \
          /tmp/resolv.conf.backup /tmp/vpn_interface_name /tmp/openvpn.log
    echo "nameserver 10.43.0.10" > /etc/resolv.conf
}

# A previous run's kill switch, as vpn-monitor's in-place restart finds it.
seed_previous_killswitch() {
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -A OUTPUT -o tun0 -j ACCEPT
    iptables -A OUTPUT -j DROP
    : > "$FW/policy-history"
}

run_setup() {
    local rc=0
    env "$@" bash "$VPN_SETUP" > "$WORK/setup.out" 2>&1 || rc=$?
    expect_eq "$rc" "0" "vpn-setup.sh exits 0"
    if [ "$rc" -ne 0 ]; then
        tail -20 "$WORK/setup.out" | sed 's/^/    | /'
    fi
}

check_common() {
    expect_eq "$(grep -c ACCEPT "$FW/policy-history" || true)" "0" "no policy is ever set to ACCEPT (iptables or ip6tables)"
    expect_eq "$(grep -c '^-o eth0 -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY' "$FW/at-launch/OUTPUT")" "1" \
        "at launch, established traffic leaves eth0 only as replies"
    expect_eq "$(grep -vc -e '^-o lo -m comment --comment vpn-bootstrap -j ACCEPT$' -e '--ctdir REPLY -m comment --comment vpn-bootstrap -j ACCEPT$' \
        -e '^-o eth0 -d [0-9.]* -p [a-z]* --dport [0-9]* -m comment --comment vpn-bootstrap -j ACCEPT$' "$FW/at-launch/OUTPUT" || true)" "0" \
        "at launch, OUTPUT holds nothing beyond loopback, replies and per-server exceptions"
    expect_eq "$(grep -c -- '-o tun0\|-o wg0' "$FW/at-launch/OUTPUT" || true)" "0" "the previous run's rules were flushed"
    expect_eq "$(grep -c 'vpn-bootstrap' "$FW/iptables/OUTPUT" "$FW/iptables/INPUT" | awk -F: '{ s += $2 } END { print s }')" "0" \
        "no bootstrap rule survives into the kill switch"
    expect_eq "$(grep -c -- '^-m state --state RELATED,ESTABLISHED -j ACCEPT$' "$FW/iptables/OUTPUT" || true)" "0" \
        "the kill switch has no interface-blind ESTABLISHED accept on OUTPUT"
    expect_eq "$(tail -1 "$FW/iptables/OUTPUT")" "-j DROP" "the kill switch still ends in DROP"
    expect_eq "$(cat "$FW/iptables/policy.OUTPUT")" "DROP" "OUTPUT policy is DROP at the end"
    if [ -f /tmp/vpn_setup_complete ]; then
        log_pass "setup completion flag written"
    else
        log_fail "setup completion flag missing"
    fi
}

# ---------------------------------------------------------------------------
echo "--- OpenVPN, three IP remotes, in-place restart ---"
reset_state
seed_previous_killswitch
cat > "$WORK/prod.ovpn" <<'EOF'
client
dev tun
proto udp
remote 209.200.239.8 8080
remote 209.200.239.9 8080
remote 209.200.239.10 8080
EOF
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/prod.ovpn" VPN_USER=u VPN_PASS=p NAME_SERVERS=1.1.1.1 METRICS_ENABLED=true
check_common
expect_eq "$(grep -c -- '-o eth0 -d 209.200.239.[0-9]* -p udp --dport 8080 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-launch/OUTPUT")" "3" \
    "at launch, every remote is reachable"
expect_eq "$(grep -c 'dport 53' "$FW/at-launch/OUTPUT" || true)" "0" "no DNS is opened when every remote is an IP"
expect_eq "$(grep -c -- '--dport 9091\|--dport 9099' "$FW/at-launch/INPUT")" "2" "web UI and metrics stay reachable for probes"
expect_eq "$(grep -c -- '^-o eth0 -d 209.200.239.[0-9]* -p udp --dport 8080 -j ACCEPT$' "$FW/iptables/OUTPUT")" "3" \
    "the kill switch keeps every remote"
expect_eq "$(cat /tmp/openvpn_connected_remote 2>/dev/null)" "209.200.239.9 8080" "the connected remote is recorded"

# ---------------------------------------------------------------------------
echo ""
echo "--- OpenVPN, hostname remote ---"
reset_state
cat > "$WORK/host.ovpn" <<'EOF'
client
proto udp
remote vpn.example.net 1198
EOF
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p NAME_SERVERS=1.1.1.1
check_common
expect_eq "$(grep 'dport 53' "$FW/at-launch/OUTPUT" | sort)" "-o eth0 -d 10.43.0.10 -p tcp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT
-o eth0 -d 10.43.0.10 -p udp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT" \
    "at launch, DNS is open only to the configured nameserver"
expect_eq "$(grep -c 'dport 53 .*-j ACCEPT' "$FW/iptables/OUTPUT" || true)" "0" "and is closed again afterwards"

# ---------------------------------------------------------------------------
echo ""
echo "--- WireGuard, hostname endpoint ---"
reset_state
cat > "$WORK/wg0.conf" <<'EOF'
[Interface]
PrivateKey = x
Address = 10.2.0.2/32

[Peer]
PublicKey = y
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.net:51820
EOF
run_setup VPN_CLIENT=wireguard VPN_CONFIG="$WORK/wg0.conf"
check_common
expect_eq "$(grep -c -- '-o eth0 -d 198.51.100.2[01] -p udp --dport 51820 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-launch/OUTPUT")" "2" \
    "at launch, every endpoint address is reachable"
expect_eq "$(grep -c -- '^-o eth0 -d 198.51.100.2[01] -p udp --dport 51820 -j ACCEPT$' "$FW/iptables/OUTPUT")" "2" \
    "the kill switch keeps every endpoint address"

# ---------------------------------------------------------------------------
# Docker user-defined networks (Compose's default): resolv.conf points at Docker's
# embedded DNS server, which works through nat rules Docker adds in the container.
# The rules and resolv.conf are as Docker Engine writes them (libnetwork
# resolver_unix.go setupIptablesNAT, internal/resolvconf).
DOCKER_UDP_PORT=52981
seed_docker_dns() {
    local nat="$FW/iptables.nat"
    mkdir -p "$nat" "$FW/iptables.mangle"
    echo "-d 127.0.0.11/32 -j DOCKER_OUTPUT" > "$nat/OUTPUT"
    echo "-d 127.0.0.11/32 -j DOCKER_POSTROUTING" > "$nat/POSTROUTING"
    printf '%s\n' "-d 127.0.0.11/32 -p tcp -m tcp --dport 53 -j DNAT --to-destination 127.0.0.11:41365" \
        "-d 127.0.0.11/32 -p udp -m udp --dport 53 -j DNAT --to-destination 127.0.0.11:$DOCKER_UDP_PORT" > "$nat/DOCKER_OUTPUT"
    printf '%s\n' "-s 127.0.0.11/32 -p tcp -m tcp --sport 41365 -j SNAT --to-source :53" \
        "-s 127.0.0.11/32 -p udp -m udp --sport $DOCKER_UDP_PORT -j SNAT --to-source :53" > "$nat/DOCKER_POSTROUTING"
    rm -rf "$WORK/docker-nat" && cp -R "$nat" "$WORK/docker-nat"
    # A mangle rule vpn-setup.sh does not own, like the ones wg-quick adds.
    echo '-p udp -m comment --comment "wg-quick(8) rule for wg0" -j CONNMARK --restore-mark --nfmask 0xffffffff --ctmask 0xffffffff' \
        > "$FW/iptables.mangle/PREROUTING"
}

# docker_resolv EXTSERVERS, e.g. "host(192.168.65.7)" or "1.1.1.1" (--dns 1.1.1.1).
docker_resolv() {
    cat > /etc/resolv.conf <<EOF
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 127.0.0.11
options ndots:0

# Based on host file: '/etc/resolv.conf' (internal resolver)
# ExtServers: [$1]
# Overrides: []
# Option ndots from: internal
EOF
}

check_docker() {
    expect_eq "$(cat "$FW/dns-blocked" 2>/dev/null)" "" "every VPN server lookup got through"
    expect_eq "$(diff -r "$WORK/docker-nat" "$FW/iptables.nat" 2>&1)" "" "Docker's nat rules for 127.0.0.11 are untouched"
    expect_eq "$(grep -v '^filter ' "$FW/flushes" 2>/dev/null || true)" "" "no chain outside the filter table is flushed"
    expect_eq "$(grep -c 'wg-quick(8)' "$FW/iptables.mangle/PREROUTING" || true)" "1" "a mangle rule vpn-setup.sh does not own is kept"
    expect_eq "$(cat "$FW"/iptables.mangle/PREROUTING "$FW"/iptables.mangle/OUTPUT | grep -c -- '--comment vpn-setup ' || true)" "2" \
        "vpn-setup.sh's own mangle rules are there once (web UI)"
    expect_eq "$(fweval "$FW/iptables" lo 127.0.0.11 udp "$DOCKER_UDP_PORT" NEW ORIGINAL | cut -d' ' -f1)" "DROP" \
        "Docker's DNS server is closed once the kill switch is built (it forwards from the host's namespace)"
    expect_eq "$(grep -c '^nameserver 127\.' /etc/resolv.conf || true)" "0" "resolv.conf no longer points at 127.0.0.11"
}

echo ""
echo "--- OpenVPN, hostname remote, Docker embedded DNS ---"
reset_state
seed_docker_dns
docker_resolv "host(192.168.65.7)"
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p
check_common
check_docker
expect_eq "$(grep -c 'dport 53' "$FW/at-launch/OUTPUT" || true)" "0" \
    "at launch, no DNS is opened on eth0 (the host's nameserver is queried from the host)"
expect_eq "$(grep -c -- '-o eth0 -d 198.51.100.2[01] -p udp --dport 1198 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-launch/OUTPUT")" "2" \
    "at launch, every address of the remote is reachable"

echo ""
echo "--- The same container, restarted in place by vpn-monitor ---"
rm -f "$FW/dns-blocked" "$FW/flushes" /tmp/vpn_setup_complete /tmp/openvpn_up_complete /tmp/resolv.conf.backup
docker_resolv "host(192.168.65.7)" # restored by the OpenVPN down script
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p
check_common
check_docker

echo ""
echo "--- OpenVPN, hostname remote, Docker embedded DNS with --dns 1.1.1.1 ---"
reset_state
seed_docker_dns
docker_resolv "1.1.1.1"
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p
check_common
check_docker
expect_eq "$(grep 'dport 53' "$FW/at-launch/OUTPUT" | sort)" "-o eth0 -d 1.1.1.1 -p tcp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT
-o eth0 -d 1.1.1.1 -p udp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT" \
    "at launch, DNS on eth0 is open only to the --dns server Docker forwards to"

echo ""
echo "--- WireGuard, hostname endpoint, Docker embedded DNS, no DNS configured ---"
reset_state
seed_docker_dns
docker_resolv "host(192.168.65.7)"
run_setup VPN_CLIENT=wireguard VPN_CONFIG="$WORK/wg0.conf"
check_common
check_docker
expect_eq "$(grep -c -- '-o eth0 -d 198.51.100.2[01] -p udp --dport 51820 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-launch/OUTPUT")" "2" \
    "at launch, every endpoint address is reachable"
expect_eq "$(awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf | tr '\n' ' ')" "1.1.1.1 8.8.8.8 " \
    "resolv.conf falls back to 1.1.1.1 and 8.8.8.8"

echo ""
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

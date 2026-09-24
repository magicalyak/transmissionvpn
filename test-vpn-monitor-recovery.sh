#!/bin/bash
# The single-quoted snippets in this file are code for the inner shells, so their
# expansions are meant to happen there, not here.
# shellcheck disable=SC2016
# Tests for vpn-monitor's tunnel check, restart limit and port-forward recovery.
#
# Covers the two defects behind the 38-hour outage of 2026-09-22:
#   - tun0 kept its address while nothing passed through it, and everything that
#     looked only at the interface reported the VPN as up;
#   - after MAX_RESTART_ATTEMPTS vpn-monitor logged "manual intervention required"
#     every ~35s forever while the web UI kept the container looking alive.
#
# The functions are extracted from the shipped root_s6/vpn-monitor/run and
# root/vpn-probe.sh rather than copied, so this test cannot drift from them. ip, ping,
# iptables, pkill, pgrep, kill and sleep are stubbed: no network, no root, no container.

set -e

# The code under test runs on the image's bash 5 and uses ${var,,}. macOS ships 3.2.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Needs bash 4 or newer (this is $BASH_VERSION). Run it in the image instead:"
    echo "  docker run --rm -v \"\$PWD\":/src -w /src bash:5 bash test-vpn-monitor-recovery.sh"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }

expect_match() {
    if echo "$1" | grep -q -- "$2"; then
        log_pass "$3"
    else
        log_fail "$3 - expected /$2/ in: $1"
    fi
}

expect_no_match() {
    if echo "$1" | grep -q -- "$2"; then
        log_fail "$3 - did not expect /$2/ in: $1"
    else
        log_pass "$3"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR="$SCRIPT_DIR/root_s6/vpn-monitor/run"
PROBE_LIB="$SCRIPT_DIR/root/vpn-probe.sh"

echo "================================================"
echo "   vpn-monitor recovery tests"
echo "================================================"
echo ""

WORK="$(mktemp -d)"
export WORK
trap 'rm -rf "$WORK"' EXIT

FUNCS="get_restart_count increment_restart_count reset_restart_count check_cooldown
       log_restart send_notification check_tunnel publish_tunnel_state wait_for_shutdown
       exit_container_for_restart restart_port_forwarding ensure_port_forwarding
       attempt_vpn_restart transmission_service_dir stop_transmission restart_transmission"
: > "$WORK/functions.sh"
for fn in $FUNCS; do
    awk -v fn="$fn" '
        $0 ~ "^"fn"\\(\\) \\{" { inside = 1 }
        inside { print }
        inside && /^\}/ { exit }
    ' "$MONITOR" > "$WORK/fn.sh"
    if [ ! -s "$WORK/fn.sh" ]; then
        log_fail "Could not extract $fn() from $MONITOR"
        exit 1
    fi
    cat "$WORK/fn.sh" >> "$WORK/functions.sh"
done

# Scripts that stand in for s6's halt, vpn-setup.sh and pia-port-forward.sh.
printf '#!/usr/bin/env bash\ntouch "$WORK/halted"\n' > "$WORK/halt"
printf '#!/usr/bin/env bash\nexit "${SETUP_RC:-0}"\n' > "$WORK/setup"
printf '#!/usr/bin/env bash\necho run >> "$WORK/pf_runs"\necho pf >> "$WORK/order"\n' > "$WORK/pf.sh"
chmod +x "$WORK/halt" "$WORK/setup" "$WORK/pf.sh"

# The harness. Environment knobs:
#   UP_IFS       interfaces that are UP
#   IP_IFS       interfaces that have an IPv4 address
#   ANSWERING    hosts that answer ping (empty = the tunnel drops everything)
#   ALIVE_PIDS   pids that kill -0 reports as alive
#   PGREP_OUT    what pgrep prints
cat > "$WORK/harness.sh" <<'EOF'
set -e
log() { echo "[VPN-MONITOR] $*"; }
probe_warn() { log "WARNING: $*"; }

RESTART_COUNT_FILE="$WORK/restart_count"
LAST_RESTART_FILE="$WORK/last_restart"
RESTART_LOG="$WORK/restart.log"
VPN_TUNNEL_STATE_FILE="$WORK/vpn_tunnel_state"
VPN_INTERFACE_FILE="$WORK/vpn_interface_name"
PIA_KEEPALIVE_PID_FILE="$WORK/pia_keepalive_pid"
LAST_PF_RESTART_FILE="$WORK/last_pf_restart"
S6_EXITCODE_FILE="$WORK/run/s6-linux-init-container-results/exitcode"
S6_HALT="$WORK/halt"
VPN_SETUP_SCRIPT="$WORK/setup"
PIA_PF_SCRIPT="$WORK/pf.sh"
MAX_RESTARTS_EXIT_CODE=1
MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS:-3}
RESTART_COOLDOWN_SECONDS=300
PF_RESTART_COOLDOWN_SECONDS=900
AUTO_RESTART_VPN=${AUTO_RESTART_VPN:-true}
EXIT_ON_MAX_RESTARTS=${EXIT_ON_MAX_RESTARTS:-true}
PIA_PORT_FORWARD=${PIA_PORT_FORWARD:-false}
NOTIFICATION_WEBHOOK_URL=""
VPN_CLIENT=openvpn
VPN_CONFIG="$WORK/does-not-exist.ovpn"
VPN_INTERFACE=tun0
FAILURE_COUNT=${FAILURE_COUNT:-0}

ip() {
    local dev="$3"
    case "$1 $2" in
        "link show") case " $UP_IFS " in *" $dev "*) echo "5: $dev: <UP> mtu 1500 state UNKNOWN";; *) return 1;; esac ;;
        "addr show") case " $IP_IFS " in *" $dev "*) echo "    inet 10.25.18.69/24 scope global $dev";; esac ;;
    esac
}
ping() {
    local host="${!#}"
    echo "$host" >> "$WORK/pinged"
    case " $ANSWERING " in *" $host "*) return 0;; esac
    return 1
}
kill() {
    if [ "$1" = "-0" ]; then
        case " $ALIVE_PIDS " in *" $2 "*) return 0;; esac
        return 1
    fi
    echo "$*" >> "$WORK/killed"
}
pgrep() { [ -n "$PGREP_OUT" ] && echo "$PGREP_OUT"; return 0; }
# Like procps: without -f, the pattern is matched against the kernel process name,
# which is cut to 15 characters, so only "transmission-da" can match the daemon.
procps_name_ok() {
    local arg pat="" full=false
    for arg in "$@"; do
        case "$arg" in -f) full=true ;; -*) ;; *) pat="$arg" ;; esac
    done
    $full && return 0
    [ "${#pat}" -le 15 ] && [[ "transmission-da" =~ $pat ]]
}
sleep() { :; }
pkill() { :; }
iptables() { :; }
curl() { :; }
EOF

# The process name the monitor looks for, taken from the shipped script.
grep '^TRANSMISSION_PROC=' "$MONITOR" >> "$WORK/harness.sh"

run_case() {
    # run_case <shell snippet> - runs it with the harness, probe lib and extracted functions
    "$BASH" -c "
        source '$WORK/harness.sh'
        source '$PROBE_LIB'
        source '$WORK/functions.sh'
        wait_for_shutdown() { echo WAITING_FOR_SHUTDOWN; exit 0; }
        $1
    " 2>&1 || echo "EXITED=$?"
}

reset_work() {
    rm -rf "$WORK/run" "$WORK"/restart_count "$WORK"/last_restart "$WORK"/vpn_tunnel_state \
           "$WORK"/halted "$WORK"/pinged "$WORK"/killed "$WORK"/pf_runs \
           "$WORK"/pia_keepalive_pid "$WORK"/last_pf_restart "$WORK"/restart.log
}

state_value() { grep "^$1=" "$WORK/vpn_tunnel_state" 2>/dev/null | cut -d= -f2; }

echo "1. Interface up with an address, but traffic dropped (iptables -I OUTPUT -o tun0 -j DROP)..."
reset_work
out=$(UP_IFS=tun0 IP_IFS=tun0 ANSWERING="" run_case '
    if check_tunnel tun0; then echo TUNNEL=ok; else echo "TUNNEL=fail $TUNNEL_FAILURE"; fi
    publish_tunnel_state 0')
expect_match "$out" "TUNNEL=fail no reply through tun0 from 1.1.1.1 or 9.9.9.9" "check_tunnel fails and says why"
if [ "$(state_value connected)" = "0" ]; then
    log_pass "Publishes connected=0"
else
    log_fail "Published connected=$(state_value connected), expected 0"
fi
if grep -qx 9.9.9.9 "$WORK/pinged" 2>/dev/null; then
    log_pass "Tried the fallback before declaring failure"
else
    log_fail "Fallback host was not probed"
fi
echo ""

echo "2. Probe matches healthcheck.sh: fallback answering is enough..."
reset_work
out=$(UP_IFS=tun0 IP_IFS=tun0 ANSWERING="9.9.9.9" run_case '
    if check_tunnel tun0; then echo TUNNEL=ok; else echo "TUNNEL=fail $TUNNEL_FAILURE"; fi')
expect_match "$out" "TUNNEL=ok" "Passes when only the fallback answers (ICMP rate-limited primary)"
echo ""

echo "3. Interface missing or without an address..."
reset_work
out=$(UP_IFS="" IP_IFS="" ANSWERING="1.1.1.1" run_case '
    if check_tunnel tun0; then echo TUNNEL=ok; else echo "TUNNEL=fail $TUNNEL_FAILURE"; fi')
expect_match "$out" "TUNNEL=fail interface tun0 is not UP" "Down interface fails"
out=$(UP_IFS=tun0 IP_IFS="" ANSWERING="1.1.1.1" run_case '
    if check_tunnel tun0; then echo TUNNEL=ok; else echo "TUNNEL=fail $TUNNEL_FAILURE"; fi')
expect_match "$out" "TUNNEL=fail interface tun0 has no IP address" "Interface without an address fails"
echo ""

echo "4. Max restart attempts reached - the container exits..."
reset_work
echo 3 > "$WORK/restart_count"
out=$(UP_IFS=tun0 IP_IFS=tun0 ANSWERING="" run_case 'attempt_vpn_restart; echo RETURNED=$?')
if [ -f "$WORK/halted" ]; then
    log_pass "Calls s6 halt"
else
    log_fail "s6 halt was not called. Output: $out"
fi
if [ "$(cat "$WORK/run/s6-linux-init-container-results/exitcode" 2>/dev/null)" = "1" ]; then
    log_pass "Writes exit code 1 for the container"
else
    log_fail "Container exit code not written"
fi
expect_match "$out" "WAITING_FOR_SHUTDOWN" "Waits for shutdown instead of returning into the loop"
expect_no_match "$out" "RETURNED=" "Does not return to the monitor loop"
expect_match "$out" "Stopping the container" "Says it is stopping the container"
if [ "$(state_value connected)" = "0" ]; then
    log_pass "Leaves connected=0 published on the way out"
else
    log_fail "Tunnel state not published before exit"
fi
echo ""

echo "5. EXIT_ON_MAX_RESTARTS=false keeps the old behaviour..."
reset_work
echo 3 > "$WORK/restart_count"
out=$(EXIT_ON_MAX_RESTARTS=false UP_IFS=tun0 IP_IFS=tun0 ANSWERING="" run_case 'attempt_vpn_restart || echo RETURNED=$?')
if [ ! -f "$WORK/halted" ]; then
    log_pass "Does not halt"
else
    log_fail "Halted despite EXIT_ON_MAX_RESTARTS=false"
fi
expect_match "$out" "RETURNED=1" "Returns failure to the loop"
expect_match "$out" "manual intervention required" "Logs that a human is needed"
echo ""

echo "6. Below the limit - restarts instead of exiting..."
reset_work
echo 1 > "$WORK/restart_count"
out=$(UP_IFS=tun0 IP_IFS=tun0 ANSWERING="1.1.1.1" run_case 'attempt_vpn_restart && echo RESTART=ok')
expect_match "$out" "RESTART=ok" "Restart succeeds when traffic passes afterwards"
if [ ! -f "$WORK/halted" ] && [ "$(cat "$WORK/restart_count")" = "2" ]; then
    log_pass "Counts the attempt (2/3) and does not halt"
else
    log_fail "Unexpected halt or count $(cat "$WORK/restart_count")"
fi
echo ""

echo "7. A restart that brings back a dead tunnel is not a success..."
reset_work
echo 0 > "$WORK/restart_count"
out=$(UP_IFS=tun0 IP_IFS=tun0 ANSWERING="" run_case 'attempt_vpn_restart && echo RESTART=ok || echo RESTART=failed')
expect_match "$out" "RESTART=failed" "Interface up with an address after restart is not enough"
expect_match "$out" "tunnel is not usable: no reply" "Logs the reason"
echo ""

echo "8. Port forwarding is restarted after a successful VPN restart..."
reset_work
echo 0 > "$WORK/restart_count"
echo 4242 > "$WORK/pia_keepalive_pid"
out=$(PIA_PORT_FORWARD=true ALIVE_PIDS=4242 UP_IFS=tun0 IP_IFS=tun0 ANSWERING="1.1.1.1" run_case 'attempt_vpn_restart; wait')
if grep -qx 4242 "$WORK/killed" 2>/dev/null; then
    log_pass "Kills the keepalive bound to the old session"
else
    log_fail "Old keepalive was not killed"
fi
if [ "$(wc -l < "$WORK/pf_runs" 2>/dev/null)" -eq 1 ] 2>/dev/null; then
    log_pass "Runs pia-port-forward.sh again"
else
    log_fail "pia-port-forward.sh was not re-run. Output: $out"
fi
reset_work
echo 0 > "$WORK/restart_count"
out=$(PIA_PORT_FORWARD=false UP_IFS=tun0 IP_IFS=tun0 ANSWERING="1.1.1.1" run_case 'attempt_vpn_restart; wait')
if [ ! -f "$WORK/pf_runs" ]; then
    log_pass "Leaves port forwarding alone when PIA_PORT_FORWARD is off"
else
    log_fail "Ran pia-port-forward.sh with PIA_PORT_FORWARD=false"
fi
echo ""

echo "9. A dead keepalive is noticed while the tunnel is healthy..."
reset_work
echo 4242 > "$WORK/pia_keepalive_pid"
PIA_PORT_FORWARD=true ALIVE_PIDS="" run_case 'ensure_port_forwarding; wait' >/dev/null
if [ -f "$WORK/pf_runs" ]; then
    log_pass "Restarts port forwarding when the keepalive has exited"
else
    log_fail "Dead keepalive was not restarted"
fi

reset_work
echo 4242 > "$WORK/pia_keepalive_pid"
PIA_PORT_FORWARD=true ALIVE_PIDS="4242" run_case 'ensure_port_forwarding; wait' >/dev/null
if [ ! -f "$WORK/pf_runs" ]; then
    log_pass "Leaves a live keepalive alone"
else
    log_fail "Restarted port forwarding with a live keepalive"
fi

reset_work
PIA_PORT_FORWARD=true ALIVE_PIDS="" PGREP_OUT="777" run_case 'ensure_port_forwarding; wait' >/dev/null
if [ ! -f "$WORK/pf_runs" ]; then
    log_pass "Does not start a second run while one is in progress"
else
    log_fail "Started a concurrent pia-port-forward.sh"
fi

reset_work
date +%s > "$WORK/last_pf_restart"
PIA_PORT_FORWARD=true ALIVE_PIDS="" run_case 'ensure_port_forwarding; wait' >/dev/null
if [ ! -f "$WORK/pf_runs" ]; then
    log_pass "Respects the cooldown after a recent restart"
else
    log_fail "Ignored PF_RESTART_COOLDOWN_SECONDS"
fi
echo ""

echo "10. stop_transmission actually stops Transmission under s6-overlay v3..."
# The v2 path /var/run/s6/services/transmission does not exist on v3, so s6-svc used
# to fail silently and Transmission kept running through every VPN restart.
expect_match "$(grep '^TRANSMISSION_SERVICE_DIRS=' "$MONITOR")" '"/run/service/svc-transmission ' \
    "Looks for the s6-overlay v3 service directory first"
reset_work
rm -rf "$WORK/svc" "$WORK/s6" "$WORK/daemon_down"
mkdir -p "$WORK/svc/svc-transmission/supervise"
out=$(run_case '
    TRANSMISSION_SERVICE_DIRS="$WORK/svc/svc-transmission $WORK/svc/legacy"
    VPN_STATUS_FILE="$WORK/vpn_status"
    s6-svc() { echo "s6-svc $*" >> "$WORK/s6"; case " $* " in *" -d "*) touch "$WORK/daemon_down";; *" -u "*) rm -f "$WORK/daemon_down";; esac; }
    pgrep() { procps_name_ok "$@" || return 1; [ -f "$WORK/daemon_down" ] && return 1; echo 123; }
    pkill() { procps_name_ok "$@" && echo "pkill $*" >> "$WORK/s6"; }
    stop_transmission
    [ -f "$WORK/daemon_down" ] && echo STOPPED
    restart_transmission
    [ -f "$WORK/daemon_down" ] || echo STARTED')
expect_match "$(cat "$WORK/s6" 2>/dev/null)" "s6-svc -wD -T 15000 -d $WORK/svc/svc-transmission" "Takes the v3 service down through s6 and waits"
expect_match "$out" "STOPPED" "Transmission is stopped"
expect_no_match "$(cat "$WORK/s6" 2>/dev/null)" "pkill" "No pkill needed when s6 stops it"
expect_match "$(cat "$WORK/s6" 2>/dev/null)" "s6-svc -u $WORK/svc/svc-transmission" "Brings the same service back up"
expect_match "$out" "STARTED" "Transmission is started again"

rm -rf "$WORK/svc" "$WORK/s6" "$WORK/daemon_down"
out=$(run_case '
    TRANSMISSION_SERVICE_DIRS="$WORK/svc/none"
    VPN_STATUS_FILE="$WORK/vpn_status"
    s6-svc() { echo "s6-svc $*" >> "$WORK/s6"; }
    pgrep() { procps_name_ok "$@" || return 1; [ -f "$WORK/daemon_down" ] && return 1; echo 123; }
    pkill() { procps_name_ok "$@" || return 1; echo "pkill $*" >> "$WORK/s6"; touch "$WORK/daemon_down"; }
    stop_transmission')
expect_no_match "$(cat "$WORK/s6" 2>/dev/null)" "s6-svc" "No s6-svc call against a service directory that does not exist"
expect_match "$(cat "$WORK/s6" 2>/dev/null)" "pkill -TERM -x transmission-da" "Falls back to killing the daemon"
echo ""

echo "11. Transmission is started again as soon as a VPN restart is verified..."
# It used to wait for the next health check, and only fired when FAILURE_COUNT > 0,
# which a successful restart had just reset to 0: Transmission stayed stopped until
# the liveness probe restarted the whole container.
reset_work
rm -rf "$WORK/svc" "$WORK/order" "$WORK/daemon_down"
mkdir -p "$WORK/svc/svc-transmission/supervise"
echo 0 > "$WORK/restart_count"
out=$(PIA_PORT_FORWARD=true UP_IFS=tun0 IP_IFS=tun0 ANSWERING="1.1.1.1" run_case '
    TRANSMISSION_SERVICE_DIRS="$WORK/svc/svc-transmission"
    VPN_STATUS_FILE="$WORK/vpn_status"
    s6-svc() { echo "s6-svc $*" >> "$WORK/order"; case " $* " in *" -d "*) touch "$WORK/daemon_down";; *" -u "*) rm -f "$WORK/daemon_down";; esac; }
    pgrep() { procps_name_ok "$@" || return 1; [ -f "$WORK/daemon_down" ] && return 1; echo 123; }
    stop_transmission
    attempt_vpn_restart; wait
    [ -f "$WORK/daemon_down" ] && echo STILL_DOWN || echo BACK_UP')
expect_match "$out" "BACK_UP" "Transmission is running again when attempt_vpn_restart returns"
expect_match "$(tr '\n' ' ' < "$WORK/order" 2>/dev/null)" "s6-svc -u .* pf" "Started before port forwarding, which waits for its RPC"

reset_work
rm -rf "$WORK/order" "$WORK/daemon_down"
echo 0 > "$WORK/restart_count"
out=$(UP_IFS=tun0 IP_IFS=tun0 ANSWERING="" run_case '
    TRANSMISSION_SERVICE_DIRS="$WORK/svc/svc-transmission"
    VPN_STATUS_FILE="$WORK/vpn_status"
    s6-svc() { echo "s6-svc $*" >> "$WORK/order"; case " $* " in *" -d "*) touch "$WORK/daemon_down";; *" -u "*) rm -f "$WORK/daemon_down";; esac; }
    pgrep() { procps_name_ok "$@" || return 1; [ -f "$WORK/daemon_down" ] && return 1; echo 123; }
    stop_transmission
    attempt_vpn_restart || true
    [ -f "$WORK/daemon_down" ] && echo STILL_DOWN || echo BACK_UP')
expect_match "$out" "STILL_DOWN" "A restart into a dead tunnel leaves Transmission stopped"

if grep -q 'if \[ \$FAILURE_COUNT -gt 0 \]; then' "$MONITOR" && \
   ! awk '/if \[ \$FAILURE_COUNT -gt 0 \]; then/ { inside = 1; next } inside && /^        fi$/ { exit } inside' "$MONITOR" | grep -q restart_transmission; then
    log_pass "The healthy branch no longer ties restart_transmission to FAILURE_COUNT"
else
    log_fail "restart_transmission is still only called when FAILURE_COUNT > 0"
fi
echo ""

echo "================================================"
if [ "$FAILED" = "true" ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

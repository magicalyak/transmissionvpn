#!/bin/bash
# Tests for vpn-monitor's wait_for_vpn_setup().
#
# The function is extracted from the shipped root_s6/vpn-monitor/run rather than copied,
# so this test cannot drift from it. `sleep` is shadowed by a stub, so the loop runs at
# full speed and no real time passes.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR="$SCRIPT_DIR/root_s6/vpn-monitor/run"

echo "================================================"
echo "   vpn-monitor initial-wait tests"
echo "================================================"
echo ""

if [ ! -f "$MONITOR" ]; then
    log_fail "Cannot find $MONITOR"
    exit 1
fi

WORK="$(mktemp -d)"
export WORK
trap 'rm -rf "$WORK"' EXIT

awk '/^wait_for_vpn_setup\(\) \{/,/^\}/' "$MONITOR" > "$WORK/fn_wait.sh"
if [ ! -s "$WORK/fn_wait.sh" ]; then
    log_fail "Could not extract wait_for_vpn_setup() from $MONITOR"
    exit 1
fi

# $1 = seconds of simulated waiting before the setup flag appears
# $2 = contents for the vpn-setup log, or the literal string NOLOG to leave it absent
run_wait() {
    local appear_after="$1" setup_log_content="$2"
    # The single-quoted lines below are written verbatim into the harness; their
    # expansions must happen when the harness runs, not while it is being written.
    # shellcheck disable=SC2016
    {
        echo '#!/bin/bash'
        echo 'set -e'
        echo 'log() { echo "[VPN-MONITOR] $*"; }'
        echo 'VPN_SETUP_COMPLETE="$WORK/flag"'
        echo 'VPN_SETUP_LOG="$WORK/vpn-setup.log"'
        echo 'VPN_SETUP_WAIT_WARN_SECONDS=150'
        # Shadow sleep: no real delay, and drop the flag once enough simulated time passes.
        echo 'SLEPT=0'
        echo 'sleep() { SLEPT=$((SLEPT + $1)); [ "$SLEPT" -ge "$APPEAR_AFTER" ] && touch "$VPN_SETUP_COMPLETE"; return 0; }'
        cat "$WORK/fn_wait.sh"
        echo 'wait_for_vpn_setup'
    } > "$WORK/harness.sh"
    chmod +x "$WORK/harness.sh"

    rm -f "$WORK/flag" "$WORK/vpn-setup.log"
    if [ "$setup_log_content" != "NOLOG" ]; then
        printf '%s\n' "$setup_log_content" > "$WORK/vpn-setup.log"
    fi
    APPEAR_AFTER="$appear_after" bash "$WORK/harness.sh"
}

echo "1. Flag already present - returns without waiting..."
rm -f "$WORK/flag"; touch "$WORK/flag"
OUT="$(APPEAR_AFTER=0 bash -c '
    set -e
    log() { echo "[VPN-MONITOR] $*"; }
    VPN_SETUP_COMPLETE="$WORK/flag"; VPN_SETUP_LOG="$WORK/nope.log"; VPN_SETUP_WAIT_WARN_SECONDS=150
    sleep() { echo "UNEXPECTED SLEEP"; }
    '"$(cat "$WORK/fn_wait.sh")"'
    wait_for_vpn_setup')"
if [ -z "$OUT" ]; then
    log_pass "No output and no sleep when setup is already complete"
else
    log_fail "Expected silence, got: $OUT"
fi

echo ""
echo "2. Setup completes before the warning threshold..."
OUT="$(run_wait 30 "[INFO] fine")"
if ! echo "$OUT" | grep -q "WARNING"; then
    log_pass "No warning for a normal startup"
else
    log_fail "Warned during a startup that completed in 30s"
fi
if [ "$(echo "$OUT" | grep -c "Waiting for initial VPN setup to complete")" -eq 6 ]; then
    log_pass "Polled every 5s up to completion (6 messages over 30s)"
else
    log_fail "Unexpected poll count: $(echo "$OUT" | grep -c "Waiting for initial VPN setup")"
fi

echo ""
echo "3. Setup overruns - warns, shows the log, and backs off..."
OUT="$(run_wait 400 "[INFO] Setting up OpenVPN...
[ERROR] Specified VPN_CONFIG=/config/openvpn/ca_toronto.ovpn not found inside the container.")"

if echo "$OUT" | grep -q "WARNING: VPN setup has not completed after 150s"; then
    log_pass "Warns once the threshold is passed"
else
    log_fail "No warning after the threshold"
fi
if echo "$OUT" | grep -q "ca_toronto.ovpn not found"; then
    log_pass "Surfaces the actual error from the vpn-setup log"
else
    log_fail "vpn-setup log contents not shown"
fi
if echo "$OUT" | grep -q "No traffic leaves this container"; then
    log_pass "States that the container is fail-closed"
else
    log_fail "No mention of the fail-closed state"
fi
if [ "$(echo "$OUT" | grep -c "WARNING: VPN setup has not completed")" -eq 1 ]; then
    log_pass "Warns exactly once, not on every iteration"
else
    log_fail "Warning repeated $(echo "$OUT" | grep -c "WARNING: VPN setup has not completed") times"
fi
# 0-150s at 5s = 30 chatty lines; 150-400s at 60s = far fewer. Without the backoff
# the same span would produce 80.
CHATTY="$(echo "$OUT" | grep -c "Waiting for initial VPN setup to complete")"
BACKED_OFF="$(echo "$OUT" | grep -c "Still waiting for VPN setup")"
if [ "$CHATTY" -eq 30 ] && [ "$BACKED_OFF" -le 6 ]; then
    log_pass "Backed off after warning ($CHATTY fast polls, then $BACKED_OFF slow ones)"
else
    log_fail "Backoff wrong: $CHATTY fast, $BACKED_OFF slow"
fi

echo ""
echo "4. vpn-setup log missing entirely..."
OUT="$(run_wait 400 NOLOG)"
if echo "$OUT" | grep -q "does not exist - vpn-setup.sh has not started"; then
    log_pass "Says the log is absent rather than showing nothing"
else
    log_fail "Missing vpn-setup log not reported"
fi

echo ""
echo "================================================"
if [ "$FAILED" = "true" ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

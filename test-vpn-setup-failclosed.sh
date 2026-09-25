#!/bin/bash
# Tests for vpn-setup.sh's failure handling:
#   - fail_closed_on_abort()      locks the firewall down when setup aborts
#   - report_missing_vpn_config() explains a VPN config the container cannot see
#
# Both functions are extracted from the shipped root/vpn-setup.sh rather than copied,
# so this test cannot drift from the code it is checking. iptables/ip6tables are stubbed,
# so no container, no privileges and no network are required.

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
echo "   vpn-setup.sh failure-handling tests"
echo "================================================"
echo ""

if [ ! -f "$VPN_SETUP" ]; then
    log_fail "Cannot find $VPN_SETUP"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Extract the functions under test verbatim.
awk '/^report_missing_vpn_config\(\) \{/,/^\}/' "$VPN_SETUP" > "$WORK/fn_report.sh"
awk '/^fail_closed_on_abort\(\) \{/,/^\}/'      "$VPN_SETUP" > "$WORK/fn_failclosed.sh"

if [ ! -s "$WORK/fn_report.sh" ] || [ ! -s "$WORK/fn_failclosed.sh" ]; then
    log_fail "Could not extract the functions under test from vpn-setup.sh"
    exit 1
fi

# Operate on a throwaway completion flag rather than the real /tmp/vpn_setup_complete,
# so running this inside a container cannot disturb a live setup.
FLAG="$WORK/vpn_setup_complete"
sed "s#rm -f /tmp/vpn_setup_complete#rm -f $FLAG#" "$WORK/fn_failclosed.sh" > "$WORK/fn_failclosed_test.sh"

# Stub iptables/ip6tables so invocations are recorded instead of applied.
mkdir -p "$WORK/bin"
for tool in iptables ip6tables; do
    # shellcheck disable=SC2016  # $* and $FW_LOG must stay literal: they are expanded
    # when the generated stub runs, not while it is being written.
    printf '#!/bin/bash\necho "%s $*" >> "$FW_LOG"\n' "$tool" > "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done
export PATH="$WORK/bin:$PATH"

make_harness() {
    # $1 = output path, $2 = final command (determines exit status)
    {
        echo '#!/bin/bash'
        echo 'set -e'
        cat "$WORK/fn_failclosed_test.sh"
        echo 'trap fail_closed_on_abort EXIT'
        echo "$2"
    } > "$1"
    chmod +x "$1"
}

echo "1. Abort path locks the firewall down..."
export FW_LOG="$WORK/fw_abort.log"
: > "$FW_LOG"
touch "$FLAG"
make_harness "$WORK/abort.sh" 'exit 7'
set +e
"$WORK/abort.sh" > "$WORK/abort.out" 2>&1
ABORT_RC=$?
set -e

if [ "$ABORT_RC" -eq 7 ]; then
    log_pass "Original exit code preserved through the trap ($ABORT_RC)"
else
    log_fail "Exit code was $ABORT_RC, expected 7 - the trap is swallowing the failure"
fi

for rule in "iptables -P INPUT DROP" "iptables -P OUTPUT DROP" "iptables -P FORWARD DROP" \
            "iptables -A INPUT -i lo -j ACCEPT" "iptables -A OUTPUT -o lo -j ACCEPT" \
            "iptables -A OUTPUT -o lo -d 127.0.0.11 -j DROP" \
            "ip6tables -P OUTPUT DROP"; do
    if grep -qxF "$rule" "$FW_LOG"; then
        log_pass "Applied: $rule"
    else
        log_fail "Missing: $rule"
    fi
done

if grep -q "OUTPUT ACCEPT" "$FW_LOG"; then
    log_fail "Abort path left an ACCEPT policy in place"
else
    log_pass "No ACCEPT policy left behind on the abort path"
fi

if [ -f "$FLAG" ]; then
    log_fail "Stale completion flag survived the abort"
else
    log_pass "Stale completion flag removed on abort"
fi

if grep -q "Locking the firewall down" "$WORK/abort.out"; then
    log_pass "Abort reason reported to the operator"
else
    log_fail "Abort produced no explanation"
fi

echo ""
echo "2. Success path leaves the firewall alone..."
export FW_LOG="$WORK/fw_ok.log"
: > "$FW_LOG"
touch "$FLAG"
make_harness "$WORK/ok.sh" 'echo "[INFO] setup complete"'
set +e
"$WORK/ok.sh" > /dev/null 2>&1
OK_RC=$?
set -e

if [ "$OK_RC" -eq 0 ]; then
    log_pass "Success path exits 0"
else
    log_fail "Success path exited $OK_RC"
fi

if [ ! -s "$FW_LOG" ]; then
    log_pass "No firewall changes on the success path"
else
    log_fail "Success path touched the firewall: $(tr '\n' ';' < "$FW_LOG")"
fi

if [ -f "$FLAG" ]; then
    log_pass "Completion flag left intact on success"
else
    log_fail "Success path removed the completion flag"
fi

echo ""
echo "3. Missing VPN config is explained..."
# shellcheck source=/dev/null
. "$WORK/fn_report.sh"
mkdir -p "$WORK/emptyconfig"
REPORT="$(report_missing_vpn_config "$WORK/emptyconfig" 2>&1)"

if echo "$REPORT" | grep -q "as this container sees it"; then
    log_pass "Reports what the container can see"
else
    log_fail "No directory listing in the report"
fi

if echo "$REPORT" | grep -q "bound to a different host directory"; then
    log_pass "Names the bind mount as the likely cause"
else
    log_fail "Report does not mention the bind mount"
fi

if echo "$REPORT" | grep -q "docker inspect"; then
    log_pass "Gives a command to compare the mounts"
else
    log_fail "Report offers no way to check the mounts"
fi

MISSING_REPORT="$(report_missing_vpn_config "$WORK/does-not-exist" 2>&1)"
if echo "$MISSING_REPORT" | grep -q "no such directory"; then
    log_pass "Handles a directory that does not exist at all"
else
    log_fail "Nonexistent directory not reported cleanly"
fi

echo ""
echo "================================================"
if [ "$FAILED" = "true" ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

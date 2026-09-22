#!/bin/bash
# Tests for healthcheck.sh's probe-target handling.
#
# Two defects are covered here. check_dns() used HEALTH_CHECK_HOST, which defaults to an
# IP address, and `getent hosts` returns success for a literal address without asking a
# resolver - so the DNS check passed unconditionally, including with DNS completely dead.
# And a private HEALTH_CHECK_HOST cannot be reached through the tunnel at all, so it
# guaranteed a connectivity failure that was really a misconfiguration.
#
# The functions are extracted from the shipped root/healthcheck.sh rather than copied, so
# this test cannot drift from it. getent and the logger are stubbed, so nothing resolves
# and no network is touched.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTHCHECK="$SCRIPT_DIR/root/healthcheck.sh"

echo "================================================"
echo "   healthcheck probe-target tests"
echo "================================================"
echo ""

if [ ! -f "$HEALTHCHECK" ]; then
    log_fail "Cannot find $HEALTHCHECK"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Pull the three functions under test out of the shipped script.
for fn in is_ip_address override_lan_probe_target check_dns; do
    awk -v fn="$fn" '
        $0 ~ "^"fn"\\(\\) \\{" { inside = 1 }
        inside { print }
        inside && /^\}/ { exit }
    ' "$HEALTHCHECK" > "$WORK/$fn.sh"
    if [ ! -s "$WORK/$fn.sh" ]; then
        log_fail "Could not extract $fn() from healthcheck.sh"
        exit 1
    fi
done

# Harness: stubs for everything the extracted functions touch.
cat > "$WORK/harness.sh" <<'EOF'
LOG_OUT=""
log() { LOG_OUT="$LOG_OUT[$1] $2
"; }
record_metric() { :; }
# getent succeeds only for names listed in RESOLVABLE. A literal IP is never
# listed, so any success for one would have to come from the code under test.
getent() {
    case " $RESOLVABLE " in
        *" $2 "*) echo "192.0.2.1 $2"; return 0 ;;
    esac
    return 2
}
EOF

run_case() {
    # run_case <fn> <env assignments...>
    local fn="$1"; shift
    env "$@" bash -c "
        source '$WORK/harness.sh'
        source '$WORK/is_ip_address.sh'
        source '$WORK/$fn.sh'
        $fn
        rc=\$?
        printf 'RC=%s\nHOST=%s\n' \"\$rc\" \"\$HEALTH_CHECK_HOST\"
        printf '%s' \"\$LOG_OUT\"
    " 2>&1
}

echo "1. is_ip_address distinguishes addresses from names..."
ip_check() {
    bash -c "source '$WORK/is_ip_address.sh'; if is_ip_address '$1'; then echo yes; else echo no; fi"
}
[ "$(ip_check 1.1.1.1)" = "yes" ] && log_pass "1.1.1.1 is an address" || log_fail "1.1.1.1 should be an address"
[ "$(ip_check 9.9.9.9)" = "yes" ] && log_pass "9.9.9.9 is an address" || log_fail "9.9.9.9 should be an address"
[ "$(ip_check 2606:4700:4700::1111)" = "yes" ] && log_pass "IPv6 literal is an address" || log_fail "IPv6 should be an address"
[ "$(ip_check one.one.one.one)" = "no" ] && log_pass "one.one.one.one is a name" || log_fail "one.one.one.one should be a name"
[ "$(ip_check google.com)" = "no" ] && log_pass "google.com is a name" || log_fail "google.com should be a name"
echo ""

echo "2. check_dns no longer passes on an address it cannot resolve..."
out=$(run_case check_dns DNS_CHECK_HOST=1.1.1.1 RESOLVABLE="")
echo "$out" | grep -q "^RC=0" \
    && log_pass "Does not fail the container over an unusable setting" \
    || log_fail "Expected rc 0, got: $out"
echo "$out" | grep -q "WARN.*cannot test resolution" \
    && log_pass "Says the check cannot test resolution" \
    || log_fail "Expected a WARN about an IP target, got: $out"
echo "$out" | grep -q "is working" \
    && log_fail "Must not claim DNS is working when nothing was resolved" \
    || log_pass "Does not claim a success it never tested"
echo ""

echo "3. check_dns actually resolves a name..."
out=$(run_case check_dns DNS_CHECK_HOST=one.one.one.one RESOLVABLE="one.one.one.one")
echo "$out" | grep -q "^RC=0" && log_pass "Succeeds when the name resolves" || log_fail "Expected rc 0, got: $out"
echo "$out" | grep -q "is working" && log_pass "Reports the working resolution" || log_fail "Expected a success log, got: $out"

out=$(run_case check_dns DNS_CHECK_HOST=one.one.one.one RESOLVABLE="")
echo "$out" | grep -q "^RC=1" && log_pass "Fails when the name does not resolve" || log_fail "Expected rc 1, got: $out"
echo "$out" | grep -q "ERROR" && log_pass "Reports the failure" || log_fail "Expected an ERROR log, got: $out"
echo ""

echo "4. check_dns can be disabled..."
out=$(run_case check_dns DNS_CHECK_HOST= RESOLVABLE="")
echo "$out" | grep -q "^RC=0" && log_pass "Empty DNS_CHECK_HOST skips the check" || log_fail "Expected rc 0, got: $out"
echo "$out" | grep -q "WARN" \
    && log_fail "Disabling it deliberately should not warn" \
    || log_pass "No warning when deliberately disabled"
echo ""

echo "5. A private probe target is replaced, loudly..."
for lan in 10.0.0.1 192.168.1.1 172.16.5.4 172.31.255.1 127.0.0.1 169.254.1.1; do
    out=$(run_case override_lan_probe_target HEALTH_CHECK_HOST="$lan")
    if echo "$out" | grep -q "^HOST=1.1.1.1" && echo "$out" | grep -q "WARN"; then
        log_pass "$lan replaced with a warning"
    else
        log_fail "$lan should have been replaced with a warning, got: $out"
    fi
done
echo ""

echo "6. A public probe target is left alone..."
for pub in 1.1.1.1 9.9.9.9 8.8.8.8 172.15.0.1 172.32.0.1 example.com; do
    out=$(run_case override_lan_probe_target HEALTH_CHECK_HOST="$pub")
    if echo "$out" | grep -q "^HOST=$pub" && ! echo "$out" | grep -q "WARN"; then
        log_pass "$pub left untouched"
    else
        log_fail "$pub should have been left untouched, got: $out"
    fi
done
echo ""

echo "================================================"
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

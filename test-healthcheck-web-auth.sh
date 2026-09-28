#!/bin/bash
# Variables set in this file are read by the functions eval'd from healthcheck.sh.
# shellcheck disable=SC2034
# Tests for the credentials healthcheck.sh sends to Transmission.
#
# With rpc-authentication-required on, the web UI answers 401 to an anonymous request,
# and check_transmission() used a bare `curl -f` on it, so the HEALTHCHECK marked a
# container with auth enabled unhealthy while the daemon was fine.
#
# The functions are extracted from the shipped root/healthcheck.sh rather than copied,
# so this test cannot drift from it. curl and transmission-remote are stubbed to record
# how they were called; nothing touches the network.

set -e

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
        log_fail "$3 - expected [$2], got [$1]"
    fi
}

HC="$(dirname "$0")/root/healthcheck.sh"
eval "$(sed -n '/^rpc_user()/p; /^rpc_pass()/p; /^curl_web_ui() {/,/^}/p; /^tr_remote() {/,/^}/p' "$HC")"

# Stubs: record argv and stdin, then fail unless credentials arrived on stdin.
CALLS=$(mktemp)
trap 'rm -f "$CALLS"' EXIT
curl() {
    local stdin=""
    if [[ " $* " == *" -K - "* ]]; then stdin=$(cat); fi
    printf 'argv=%s\nstdin=%s\n' "$*" "$stdin" > "$CALLS"
    [[ -n "$stdin" ]]
}
transmission-remote() { printf 'argv=%s\nTR_AUTH=%s\n' "$*" "${TR_AUTH:-}" > "$CALLS"; }

reset_env() { unset TRANSMISSION_RPC_USERNAME TRANSMISSION_RPC_PASSWORD USER PASS; }

echo "credential sources"
reset_env; USER=tom; PASS=pw
expect_eq "$(rpc_user):$(rpc_pass)" "tom:pw" "falls back to USER/PASS"
reset_env; USER=root
expect_eq "$(rpc_user):$(rpc_pass)" ":" "USER alone is not a credential"
reset_env; TRANSMISSION_RPC_USERNAME=a; TRANSMISSION_RPC_PASSWORD=b; USER=c; PASS=d
expect_eq "$(rpc_user):$(rpc_pass)" "a:b" "TRANSMISSION_RPC_* wins over USER/PASS"

echo "web UI check"
reset_env; USER=tom; PASS=pw
if curl_web_ui; then log_pass "authenticated check succeeds"; else log_fail "authenticated check failed"; fi
expect_eq "$(sed -n 's/^stdin=//p' "$CALLS")" 'user = "tom:pw"' "credentials sent on stdin"
case "$(sed -n 's/^argv=//p' "$CALLS")" in
    *pw*) log_fail "password leaked into curl argv" ;;
    *) log_pass "password not in curl argv" ;;
esac

reset_env; USER=tom; PASS='p"a\ss'
curl_web_ui || true
expect_eq "$(sed -n 's/^stdin=//p' "$CALLS")" 'user = "tom:p\"a\\ss"' "quote and backslash escaped for curl config"

reset_env
if curl_web_ui; then log_fail "anonymous check should not send credentials"; else log_pass "no credentials -> anonymous request"; fi

echo "transmission-remote"
reset_env; USER=tom; PASS=pw
tr_remote -si
expect_eq "$(sed -n 's/^TR_AUTH=//p' "$CALLS")" "tom:pw" "credentials passed via TR_AUTH"
expect_eq "$(sed -n 's/^argv=//p' "$CALLS")" "localhost:9091 -ne -si" "uses -ne, no password in argv"
reset_env
tr_remote -si
expect_eq "$(sed -n 's/^argv=//p' "$CALLS")" "localhost:9091 -si" "no credentials -> plain call"

if [ "$FAILED" = true ]; then
    echo -e "${RED}FAILED${NC}"
    exit 1
fi
echo -e "${GREEN}All healthcheck web auth tests passed${NC}"

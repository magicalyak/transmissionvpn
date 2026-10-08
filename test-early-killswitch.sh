#!/bin/bash
# Tests for root/early-killswitch.sh, the entrypoint that locks the firewall
# before s6-overlay's /init runs anything. early_lock() is extracted from the
# shipped script, so this test cannot drift from it. iptables and ip6tables are
# stubbed with a small model of the filter table, so no container, privileges
# or network are needed.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; FAILED=true; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EARLY="$SCRIPT_DIR/root/early-killswitch.sh"
PROVIDER="$SCRIPT_DIR/root/etc/cont-init.d/02-vpn-provider-setup.sh"

echo "================================================"
echo "   early-killswitch tests"
echo "================================================"
echo ""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# Filter-table model: $STATE/<cmd>.policy holds "CHAIN POLICY" lines and
# $STATE/<cmd>.rules holds one "CHAIN args..." line per rule.
cat > "$WORK/bin/fw-stub" <<'STUB'
#!/bin/bash
name=$(basename "$0")
[ -n "$FW_FAIL" ] && exit 4
pol="$STATE/$name.policy"; rules="$STATE/$name.rules"
touch "$pol" "$rules"
op="$1"; chain="$2"; shift 2
case "$op" in
  -P) grep -v "^$chain " "$pol" > "$pol.tmp" || true; mv "$pol.tmp" "$pol"; echo "$chain $1" >> "$pol" ;;
  -C) grep -qxF "$chain $*" "$rules" ;;
  -A) echo "$chain $*" >> "$rules" ;;
  -I) shift; { echo "$chain $*"; cat "$rules"; } > "$rules.tmp"; mv "$rules.tmp" "$rules" ;;
  -D) line="$chain $*"; grep -qxF "$line" "$rules" || exit 1
      awk -v l="$line" '!d && $0 == l { d = 1; next } { print }' "$rules" > "$rules.tmp"; mv "$rules.tmp" "$rules" ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$WORK/bin/fw-stub"
ln -s fw-stub "$WORK/bin/iptables"
ln -s fw-stub "$WORK/bin/ip6tables"
export PATH="$WORK/bin:$PATH"

awk '/^early_lock\(\) \{/,/^\}/' "$EARLY" > "$WORK/fn_early.sh"
if [ ! -s "$WORK/fn_early.sh" ]; then
    log_fail "Could not extract early_lock from $EARLY"
    exit 1
fi
# shellcheck disable=SC1091
source "$WORK/fn_early.sh"

reset_state() { export STATE="$WORK/state.$1"; rm -rf "$STATE"; mkdir -p "$STATE"; }

# 1. Policies and loopback, both families
reset_state lock
early_lock > "$WORK/out" 2>&1
for cmd in iptables ip6tables; do
    for c in INPUT FORWARD OUTPUT; do
        if grep -qx "$c DROP" "$STATE/$cmd.policy"; then
            log_pass "$cmd $c policy is DROP"
        else
            log_fail "$cmd $c policy is not DROP"
        fi
    done
    if grep -qx "INPUT -i lo -j ACCEPT" "$STATE/$cmd.rules" && grep -qx "OUTPUT -o lo -j ACCEPT" "$STATE/$cmd.rules"; then
        log_pass "$cmd allows loopback (Docker's embedded DNS lives there)"
    else
        log_fail "$cmd does not allow loopback"
    fi
    if [ "$(grep -cv -e ' -i lo ' -e ' -o lo ' "$STATE/$cmd.rules")" = 0 ]; then
        log_pass "$cmd allows nothing but loopback"
    else
        log_fail "$cmd has rules beyond loopback: $(cat "$STATE/$cmd.rules")"
    fi
done

# 2. Running it twice (container restart in the same pod) adds no duplicates
early_lock > /dev/null 2>&1
if [ "$(grep -c ' lo ' "$STATE/iptables.rules")" = 2 ]; then
    log_pass "second run adds no duplicate loopback rules"
else
    log_fail "second run duplicated rules: $(cat "$STATE/iptables.rules")"
fi

# 3. Without NET_ADMIN it warns and returns 0, so /init still runs and vpn-setup fails closed
reset_state fail
if FW_FAIL=1 early_lock > "$WORK/out" 2>&1 && grep -q "WARN" "$WORK/out"; then
    log_pass "failed lock warns and lets startup continue"
else
    log_fail "failed lock did not warn or returned non-zero"
fi

# 4. The entrypoint hands over to /init with the original arguments
if grep -qx 'exec /init "\$@"' "$EARLY"; then
    log_pass "entrypoint execs /init with its arguments"
else
    log_fail "entrypoint does not exec /init \"\$@\""
fi

# 5. nzbgetvpn only: the provider download opens DNS/HTTP(S) and closes it again
if [ -f "$PROVIDER" ]; then
    awk '/^provider_net\(\) \{/,/^\}/' "$PROVIDER" > "$WORK/fn_provider.sh"
    if [ ! -s "$WORK/fn_provider.sh" ]; then
        log_fail "Could not extract provider_net from $PROVIDER"
    else
        # shellcheck disable=SC1091
        source "$WORK/fn_provider.sh"
        export PROVIDER_NET_TAG="vpn-provider-setup"
        reset_state provider
        early_lock > /dev/null 2>&1
        before=$(cat "$STATE/iptables.rules")
        provider_net open
        if grep -q "OUTPUT -p tcp --dport 443 .*vpn-provider-setup -j ACCEPT" "$STATE/iptables.rules" &&
           grep -q "OUTPUT -p udp --dport 53 " "$STATE/iptables.rules" &&
           grep -q "INPUT -m conntrack --ctstate ESTABLISHED,RELATED " "$STATE/iptables.rules"; then
            log_pass "provider setup opens DNS, HTTPS and replies"
        else
            log_fail "provider setup rules missing: $(cat "$STATE/iptables.rules")"
        fi
        provider_net open   # opened twice must still close completely
        provider_net close
        if [ "$(cat "$STATE/iptables.rules")" = "$before" ] && ! grep -q vpn-provider-setup "$STATE/ip6tables.rules"; then
            log_pass "provider setup closes everything it opened"
        else
            log_fail "provider rules left behind: $(cat "$STATE/iptables.rules")"
        fi
        if grep -qE "^trap 'provider_net close' EXIT" "$PROVIDER" &&
           [ "$(grep -n "^provider_net open" "$PROVIDER" | cut -d: -f1)" -lt "$(grep -n '^case "\$PROVIDER"' "$PROVIDER" | cut -d: -f1)" ]; then
            log_pass "provider setup closes on every exit path and opens before any download"
        else
            log_fail "provider setup is missing the EXIT trap or opens too late"
        fi
    fi
fi

echo ""
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"

#!/command/with-contenv bash
# shellcheck shell=bash
# Shared firewall helper for the PIA forwarded port.
#
# The forwarded port is dynamic: PIA issues a fresh payload and a different port
# on every container start, so it can only be discovered at runtime.
# pia-port-forward.sh records it in PF_PORT_FILE; everything that rebuilds the
# INPUT chain has to re-read that file and re-assert the rules. Without this,
# a rebuild (vpn-setup.sh re-run by vpn-monitor's auto-restart, or either kill
# switch path) silently firewalls off the forwarded port: inbound BitTorrent
# peers are dropped while PIA still has the port bound and every log line still
# reports success.
#
# Source it to get the functions, or run it directly:
#   pia-pf-firewall.sh apply   - install and verify the rules (idempotent)
#   pia-pf-firewall.sh remove  - remove the rules
#   pia-pf-firewall.sh port    - print the live forwarded port
#   pia-pf-firewall.sh status  - report whether the rules are actually present
#
# Exit/return codes for apply/remove/status:
#   0 - rules are in the intended state
#   1 - genuine failure (iptables missing, or the rules could not be installed)
#   2 - no forwarded port is configured, nothing to do (not an error)

PF_PORT_FILE="${PF_PORT_FILE:-/tmp/pia_forwarded_port}"
PF_VPN_INTERFACE_FILE="${PF_VPN_INTERFACE_FILE:-/tmp/vpn_interface_name}"
# Published rule state, for readers that cannot run iptables themselves. The
# metrics server runs unprivileged (s6-setuidgid abc) and so cannot verify the
# chain directly; this file is written by the privileged callers that can.
PF_STATE_FILE="${PF_STATE_FILE:-/tmp/pia_pf_state}"
# tcp/udp ACCEPT on the VPN interface + tcp/udp DROP on eth0.
PF_RULE_COUNT=4

pf_log() {
  echo "[PIA-PF-FW] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Print the live forwarded port, or return 1 if there isn't a usable one.
# Prefers the port PIA actually issued this session over TRANSMISSION_PEER_PORT,
# which is only a fallback for setups that pin a static peer port. Note that
# TRANSMISSION_PEER_PORT does not set Transmission's peer port (that is PEERPORT
# in init-transmission-config); it is only a firewall hint.
pf_is_valid_port() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

pf_get_port() {
  local port=""

  if [ -r "$PF_PORT_FILE" ]; then
    read -r port < "$PF_PORT_FILE" || port=""
    port="${port//[[:space:]]/}"
    # A truncated or corrupt file is treated as no file at all, so a static
    # $TRANSMISSION_PEER_PORT still gets honoured. Warn on stderr, not stdout:
    # callers capture this function's stdout as the port number.
    if [ -n "$port" ] && ! pf_is_valid_port "$port"; then
      pf_log "WARNING: Ignoring invalid port '$port' in $PF_PORT_FILE" >&2
      port=""
    fi
  fi

  if [ -z "$port" ]; then
    port="${TRANSMISSION_PEER_PORT:-}"
    port="${port//[[:space:]]/}"
  fi

  pf_is_valid_port "$port" || return 1
  echo "$port"
}

pf_get_vpn_interface() {
  local vpn_if=""

  if [ -r "$PF_VPN_INTERFACE_FILE" ]; then
    read -r vpn_if < "$PF_VPN_INTERFACE_FILE" || vpn_if=""
    vpn_if="${vpn_if//[[:space:]]/}"
  fi

  if [ -z "$vpn_if" ]; then
    if ip link show tun0 >/dev/null 2>&1; then
      vpn_if="tun0"
    elif ip link show wg0 >/dev/null 2>&1; then
      vpn_if="wg0"
    fi
  fi

  [ -n "$vpn_if" ] || return 1
  echo "$vpn_if"
}

# Publish the observed rule state so unprivileged readers can alert on it.
# Written on every apply and every status check, so its `updated` timestamp
# doubles as a liveness signal: a stale file means the keepalive has stopped.
pf_write_state() {
  local port="$1" found="$2" expected="$3"
  local tmp="${PF_STATE_FILE}.tmp"

  {
    echo "port=${port:-0}"
    echo "rules_found=${found}"
    echo "rules_expected=${expected}"
    echo "rules_present=$([ "$found" -eq "$expected" ] && echo 1 || echo 0)"
    echo "updated=$(date +%s)"
  } > "$tmp" 2>/dev/null || return 0
  # Rename so readers never observe a half-written file.
  mv -f "$tmp" "$PF_STATE_FILE" 2>/dev/null || return 0
  chmod 644 "$PF_STATE_FILE" 2>/dev/null || true
}

# Insert a rule at the head of INPUT only if an identical rule is not present.
# -I (not -A) so the eth0 DROP always precedes any broader eth0 ACCEPT added
# later in the chain, such as the LAN_NETWORK rule.
pf_ensure_rule() {
  iptables -C INPUT "$@" >/dev/null 2>&1 && return 0
  iptables -I INPUT 1 "$@" >/dev/null 2>&1 || return 1
  iptables -C INPUT "$@" >/dev/null 2>&1
}

# Assert the INPUT rules for the forwarded port, then verify they are present.
# Success is only logged when iptables confirms every rule is in the chain -
# a rule that was never installed must never be reported as added.
pf_apply_rules() {
  local vpn_if="${1:-}"
  local port proto failed=0 found=0

  if ! command -v iptables >/dev/null 2>&1; then
    pf_log "ERROR: iptables not available, cannot open the forwarded port"
    return 1
  fi

  if ! port=$(pf_get_port); then
    pf_log "No forwarded port recorded yet (${PF_PORT_FILE}); nothing to apply"
    return 2
  fi

  if [ -z "$vpn_if" ]; then
    if ! vpn_if=$(pf_get_vpn_interface); then
      pf_log "ERROR: Could not determine the VPN interface; port $port left closed"
      return 1
    fi
  fi

  for proto in tcp udp; do
    # Reachable through the tunnel.
    if pf_ensure_rule -i "$vpn_if" -p "$proto" --dport "$port" -j ACCEPT; then
      found=$((found + 1))
    else
      pf_log "ERROR: Failed to install ACCEPT rule for $proto/$port on $vpn_if"
      failed=1
    fi
    # Never reachable off-tunnel. The kill switch's intent is that peer traffic
    # only ever crosses the VPN interface, so eth0 is dropped explicitly rather
    # than left to the default policy, which a later broad ACCEPT could override.
    if pf_ensure_rule -i eth0 -p "$proto" --dport "$port" -j DROP; then
      found=$((found + 1))
    else
      pf_log "ERROR: Failed to install eth0 DROP rule for $proto/$port"
      failed=1
    fi
  done

  pf_write_state "$port" "$found" "$PF_RULE_COUNT"

  if [ "$failed" -ne 0 ]; then
    pf_log "ERROR: Forwarded port $port is NOT fully open on $vpn_if ($found/$PF_RULE_COUNT rules) - inbound peers will be dropped"
    return 1
  fi

  pf_log "Verified INPUT rules for forwarded port $port (ACCEPT on $vpn_if, DROP on eth0)"
  return 0
}

pf_remove_rules() {
  local vpn_if="${1:-}"
  local port proto

  command -v iptables >/dev/null 2>&1 || return 1
  port=$(pf_get_port) || return 2
  if [ -z "$vpn_if" ]; then
    vpn_if=$(pf_get_vpn_interface) || vpn_if="tun0"
  fi

  for proto in tcp udp; do
    iptables -D INPUT -i "$vpn_if" -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i eth0 -p "$proto" --dport "$port" -j DROP 2>/dev/null || true
  done
  pf_log "Removed INPUT rules for forwarded port $port"
  return 0
}

# Report whether the rules are actually in the chain, without changing anything.
pf_status_rules() {
  local vpn_if="${1:-}"
  local port proto missing=0 found=0

  command -v iptables >/dev/null 2>&1 || return 1
  if ! port=$(pf_get_port); then
    pf_log "No forwarded port configured"
    return 2
  fi
  if [ -z "$vpn_if" ]; then
    vpn_if=$(pf_get_vpn_interface) || vpn_if="tun0"
  fi

  for proto in tcp udp; do
    if iptables -C INPUT -i "$vpn_if" -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1; then
      found=$((found + 1))
    else
      pf_log "MISSING: ACCEPT $proto/$port on $vpn_if"
      missing=1
    fi
    if iptables -C INPUT -i eth0 -p "$proto" --dport "$port" -j DROP >/dev/null 2>&1; then
      found=$((found + 1))
    else
      pf_log "MISSING: DROP $proto/$port on eth0"
      missing=1
    fi
  done

  pf_write_state "$port" "$found" "$PF_RULE_COUNT"

  if [ "$missing" -ne 0 ]; then
    pf_log "ERROR: Forwarded port $port is not correctly firewalled"
    return 1
  fi
  pf_log "Forwarded port $port is open on $vpn_if and blocked on eth0"
  return 0
}

# Only run the dispatcher when executed directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-apply}" in
    apply)  pf_apply_rules "${2:-}"; exit $? ;;
    remove) pf_remove_rules "${2:-}"; exit $? ;;
    status) pf_status_rules "${2:-}"; exit $? ;;
    port)   pf_get_port; exit $? ;;
    *)
      echo "Usage: $0 [apply|remove|status|port] [vpn_interface]"
      exit 1
      ;;
  esac
fi

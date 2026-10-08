#!/bin/bash
# Container entrypoint: lock the firewall, then hand over to s6-overlay's /init.
#
# The kill switch used to start with vpn-setup (cont-init 50). Until then the
# container ran on Docker's or Kubernetes' empty, all-ACCEPT firewall, so the
# base image's init, the earlier cont-init scripts and anything exec'd into the
# container could reach the internet without the VPN. A `kubectl exec ... curl`
# about 2s after a restart returned the host's own public IP.
#
# Only the filter table's policies change, and only loopback is allowed. That is
# also where Docker's embedded DNS server (127.0.0.11) lives. vpn-setup flushes
# these chains and builds its own rules from this locked state, so nothing has
# to undo this. Provider config downloads that run before vpn-setup open the
# firewall for themselves (see 02-vpn-provider-setup, nzbgetvpn).

early_lock() {
  local cmd ok=0

  for cmd in iptables ip6tables; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    if "$cmd" -P INPUT DROP 2>/dev/null &&
       "$cmd" -P FORWARD DROP 2>/dev/null &&
       "$cmd" -P OUTPUT DROP 2>/dev/null; then
      "$cmd" -C INPUT -i lo -j ACCEPT 2>/dev/null || "$cmd" -I INPUT 1 -i lo -j ACCEPT 2>/dev/null
      "$cmd" -C OUTPUT -o lo -j ACCEPT 2>/dev/null || "$cmd" -I OUTPUT 1 -o lo -j ACCEPT 2>/dev/null
      [ "$cmd" = iptables ] && ok=1
    elif [ "$cmd" = iptables ]; then
      echo "[WARN] early-killswitch: could not set iptables policies (is NET_ADMIN granted?). vpn-setup will fail closed when it runs." >&2
    fi
  done
  [ "$ok" = 1 ] && echo "[INFO] early-killswitch: all non-loopback traffic blocked until vpn-setup builds the kill switch."
  return 0
}

early_lock
exec /init "$@"

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

#
# The iptables backend is picked here too, before any rule exists, so nothing
# ever mixes rule sets. Every script calls plain `iptables`/`ip6tables`;
# /usr/local/sbin links those names to $BACKEND_DIR, and this points
# $BACKEND_DIR at the chosen xtables binary. Some hosts (Synology DSM) cannot
# use nf_tables: every call fails with "Could not fetch rule set generation id".

BACKEND_DIR=${BACKEND_DIR:-/run/iptables-backend}
XTABLES_DIR=${XTABLES_DIR:-/usr/sbin}
FW_TOOLS="iptables ip6tables iptables-save iptables-restore ip6tables-save ip6tables-restore"

# Can this backend build what vpn-setup needs? Listing alone is not enough: a
# filter chain with conntrack and comment matches (comments tag rules for
# cleanup) and a mangle chain with CONNMARK (web UI reply routing).
backend_works() {
  local multi="$XTABLES_DIR/xtables-$1-multi" chain="TVPN_PROBE_$$" rc=0
  [ -x "$multi" ] || return 1
  "$multi" iptables -w -N "$chain" 2>/dev/null || return 1
  "$multi" iptables -w -A "$chain" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment probe -j ACCEPT 2>/dev/null || rc=1
  "$multi" iptables -w -F "$chain" 2>/dev/null
  "$multi" iptables -w -X "$chain" 2>/dev/null
  [ "$rc" = 0 ] || return 1
  "$multi" iptables -w -t mangle -N "$chain" 2>/dev/null || return 1
  "$multi" iptables -w -t mangle -A "$chain" -j CONNMARK --restore-mark 2>/dev/null || rc=1
  "$multi" iptables -w -t mangle -F "$chain" 2>/dev/null
  "$multi" iptables -w -t mangle -X "$chain" 2>/dev/null
  return "$rc"
}

select_backend() {
  local want="${IPTABLES_BACKEND:-auto}" b="" t
  want=${want,,}

  case "$want" in
    auto)
      if backend_works nft; then
        b=nft
      elif backend_works legacy; then
        b=legacy
        echo "[INFO] early-killswitch: nf_tables does not work on this host; using the legacy iptables backend."
      else
        b=nft
        echo "[ERROR] early-killswitch: neither the nft nor the legacy iptables backend works (is NET_ADMIN granted?). vpn-setup will stop the container." >&2
      fi
      ;;
    nft|legacy)
      b=$want
      backend_works "$b" ||
        echo "[ERROR] early-killswitch: IPTABLES_BACKEND=$b does not work on this host. Not falling back; vpn-setup will stop the container. Try IPTABLES_BACKEND=auto." >&2
      ;;
    *)
      echo "[ERROR] early-killswitch: IPTABLES_BACKEND=$want is invalid (use auto, nft or legacy)." >&2
      return 1
      ;;
  esac

  mkdir -p "$BACKEND_DIR" || return 1
  for t in $FW_TOOLS; do
    ln -sfn "$XTABLES_DIR/xtables-$b-multi" "$BACKEND_DIR/$t" || return 1
  done
  # For 00-iptables-backend, which relinks if /init mounted a fresh /run.
  export IPTABLES_BACKEND_SELECTED="$b"
  echo "[INFO] early-killswitch: iptables backend: $b"
}

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

select_backend || exit 1
early_lock
exec /init "$@"

#!/command/with-contenv bash
# shellcheck shell=bash
# settings.json may bind RPC to "::" (seen as "[::]"). With IPv6 disabled in the
# container that bind fails, so the web UI and RPC (port 9091) never listen,
# while the daemon itself runs. Only then, and only for the IPv6 wildcard (or
# no setting at all), switch to the IPv4 wildcard 0.0.0.0: same reach, nothing
# widened. A specific bind address is left alone and reported.
#
# Both the live settings and the defaults the base image copies on first start
# are patched, since this may run before or after that copy. Transmission is
# not running yet (svc-transmission waits for cont-init), so it will not
# overwrite the change.

IPV6_SYSCTL="${VPN_IPV6_SYSCTL:-/proc/sys/net/ipv6/conf/all/disable_ipv6}"
[ ! -e "$IPV6_SYSCTL" ] || [ "$(cat "$IPV6_SYSCTL" 2>/dev/null)" = 1 ] || exit 0

for f in "${TRANSMISSION_SETTINGS:-/config/settings.json}" "${TRANSMISSION_DEFAULT_SETTINGS:-/defaults/settings.json}"; do
  [ -s "$f" ] || continue
  bind=$(jq -r '."rpc-bind-address" // ""' "$f" 2>/dev/null) || {
    echo "[WARN] rpc-bind: $f is not valid JSON; not changed."
    continue
  }
  case "$bind" in
    "" | "::" | "[::]")
      jq '."rpc-bind-address" = "0.0.0.0"' "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp" &&
        echo "[INFO] rpc-bind: IPv6 is disabled; rpc-bind-address ${bind:-(unset)} -> 0.0.0.0 in $f."
      ;;
    *:*)
      echo "[ERROR] rpc-bind: rpc-bind-address $bind in $f is IPv6, but IPv6 is disabled. The web UI will not listen; set an IPv4 address."
      ;;
  esac
done
exit 0

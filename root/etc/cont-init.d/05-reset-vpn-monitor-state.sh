#!/command/with-contenv bash
# shellcheck shell=bash
# Clear vpn-monitor's restart bookkeeping once per container start.
#
# These files live in /tmp, which survives `docker restart` and a restart policy
# restarting the same container. When vpn-monitor stops the container after
# MAX_RESTART_ATTEMPTS (EXIT_ON_MAX_RESTARTS=true), a surviving counter would put
# the restarted container straight back at the limit, and it would exit again
# without ever trying. This runs as a cont-init script, not in vpn-monitor itself,
# so an s6 restart of the vpn-monitor service alone does not reset the count.

rm -f /tmp/vpn_restart_count \
      /tmp/last_vpn_restart \
      /tmp/vpn_tunnel_state \
      /tmp/pia_keepalive_pid \
      /tmp/last_pf_restart

echo "[INFO] Cleared vpn-monitor restart state from any previous run of this container."

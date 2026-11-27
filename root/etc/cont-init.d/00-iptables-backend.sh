#!/command/with-contenv bash
# shellcheck shell=bash
# The entrypoint (early-killswitch) links /run/iptables-backend to the iptables
# backend it selected. s6-overlay may mount a fresh tmpfs on /run when it has the
# privileges to, which removes those links, and every script would silently fall
# back to /usr/sbin (nft). Recreate them from the entrypoint's choice before
# anything else uses iptables. Nothing to do when the links are still there.

b="${IPTABLES_BACKEND_SELECTED:-}"
dir=/run/iptables-backend
[ -n "$b" ] || exit 0
[ -e "$dir/iptables" ] && exit 0

mkdir -p "$dir" || { echo "[ERROR] iptables-backend: cannot create $dir"; exit 1; }
for t in iptables ip6tables iptables-save iptables-restore ip6tables-save ip6tables-restore; do
  ln -sfn "/usr/sbin/xtables-$b-multi" "$dir/$t"
done
echo "[INFO] iptables-backend: relinked $dir to $b (/run was replaced after the entrypoint)."

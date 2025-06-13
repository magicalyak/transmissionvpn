#!/bin/bash
# Simple wrapper to override HEALTH_CHECK_HOST for VPN testing
# This prevents trying to ping LAN addresses through the VPN tunnel

if [[ "$HEALTH_CHECK_HOST" =~ ^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
    echo "Overriding LAN address $HEALTH_CHECK_HOST with google.com for VPN testing" >&2
    export HEALTH_CHECK_HOST="google.com"
fi

exec /root/healthcheck.sh "$@" 
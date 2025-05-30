#!/bin/bash

# Basic check: is NZBGet responding?
curl -sSf http://localhost:6789 || exit 1

# Check that tunnel is up
ip link show tun0 | grep -q 'state UP' || exit 2

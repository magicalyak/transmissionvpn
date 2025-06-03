#!/command/with-contenv bash
# shellcheck disable=SC1008
# Setup directory compatibility for haugene/docker-transmission-openvpn migration

echo "[INFO] Setting up directory compatibility for haugene migration..."

# Check if compatibility mode is disabled
if [[ "${DISABLE_HAUGENE_COMPATIBILITY,,}" == "true" ]]; then
    echo "[INFO] Haugene compatibility mode disabled via DISABLE_HAUGENE_COMPATIBILITY=true"
    echo "[INFO] Skipping symlink creation."
    exit 0
fi

# Create haugene-compatible symlinks if they don't exist
# This allows both /downloads/complete/ (LinuxServer.io) and /downloads/completed/ (haugene) to work

# Wait for the base image to create the standard directories first
sleep 2

# Ensure the LinuxServer.io standard directories exist
mkdir -p /downloads/complete
mkdir -p /downloads/incomplete

# Create haugene-compatible symlinks only if they don't already exist
if [[ ! -e "/downloads/completed" ]]; then
    if [[ -d "/downloads/complete" ]]; then
        echo "[INFO] Creating haugene-compatible symlink: /downloads/completed -> /downloads/complete"
        ln -sf complete /downloads/completed
        echo "[INFO] Both /downloads/complete/ and /downloads/completed/ now point to the same location"
    else
        echo "[WARN] /downloads/complete directory not found, cannot create compatibility symlink"
    fi
else
    if [[ -L "/downloads/completed" ]]; then
        echo "[INFO] Haugene compatibility symlink already exists: /downloads/completed"
    elif [[ -d "/downloads/completed" ]]; then
        echo "[WARN] /downloads/completed exists as a directory, not creating symlink"
        echo "[WARN] You may need to manually migrate data from /downloads/completed/ to /downloads/complete/"
    fi
fi

# Also create a data symlink for full haugene compatibility (optional)
if [[ ! -e "/data" ]] && [[ -d "/downloads" ]]; then
    echo "[INFO] Creating haugene-compatible symlink: /data -> /downloads"
    ln -sf downloads /data
    echo "[INFO] /data/ now points to /downloads/ for full haugene compatibility"
elif [[ -L "/data" ]]; then
    echo "[INFO] /data symlink already exists: $(readlink /data)"
elif [[ -e "/data" ]]; then
    echo "[INFO] /data already exists as a directory/file, not creating symlink"
fi

# Verify the setup
echo "[INFO] Directory structure after compatibility setup:"
if [[ -d "/downloads" ]]; then
    ls -la /downloads/ 2>/dev/null || echo "[WARN] /downloads directory not accessible"
else
    echo "[WARN] /downloads directory does not exist"
fi

if [[ -L "/data" ]]; then
    echo "[INFO] /data -> $(readlink /data)"
fi
if [[ -L "/downloads/completed" ]]; then
    echo "[INFO] /downloads/completed -> $(readlink /downloads/completed)"
fi

echo "[INFO] Directory compatibility setup complete."
echo "[INFO] "
echo "[INFO] Your container now supports both directory structures:"
echo "[INFO] - LinuxServer.io style: /downloads/complete/, /downloads/incomplete/"
echo "[INFO] - haugene style: /downloads/completed/, /downloads/incomplete/ (via symlink)"
echo "[INFO] - haugene style: /data/completed/, /data/incomplete/ (via symlinks)"
echo "[INFO] "
echo "[INFO] To disable this feature, set DISABLE_HAUGENE_COMPATIBILITY=true" 
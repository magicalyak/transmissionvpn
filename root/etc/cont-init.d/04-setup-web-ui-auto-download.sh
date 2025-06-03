#!/command/with-contenv bash
# shellcheck disable=SC1008
# Automatic download and setup of alternative Transmission web UIs

echo "[INFO] Setting up automatic web UI download..."

# Check if auto download is disabled
if [[ "${TRANSMISSION_WEB_UI_AUTO,,}" == "false" || "${TRANSMISSION_WEB_UI_AUTO,,}" == "disabled" ]]; then
    echo "[INFO] Automatic web UI download disabled"
    exit 0
fi

# If no auto UI is specified, exit
if [[ -z "$TRANSMISSION_WEB_UI_AUTO" || "$TRANSMISSION_WEB_UI_AUTO" == "" ]]; then
    echo "[INFO] No automatic web UI specified (TRANSMISSION_WEB_UI_AUTO not set)"
    exit 0
fi

# Create web UI directory
WEB_UI_DIR="/config/web-ui"
mkdir -p "$WEB_UI_DIR"

# Normalize the UI name
UI_NAME="${TRANSMISSION_WEB_UI_AUTO,,}"
UI_PATH="$WEB_UI_DIR/$UI_NAME"

echo "[INFO] Auto-downloading web UI: $UI_NAME"

# Function to download and extract web UI
download_ui() {
    local ui_name="$1"
    local download_url="$2"
    local extract_method="$3"
    local target_dir="$4"
    
    echo "[INFO] Downloading $ui_name from $download_url"
    
    # Create temporary directory
    local temp_dir="/tmp/webui-download"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || exit 1
    
    # Download with timeout and retries
    local download_file="webui.${extract_method##*.}"
    if curl -L -f --connect-timeout 30 --max-time 300 --retry 3 -o "$download_file" "$download_url"; then
        echo "[INFO] Download successful"
        
        # Extract based on method
        case "$extract_method" in
            "zip")
                if command -v unzip >/dev/null 2>&1; then
                    unzip -q "$download_file"
                    # Find the extracted directory (often has a different name)
                    local extracted_dir
                    extracted_dir=$(find . -maxdepth 1 -type d ! -name "." | head -1)
                    if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                        echo "[INFO] Moving extracted files to $target_dir"
                        rm -rf "$target_dir"
                        mv "$extracted_dir" "$target_dir"
                        return 0
                    fi
                fi
                ;;
            "tar.gz"|"tgz")
                if tar -tzf "$download_file" >/dev/null 2>&1; then
                    tar -xzf "$download_file"
                    local extracted_dir
                    extracted_dir=$(find . -maxdepth 1 -type d ! -name "." | head -1)
                    if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                        echo "[INFO] Moving extracted files to $target_dir"
                        rm -rf "$target_dir"
                        mv "$extracted_dir" "$target_dir"
                        return 0
                    fi
                fi
                ;;
        esac
        
        echo "[ERROR] Failed to extract $ui_name"
        return 1
    else
        echo "[ERROR] Failed to download $ui_name"
        return 1
    fi
}

# Function to clone git repository
clone_ui() {
    local ui_name="$1"
    local git_url="$2"
    local target_dir="$3"
    local subfolder="$4"
    
    echo "[INFO] Cloning $ui_name from $git_url"
    
    if command -v git >/dev/null 2>&1; then
        local temp_dir="/tmp/webui-clone"
        rm -rf "$temp_dir"
        
        if git clone --depth 1 "$git_url" "$temp_dir"; then
            if [[ -n "$subfolder" && -d "$temp_dir/$subfolder" ]]; then
                echo "[INFO] Using subfolder: $subfolder"
                rm -rf "$target_dir"
                mv "$temp_dir/$subfolder" "$target_dir"
            else
                rm -rf "$target_dir"
                mv "$temp_dir" "$target_dir"
            fi
            return 0
        else
            echo "[ERROR] Failed to clone $ui_name"
            return 1
        fi
    else
        echo "[ERROR] Git not available for cloning $ui_name"
        return 1
    fi
}

# Check if UI already exists and skip if found
if [[ -d "$UI_PATH" && -f "$UI_PATH/index.html" ]]; then
    echo "[INFO] Web UI '$UI_NAME' already exists at $UI_PATH"
    echo "[INFO] Skipping download. Delete the directory to force re-download."
else
    echo "[INFO] Downloading web UI '$UI_NAME' to $UI_PATH"
    
    # Download based on UI type
    case "$UI_NAME" in
        "flood"|"flood-for-transmission")
            download_ui "Flood for Transmission" \
                "https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.zip" \
                "zip" \
                "$UI_PATH"
            ;;
        "kettu")
            clone_ui "Kettu" \
                "https://github.com/endor/kettu.git" \
                "$UI_PATH"
            ;;
        "combustion")
            clone_ui "Combustion" \
                "https://github.com/secretmapper/combustion.git" \
                "$UI_PATH"
            ;;
        "transmission-web-control"|"twc")
            clone_ui "Transmission Web Control" \
                "https://github.com/ronggang/transmission-web-control.git" \
                "$UI_PATH" \
                "src"
            ;;
        *)
            echo "[ERROR] Unknown web UI: $UI_NAME"
            echo "[INFO] Supported UIs: flood, kettu, combustion, transmission-web-control"
            exit 1
            ;;
    esac
    
    # Check if download was successful
    if [[ ! -d "$UI_PATH" || ! -f "$UI_PATH/index.html" ]]; then
        echo "[ERROR] Web UI download failed or index.html not found"
        echo "[WARN] Falling back to default Transmission web UI"
        exit 1
    fi
fi

# Set TRANSMISSION_WEB_HOME to use the downloaded UI
export TRANSMISSION_WEB_HOME="$UI_PATH"
echo "[INFO] Setting TRANSMISSION_WEB_HOME=$UI_PATH"

# Create a flag file to indicate successful setup
echo "$UI_NAME" > "$WEB_UI_DIR/.current-ui"

echo "[INFO] Web UI '$UI_NAME' setup complete"
echo "[INFO] Alternative web UI will be available at http://your-server:9091"

# Clean up any temporary files
rm -rf /tmp/webui-download /tmp/webui-clone

# Provide usage information
echo "[INFO] "
echo "[INFO] Installed web UI: $UI_NAME"
echo "[INFO] Location: $UI_PATH"
echo "[INFO] To switch to a different UI:"
echo "[INFO] 1. Set TRANSMISSION_WEB_UI_AUTO=<ui-name>"
echo "[INFO] 2. Delete $UI_PATH to force re-download"
echo "[INFO] 3. Restart the container"
echo "[INFO] "
echo "[INFO] Available UIs: flood, kettu, combustion, transmission-web-control" 
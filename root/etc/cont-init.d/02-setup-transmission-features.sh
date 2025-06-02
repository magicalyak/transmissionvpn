#!/command/with-contenv bash
# shellcheck disable=SC1008
# Setup Transmission features and enhancements

echo "[INFO] Setting up Transmission features..."

# Configure logging to stdout if requested
if [[ "${LOG_TO_STDOUT,,}" == "true" ]]; then
    echo "[INFO] Configuring Transmission to log to stdout..."
    # This will be handled by the base image's transmission configuration
    # We just need to set the environment variable
    export TRANSMISSION_LOG_TO_STDOUT=true
else
    echo "[INFO] Transmission will log to file (default)"
fi

# Handle alternative web UI via TRANSMISSION_WEB_HOME (LinuxServer.io compatible method)
if [[ -n "$TRANSMISSION_WEB_UI" && "$TRANSMISSION_WEB_UI" != "" ]]; then
    echo "[INFO] Alternative web UI requested: $TRANSMISSION_WEB_UI"
    echo "[INFO] To use alternative web UIs, please follow LinuxServer.io method:"
    echo "[INFO] 1. Download your preferred UI to the host"
    echo "[INFO] 2. Mount it to the container and set TRANSMISSION_WEB_HOME"
    echo "[INFO] "
    echo "[INFO] Example for Flood for Transmission:"
    echo "[INFO] 1. Download: curl -OL https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.zip"
    echo "[INFO] 2. Extract: unzip flood-for-transmission.zip"
    echo "[INFO] 3. Mount: -v /path/to/flood-for-transmission:/web-ui:ro"
    echo "[INFO] 4. Set: -e TRANSMISSION_WEB_HOME=/web-ui"
    echo "[INFO] "
    echo "[INFO] Example for Combustion:"
    echo "[INFO] 1. Download: curl -OL https://github.com/secretmapper/combustion/archive/release.zip"
    echo "[INFO] 2. Extract and mount similarly"
    echo "[INFO] "
    echo "[INFO] This method is more reliable than downloading during container startup."
    
    # If TRANSMISSION_WEB_HOME is already set, respect it
    if [[ -n "$TRANSMISSION_WEB_HOME" && -d "$TRANSMISSION_WEB_HOME" ]]; then
        echo "[INFO] TRANSMISSION_WEB_HOME is set to: $TRANSMISSION_WEB_HOME"
        echo "[INFO] Using mounted web UI from: $TRANSMISSION_WEB_HOME"
    else
        echo "[WARN] TRANSMISSION_WEB_HOME not set or directory doesn't exist"
        echo "[WARN] Falling back to default Transmission web UI"
    fi
fi

echo "[INFO] Transmission features setup complete." 
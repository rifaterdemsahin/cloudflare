#!/bin/bash

# Script to manage the cloudflared service.
# Sources .env file for TUNNEL_NAME and CLOUDFLARED_CONFIG_PATH.
# Actions: run, install, start, stop, status

# --- Configuration & Helpers ---
DEFAULT_VERBOSE_LOGGING="true"
LOG_PREFIX="[manage_cf_service.sh]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_CLOUDFLARED_CONFIG_PATH="/etc/cloudflared/config.yml"

# Function to print messages
log_msg() {
    if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} $1"
    fi
}

# Function to print error messages and exit
log_error_exit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ERROR: $1" >&2
    exit 1
}

# Source .env file if it exists
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=.env.example
    source "${ENV_FILE}"
    log_msg "Sourced environment variables from ${ENV_FILE}"
else
    log_msg "No .env file found at ${ENV_FILE}. Using default settings."
fi

# Determine VERBOSE_LOGGING
VERBOSE_LOGGING="${VERBOSE_LOGGING:-${DEFAULT_VERBOSE_LOGGING}}"
if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set -x
fi

# --- Sanity Checks ---
if [[ "$(id -u)" -ne 0 ]]; then
    log_error_exit "This script must be run as root or with sudo for service management actions (install, start, stop, status for system service)."
fi

if ! command -v cloudflared &> /dev/null; then
    log_error_exit "cloudflared command not found. Please run install_cloudflared.sh first."
fi

if ! command -v systemctl &> /dev/null && ( [[ "$1" == "install" ]] || [[ "$1" == "start" ]] || [[ "$1" == "stop" ]] || [[ "$1" == "status" ]] ); then
    log_msg "systemctl command not found. Service management actions (install, start, stop, status) might not work as expected without systemd."
    # Allow to proceed for 'run' or if systemctl is not strictly needed for some status checks
fi


# Determine config file path and tunnel name
CLOUDFLARED_CONFIG_PATH_EFFECTIVE="${CLOUDFLARED_CONFIG_PATH:-${DEFAULT_CLOUDFLARED_CONFIG_PATH}}"

if [[ -z "${TUNNEL_NAME}" ]]; then
    log_msg "TUNNEL_NAME not set in .env. This is needed for 'run' and for clarity in logs."
    # For service install/start/stop, cloudflared reads tunnel from config.yml.
    # For 'run', it's good practice to specify the tunnel name or ID.
fi

# --- Action Handling ---
ACTION="$1"
if [[ -z "$ACTION" ]]; then
    log_error_exit "No action specified. Usage: sudo bash ${0} {run|install|start|stop|status}"
fi

log_msg "Performing action: ${ACTION}"

case "$ACTION" in
    run)
        if [[ -z "${TUNNEL_NAME}" ]]; then
             log_error_exit "TUNNEL_NAME must be set in .env for the 'run' action."
        fi
        if [[ ! -f "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}" ]]; then
            log_error_exit "Cloudflared config file not found at ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}. Generate it first."
        fi
        log_msg "Running tunnel '${TUNNEL_NAME}' with config ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE} in foreground..."
        log_msg "Press Ctrl+C to stop."
        # Ensure CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are available if needed by this command for auth
        export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
        export CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}"
        cloudflared tunnel --config "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}" run "${TUNNEL_NAME}"
        ;;
    install)
        log_msg "Installing cloudflared as a systemd service..."
        log_msg "This will use the configuration from ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}."
        # The 'cloudflared service install' command might take an API token for some auth flows,
        # or it might assume the config.yml and associated credentials file handle auth.
        # Exporting them just in case, though typically not needed if config is complete.
        export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
        export CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}"
        if ! cloudflared service install; then
            log_error_exit "Failed to install cloudflared service."
        fi
        log_msg "cloudflared service installed successfully."
        log_msg "You might need to run 'sudo systemctl daemon-reload' if this is the first time."
        log_msg "Then enable and start the service: sudo systemctl enable cloudflared && sudo systemctl start cloudflared"
        ;;
    start)
        if ! command -v systemctl &> /dev/null; then log_error_exit "systemctl not found. Cannot start service."; fi
        log_msg "Starting cloudflared service..."
        if ! systemctl start cloudflared; then
            log_error_exit "Failed to start cloudflared service. Check 'systemctl status cloudflared' and 'journalctl -u cloudflared'."
        fi
        log_msg "cloudflared service started."
        systemctl status cloudflared --no-pager
        ;;
    stop)
        if ! command -v systemctl &> /dev/null; then log_error_exit "systemctl not found. Cannot stop service."; fi
        log_msg "Stopping cloudflared service..."
        if ! systemctl stop cloudflared; then
            log_error_exit "Failed to stop cloudflared service."
        fi
        log_msg "cloudflared service stopped."
        systemctl status cloudflared --no-pager
        ;;
    status)
        log_msg "Checking cloudflared service status..."
        if command -v systemctl &> /dev/null; then
            systemctl status cloudflared --no-pager
        else
            log_msg "systemctl not found, cannot check system service status."
        fi
        log_msg "---"
        log_msg "Listing Cloudflare tunnels (from cloudflared CLI):"
        # Exporting them just in case, though typically not needed if config is complete.
        export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
        export CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}"
        cloudflared tunnel list
        if [[ -n "${TUNNEL_NAME}" ]]; then
            log_msg "---"
            log_msg "Detailed info for tunnel '${TUNNEL_NAME}':"
            cloudflared tunnel info "${TUNNEL_NAME}"
        fi
        ;;
    *)
        log_error_exit "Invalid action: ${ACTION}. Usage: sudo bash ${0} {run|install|start|stop|status}"
        ;;
esac

if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set +x
fi

log_msg "Service management script finished for action: ${ACTION}."
exit 0

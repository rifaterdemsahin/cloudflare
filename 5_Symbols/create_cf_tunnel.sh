#!/bin/bash

# Script to create a Cloudflare tunnel.
# Sources .env file for TUNNEL_NAME, CF_API_TOKEN, ACCOUNT_ID.
# Outputs the Tunnel ID and attempts to save it back to the .env file.

# --- Configuration & Helpers ---
DEFAULT_VERBOSE_LOGGING="true"
LOG_PREFIX="[create_cf_tunnel.sh]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

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
    log_error_exit "No .env file found at ${ENV_FILE}. This script requires it for configuration. Please copy .env.example to .env and populate it."
fi

# Determine VERBOSE_LOGGING
VERBOSE_LOGGING="${VERBOSE_LOGGING:-${DEFAULT_VERBOSE_LOGGING}}"
if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    # Be cautious with `set -x` if tokens are handled, though this script passes them as env vars to cloudflared.
    # For now, enabling for general command visibility.
    set -x
fi

# --- Sanity Checks ---
if ! command -v cloudflared &> /dev/null; then
    log_error_exit "cloudflared command not found. Please run install_cloudflared.sh first."
fi

if [[ -z "${TUNNEL_NAME}" ]]; then
    log_error_exit "TUNNEL_NAME is not set in ${ENV_FILE}. Please define it (e.g., proxmox-tunnel)."
fi

# Authentication check:
# cloudflared tunnel create typically relies on prior `cloudflared tunnel login` (cert.pem)
# or setting CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID.
if [[ -z "${CF_API_TOKEN}" ]] || [[ -z "${ACCOUNT_ID}" ]]; then
    log_msg "CF_API_TOKEN or ACCOUNT_ID is not set in ${ENV_FILE}."
    log_msg "Attempting tunnel creation. This may rely on an existing cert.pem from a previous 'cloudflared tunnel login'."
    log_msg "If it fails, ensure you have logged in via browser OR set CF_API_TOKEN and ACCOUNT_ID in ${ENV_FILE}."
    # Forcing use of API token if provided:
    export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
    export CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}"
else
    log_msg "Using CF_API_TOKEN and ACCOUNT_ID from .env for authentication."
    export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
    export CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}"
fi


# --- Main Logic ---
log_msg "Attempting to create Cloudflare tunnel named '${TUNNEL_NAME}'..."

# Check if tunnel already exists
# cloudflared tunnel list output format:
# ID                                   NAME             CREATED              CONNECTIONS
# xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx your-tunnel-name 2023-10-26T10:00:00Z 2xLAX, 2xMIA
EXISTING_TUNNEL_ID=$(cloudflared tunnel list | grep " ${TUNNEL_NAME} " | awk '{print $1}')

if [[ -n "$EXISTING_TUNNEL_ID" ]]; then
    log_msg "Tunnel '${TUNNEL_NAME}' already exists with ID: ${EXISTING_TUNNEL_ID}."
    TUNNEL_ID_OUTPUT=${EXISTING_TUNNEL_ID}
else
    log_msg "Creating new tunnel '${TUNNEL_NAME}'..."
    # The output of `cloudflared tunnel create` includes lines like:
    # Tunnel credentials written to /root/.cloudflared/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json. cloudflared chose this file based on where your origin certificate was found. Keep this file secret.
    # Created tunnel YourNewTunnelName with id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    #
    # We need to capture the ID.
    # Using process substitution and tee to capture output and display it.
    CREATE_OUTPUT_FILE=$(mktemp)
    if ! cloudflared tunnel create "${TUNNEL_NAME}" | tee "${CREATE_OUTPUT_FILE}"; then
        log_error_exit "Failed to create tunnel '${TUNNEL_NAME}'. Check logs and authentication."
    fi

    TUNNEL_ID_OUTPUT=$(grep "Created tunnel ${TUNNEL_NAME} with id" "${CREATE_OUTPUT_FILE}" | awk '{print $NF}')
    CREDENTIALS_FILE_PATH=$(grep "Tunnel credentials written to" "${CREATE_OUTPUT_FILE}" | awk '{print $5}')
    rm "${CREATE_OUTPUT_FILE}"

    if [[ -z "${TUNNEL_ID_OUTPUT}" ]]; then
        log_error_exit "Could not parse Tunnel ID from cloudflared output. Manual check required."
    fi
    log_msg "Successfully created tunnel '${TUNNEL_NAME}' with ID: ${TUNNEL_ID_OUTPUT}."
    if [[ -n "${CREDENTIALS_FILE_PATH}" ]]; then
        log_msg "Tunnel credentials written to: ${CREDENTIALS_FILE_PATH}"
        # Storing this path might be useful for config generation
        CREDENTIALS_FILE_PATH_CLEAN=$(echo "${CREDENTIALS_FILE_PATH}" | sed 's/\.$//') # Remove trailing dot if any
    fi
fi

log_msg "--- IMPORTANT ---"
log_msg "Tunnel Name: ${TUNNEL_NAME}"
log_msg "Tunnel ID:   ${TUNNEL_ID_OUTPUT}"
log_msg "Ensure this Tunnel ID is used for your CNAME record at your DNS provider (e.g., GoDaddy)."
log_msg "CNAME Target: ${TUNNEL_ID_OUTPUT}.cfargotunnel.com"
if [[ -n "${CREDENTIALS_FILE_PATH_CLEAN}" ]]; then
     log_msg "Credentials File: ${CREDENTIALS_FILE_PATH_CLEAN}"
fi
log_msg "-----------------"

# Attempt to save TUNNEL_ID and CREDENTIALS_FILE_PATH to .env file
if [[ -f "${ENV_FILE}" ]]; then
    if grep -q "^TUNNEL_ID=" "${ENV_FILE}"; then
        sed -i.bak "s|^TUNNEL_ID=.*|TUNNEL_ID=\"${TUNNEL_ID_OUTPUT}\"|" "${ENV_FILE}"
        log_msg "Updated TUNNEL_ID in ${ENV_FILE}."
    else
        echo "" >> "${ENV_FILE}"
        echo "TUNNEL_ID=\"${TUNNEL_ID_OUTPUT}\"" >> "${ENV_FILE}"
        log_msg "Added TUNNEL_ID to ${ENV_FILE}."
    fi

    if [[ -n "${CREDENTIALS_FILE_PATH_CLEAN}" ]]; then
        if grep -q "^CREDENTIALS_FILE_PATH=" "${ENV_FILE}"; then
            sed -i.bak "s|^CREDENTIALS_FILE_PATH=.*|CREDENTIALS_FILE_PATH=\"${CREDENTIALS_FILE_PATH_CLEAN}\"|" "${ENV_FILE}"
            log_msg "Updated CREDENTIALS_FILE_PATH in ${ENV_FILE}."
        else
            echo "CREDENTIALS_FILE_PATH=\"${CREDENTIALS_FILE_PATH_CLEAN}\"" >> "${ENV_FILE}"
            log_msg "Added CREDENTIALS_FILE_PATH to ${ENV_FILE}."
        fi
    fi
    # Remove backup file created by sed if changes were made
    if [[ -f "${ENV_FILE}.bak" ]]; then
         rm -f "${ENV_FILE}.bak"
    fi
else
    log_msg "Warning: ${ENV_FILE} not found. Could not save TUNNEL_ID or CREDENTIALS_FILE_PATH automatically."
fi

if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set +x
fi

log_msg "Tunnel creation script finished."
exit 0

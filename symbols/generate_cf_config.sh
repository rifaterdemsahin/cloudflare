#!/bin/bash

# Script to generate the /etc/cloudflared/config.yml file.
# Sources .env file for TUNNEL_NAME, TUNNEL_ID, SUBDOMAIN_NAME, DOMAIN_NAME,
# PROXMOX_IP, PROXMOX_PORT, and CREDENTIALS_FILE_PATH.

# --- Configuration & Helpers ---
DEFAULT_VERBOSE_LOGGING="true"
LOG_PREFIX="[generate_cf_config.sh]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_CLOUDFLARED_CONFIG_PATH="/etc/cloudflared/config.yml" # Standard path
DEFAULT_CLOUDFLARED_USER_DIR="/root/.cloudflared" # Default if run as root

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
    set -x
fi

# --- Sanity Checks ---
if [[ "$(id -u)" -ne 0 ]]; then
    log_error_exit "This script must be run as root or with sudo to write to ${DEFAULT_CLOUDFLARED_CONFIG_PATH}."
fi

# Required variables from .env
REQUIRED_VARS=("TUNNEL_NAME" "TUNNEL_ID" "SUBDOMAIN_NAME" "DOMAIN_NAME" "PROXMOX_IP" "PROXMOX_PORT")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        log_error_exit "${var} is not set in ${ENV_FILE}. Please define it."
    fi
done

# Determine credentials file path
# Use CREDENTIALS_FILE_PATH from .env if set (by create_cf_tunnel.sh), otherwise construct default
if [[ -z "${CREDENTIALS_FILE_PATH}" ]]; then
    log_msg "CREDENTIALS_FILE_PATH not found in .env. Constructing default path."
    CLOUDFLARED_USER_DIR_EFFECTIVE="${CLOUDFLARED_USER_DIR:-${DEFAULT_CLOUDFLARED_USER_DIR}}"
    CREDENTIALS_FILE_PATH_EFFECTIVE="${CLOUDFLARED_USER_DIR_EFFECTIVE}/${TUNNEL_ID}.json"
    log_msg "Using default credentials file path: ${CREDENTIALS_FILE_PATH_EFFECTIVE}"
else
    CREDENTIALS_FILE_PATH_EFFECTIVE="${CREDENTIALS_FILE_PATH}"
    log_msg "Using CREDENTIALS_FILE_PATH from .env: ${CREDENTIALS_FILE_PATH_EFFECTIVE}"
fi

if [[ ! -f "${CREDENTIALS_FILE_PATH_EFFECTIVE}" ]]; then
    log_error_exit "Tunnel credentials file not found at ${CREDENTIALS_FILE_PATH_EFFECTIVE}. Ensure tunnel was created and path is correct."
fi

# Determine config file path
CLOUDFLARED_CONFIG_PATH_EFFECTIVE="${CLOUDFLARED_CONFIG_PATH:-${DEFAULT_CLOUDFLARED_CONFIG_PATH}}"
CONFIG_DIR=$(dirname "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}")

# --- Main Logic ---
log_msg "Generating cloudflared configuration file at ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}..."

HOSTNAME_FQDN="${SUBDOMAIN_NAME}.${DOMAIN_NAME}"
PROXMOX_SERVICE_URL="https://$PROXMOX_IP:$PROXMOX_PORT"

# Create config directory if it doesn't exist
if [[ ! -d "${CONFIG_DIR}" ]]; then
    log_msg "Configuration directory ${CONFIG_DIR} does not exist. Creating it..."
    if ! mkdir -p "${CONFIG_DIR}"; then
        log_error_exit "Failed to create configuration directory ${CONFIG_DIR}."
    fi
    log_msg "Configuration directory ${CONFIG_DIR} created."
fi

# Create the config.yml content
# Using a heredoc for clarity
CONFIG_CONTENT=$(cat <<EOF
# Tunnel UUID: ${TUNNEL_ID}
# Tunnel Name: ${TUNNEL_NAME}
# Credentials File: ${CREDENTIALS_FILE_PATH_EFFECTIVE}

tunnel: ${TUNNEL_ID} # Matches the tunnel ID, some older configs might use tunnel name. ID is more robust.
credentials-file: ${CREDENTIALS_FILE_PATH_EFFECTIVE}

ingress:
  - hostname: ${HOSTNAME_FQDN}
    service: ${PROXMOX_SERVICE_URL}
    originRequest:
      noTLSVerify: true # Proxmox often uses self-signed certs locally
  # Default rule to catch all other traffic and return a 404
  - service: http_status:404
EOF
)

log_msg "Generated config.yml content:"
echo "${CONFIG_CONTENT}" # Log the content before writing

# Backup existing config if it exists
if [[ -f "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}" ]]; then
    BACKUP_PATH="${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}.backup.$(date +%F-%H%M%S)"
    log_msg "Backing up existing config ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE} to ${BACKUP_PATH}..."
    if ! cp "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}" "${BACKUP_PATH}"; then
        log_error_exit "Failed to backup existing config file. Aborting."
    fi
fi

log_msg "Writing new configuration to ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}..."
if ! echo "${CONFIG_CONTENT}" > "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}"; then
    log_error_exit "Failed to write configuration to ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}."
fi

# Set permissions (optional, but good practice)
# Typically /etc/cloudflared/config.yml should be readable by root and cloudflared user
chmod 640 "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}"
# chown cloudflared:cloudflared "${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}" # If a 'cloudflared' user exists

log_msg "cloudflared configuration file generated successfully at ${CLOUDFLARED_CONFIG_PATH_EFFECTIVE}."
log_msg "Make sure the 'cloudflared' service user (if applicable) has read access to this file and the credentials file."

if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set +x
fi

log_msg "Config generation script finished."
exit 0

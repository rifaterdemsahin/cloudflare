#!/bin/bash

# Script to configure Proxmox VE pveproxy to listen only on localhost.
# This is a security measure when exposing Proxmox via a tunnel.
# Sources .env file for VERBOSE_LOGGING if set.

# --- Configuration & Helpers ---
DEFAULT_VERBOSE_LOGGING="true"
LOG_PREFIX="[configure_proxmox_firewall.sh]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
PVEPROXY_CONFIG_FILE="/etc/default/pveproxy"
CONFIG_LINE="ALLOW_FROM=\"127.0.0.1,::1\""

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
    log_error_exit "This script must be run as root or with sudo."
fi

if [[ ! -f "${PVEPROXY_CONFIG_FILE}" ]]; then
    log_error_exit "Proxmox proxy config file not found at ${PVEPROXY_CONFIG_FILE}. Is this a Proxmox VE host?"
fi

if ! command -v systemctl &> /dev/null; then
    log_error_exit "systemctl command not found. Cannot restart pveproxy service."
fi

# --- Main Logic ---
log_msg "Configuring Proxmox pveproxy firewall settings..."

# Check if the line already exists and is correct
if grep -q "^ALLOW_FROM=\"127.0.0.1,::1\"" "${PVEPROXY_CONFIG_FILE}"; then
    log_msg "${CONFIG_LINE} already exists in ${PVEPROXY_CONFIG_FILE}. No changes needed to this line."
elif grep -q "^ALLOW_FROM=" "${PVEPROXY_CONFIG_FILE}"; then
    # Line exists but is different, backup and replace
    log_msg "ALLOW_FROM line found but is different. Backing up and updating..."
    cp "${PVEPROXY_CONFIG_FILE}" "${PVEPROXY_CONFIG_FILE}.bak.$(date +%F-%H%M%S)"
    if ! sed -i.bak-sed "s|^ALLOW_FROM=.*|${CONFIG_LINE}|" "${PVEPROXY_CONFIG_FILE}"; then
        log_error_exit "Failed to update ALLOW_FROM line in ${PVEPROXY_CONFIG_FILE}."
    fi
    rm -f "${PVEPROXY_CONFIG_FILE}.bak-sed" # clean up sed backup
    log_msg "Updated ALLOW_FROM line in ${PVEPROXY_CONFIG_FILE} to ${CONFIG_LINE}."
else
    # Line does not exist, backup and add
    log_msg "ALLOW_FROM line not found. Backing up and adding..."
    cp "${PVEPROXY_CONFIG_FILE}" "${PVEPROXY_CONFIG_FILE}.bak.$(date +%F-%H%M%S)"
    echo "" >> "${PVEPROXY_CONFIG_FILE}" # Add a newline just in case last line has no EOL
    echo "${CONFIG_LINE}" >> "${PVEPROXY_CONFIG_FILE}"
    log_msg "Added ${CONFIG_LINE} to ${PVEPROXY_CONFIG_FILE}."
fi

log_msg "Restarting pveproxy service to apply changes..."
if ! systemctl restart pveproxy; then
    log_error_exit "Failed to restart pveproxy service. Check 'systemctl status pveproxy' and 'journalctl -u pveproxy'."
fi

log_msg "pveproxy service restarted successfully."
log_msg "pveproxy should now only be listening on localhost (127.0.0.1 and ::1)."
log_msg "Verify with 'ss -tulnp | grep 8006' or 'netstat -tulnp | grep 8006'."

if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set +x
fi

log_msg "Proxmox firewall configuration script finished."
exit 0

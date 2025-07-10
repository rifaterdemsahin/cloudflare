#!/bin/bash

# Script to download and install the cloudflared Debian package.
# Sources .env file for VERBOSE_LOGGING if set.

# --- Configuration & Helpers ---
# Default to verbose logging if not set in .env
DEFAULT_VERBOSE_LOGGING="true"
LOG_PREFIX="[install_cloudflared.sh]"
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
    log_msg "No .env file found at ${ENV_FILE}. Using default settings."
fi

# Determine VERBOSE_LOGGING
VERBOSE_LOGGING="${VERBOSE_LOGGING:-${DEFAULT_VERBOSE_LOGGING}}"
if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set -x # Print commands and their arguments as they are executed.
fi

# --- Sanity Checks ---
if [[ "$(id -u)" -ne 0 ]]; then
    log_error_exit "This script must be run as root or with sudo. Please use 'sudo bash ${0}'."
fi

if ! command -v curl &> /dev/null; then
    log_msg "curl is not installed. Attempting to install..."
    apt-get update && apt-get install -y curl
    if ! command -v curl &> /dev/null; then
        log_error_exit "Failed to install curl. Please install it manually and re-run."
    fi
    log_msg "curl installed successfully."
fi

if ! command -v dpkg &> /dev/null; then
    log_msg "dpkg is not installed. This is highly unusual for a Debian-based system."
    log_error_exit "dpkg not found. Please ensure your system is Debian-based and dpkg is available."
fi


# --- Main Logic ---
log_msg "Starting cloudflared installation..."

# Check if cloudflared is already installed
if command -v cloudflared &> /dev/null; then
    INSTALLED_VERSION=$(cloudflared --version)
    log_msg "cloudflared is already installed: ${INSTALLED_VERSION}. Skipping installation."
    log_msg "If you need to reinstall or upgrade, please remove the existing version first."
    exit 0
fi

# Define package URL and name
CLOUDFLARED_PKG_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
CLOUDFLARED_PKG_NAME="cloudflared-linux-amd64.deb"
DOWNLOAD_DIR="/tmp"

log_msg "Downloading cloudflared package from ${CLOUDFLARED_PKG_URL} to ${DOWNLOAD_DIR}/${CLOUDFLARED_PKG_NAME}..."
if ! curl -L "${CLOUDFLARED_PKG_URL}" -o "${DOWNLOAD_DIR}/${CLOUDFLARED_PKG_NAME}"; then
    log_error_exit "Failed to download cloudflared package. Check URL or network connection."
fi
log_msg "Download complete."

log_msg "Installing cloudflared package using dpkg..."
if ! dpkg -i "${DOWNLOAD_DIR}/${CLOUDFLARED_PKG_NAME}"; then
    log_msg "dpkg -i failed. This might be due to missing dependencies. Attempting 'apt-get install -f'..."
    if ! apt-get install -f -y; then
        log_error_exit "Failed to install cloudflared package even after 'apt-get install -f'. Please check for dependency issues."
    else
        log_msg "'apt-get install -f' completed. Retrying dpkg install if necessary or checking if already installed."
        if ! command -v cloudflared &> /dev/null; then
             # This typically shouldn't be needed if `apt-get install -f` fixed it and completed the install.
             if ! dpkg -i "${DOWNLOAD_DIR}/${CLOUDFLARED_PKG_NAME}"; then
                log_error_exit "dpkg install failed again. Please check logs."
             fi
        fi
    fi
fi

log_msg "Cleaning up downloaded package ${DOWNLOAD_DIR}/${CLOUDFLARED_PKG_NAME}..."
if ! rm "${DOWNLOAD_DIR}/${CLOUDFLARED_PKG_NAME}"; then
    log_msg "Warning: Failed to remove downloaded package. Manual cleanup might be needed."
fi

# Verify installation
if command -v cloudflared &> /dev/null; then
    INSTALLED_VERSION=$(cloudflared --version)
    log_msg "cloudflared installed successfully! Version: ${INSTALLED_VERSION}"
else
    log_error_exit "cloudflared installation failed. Command 'cloudflared' not found."
fi

if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    set +x
fi

log_msg "Installation script finished."
exit 0

#!/bin/bash

# Script to assist with cloudflared authentication.
# Primarily focuses on guiding the user for browser-based login or ensuring API token is set.

# --- Configuration & Helpers ---
DEFAULT_VERBOSE_LOGGING="true"
LOG_PREFIX="[authenticate_cloudflared.sh]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Function to print messages
log_msg() {
    if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} $1"
    fi
}

# Function to print error messages (does not exit by default in this script)
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ERROR: $1" >&2
}

# Source .env file if it exists
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=.env.example
    source "${ENV_FILE}"
    log_msg "Sourced environment variables from ${ENV_FILE}"
else
    log_msg "No .env file found at ${ENV_FILE}. Using default settings and expecting manual input or pre-set environment variables."
fi

# Determine VERBOSE_LOGGING
VERBOSE_LOGGING="${VERBOSE_LOGGING:-${DEFAULT_VERBOSE_LOGGING}}"
if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    # For this script, we might not want to set -x if it displays sensitive tokens.
    # Consider carefully if CF_API_TOKEN could be exposed.
    # For now, let's keep it off for safety here.
    # set -x
    log_msg "Verbose logging enabled."
fi

# --- Main Logic ---
log_msg "Starting cloudflared authentication assistance..."

if ! command -v cloudflared &> /dev/null; then
    log_error "cloudflared command not found. Please run install_cloudflared.sh first."
    exit 1
fi

# Check if already logged in (though this is hard to check definitively without making calls)
# A simple check could be looking for certificate files, but their location can vary.
# For now, we'll rely on user action or API token.

log_msg "Cloudflare authentication can be done via browser login or an API token."
log_msg "For automation, API token is preferred if subsequent commands support it directly."

# Check if CF_API_TOKEN is set in the environment (sourced from .env or pre-existing)
if [[ -n "${CF_API_TOKEN}" ]] && [[ -n "${ACCOUNT_ID}" ]]; then
    log_msg "CF_API_TOKEN and ACCOUNT_ID are set in the environment."
    log_msg "This token can be used by setting CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID environment variables when running cloudflared commands."
    log_msg "For example: export CLOUDFLARE_API_TOKEN=${CF_API_TOKEN}"
    log_msg "For example: export CLOUDFLARE_ACCOUNT_ID=${ACCOUNT_ID}"
    log_msg "Some cloudflared commands might pick this up automatically if set."
    log_msg "This script will not export it globally. Ensure it's set in the shell where you run other scripts if they rely on it."
    # Example of how other scripts might use it:
    # CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}" CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}" cloudflared tunnel create ...
else
    log_msg "CF_API_TOKEN and/or ACCOUNT_ID are not set in the .env file or current environment."
    log_msg "If you intend to use API token authentication for subsequent scripts (like tunnel creation), please ensure CF_API_TOKEN and ACCOUNT_ID are defined in ${ENV_FILE}."
fi

log_msg "---------------------------------------------------------------------"
log_msg "To authenticate via browser (interactive login):"
log_msg "1. Run the following command in your terminal:"
log_msg "   cloudflared tunnel login"
log_msg "2. A browser window will open. Log in with your Cloudflare account."
log_msg "3. Select the domain you want to use for the tunnel (e.g., ${DOMAIN_NAME:-yourdomain.com})."
log_msg "4. This will download a certificate file (cert.pem) to the default cloudflared directory (usually ~/.cloudflared/ or /root/.cloudflared/)."
log_msg "---------------------------------------------------------------------"

# The `cloudflared tunnel login` command itself is interactive and opens a browser.
# It's not something this script can "do" silently.
# This script serves more as a reminder and checker for the API token.

# A more advanced script could try to use the API token with `cloudflared tunnel token <tunnel_name_or_id>`
# but that's for an existing tunnel. For initial login for tunnel creation, the browser flow or
# ensuring the API token is set for commands that support it is key.
# `cloudflared` itself is moving towards more direct API token usage for commands.

log_msg "Authentication assistance script finished."
log_msg "Ensure you have either completed the browser login or have CF_API_TOKEN and ACCOUNT_ID set in .env for other scripts if they are designed to use token-based auth."

if [[ "${VERBOSE_LOGGING}" == "true" ]]; then
    if [[ -n "$OLD_XTRACE_STATE" ]]; then
        set -x
    else
        set +x
    fi
fi
exit 0

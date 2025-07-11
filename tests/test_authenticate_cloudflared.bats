#!/usr/bin/env bats

# Load bats-support and bats-assert, assuming they are in tests/lib
load 'tests/lib/bats-support/load.bash'
load 'tests/lib/bats-assert/load.bash'

setup() {
    BATS_TMPDIR=$(mktemp -d -t bats-test-XXXXXX)
    export BATS_TMPDIR

    # Path to the script under test
    SCRIPT_UNDER_TEST_ORIGINAL="${BATS_TEST_DIRNAME}/../5_Symbols/authenticate_cloudflared.sh"
    cp "$SCRIPT_UNDER_TEST_ORIGINAL" "${BATS_TMPDIR}/authenticate_cloudflared.sh"
    chmod +x "${BATS_TMPDIR}/authenticate_cloudflared.sh"
    SCRIPT_EXECUTABLE="${BATS_TMPDIR}/authenticate_cloudflared.sh"

    # Default .env content for most tests
    # Tests can override this by creating their own .env in BATS_TMPDIR
    # By default, no API token or account ID to test the guidance part.
    cat > "${BATS_TMPDIR}/.env" <<EOF
VERBOSE_LOGGING=false
DOMAIN_NAME="mytestdomain.com"
EOF

    # Mock common commands
    _prime_command_mock "cloudflared" "exists" # cloudflared is installed by default for tests
}

teardown() {
    rm -rf "$BATS_TMPDIR"
    # Unset any functions or PATH modifications if made (though this test suite is light on them)
    unset -f command
}

# --- Mocking Helper Functions ---
_prime_command_mock() {
    local cmd_name="$1"
    local state="$2" # "exists" or "not_exists"
    mkdir -p "${BATS_TMPDIR}/bin"
    if [ "$state" == "exists" ]; then
        if [ ! -f "${BATS_TMPDIR}/bin/${cmd_name}" ]; then
            echo -e "#!/bin/bash\necho \"Mock for ${cmd_name} invoked with: \$@\" >&2\nexit 0" > "${BATS_TMPDIR}/bin/${cmd_name}"
            chmod +x "${BATS_TMPDIR}/bin/${cmd_name}"
        fi
    else
        rm -f "${BATS_TMPDIR}/bin/${cmd_name}"
    fi
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

# --- Test Cases ---

@test "authenticate_cloudflared.sh: fails if cloudflared command not found" {
    _prime_command_mock "cloudflared" "not_exists" # cloudflared is NOT installed
    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "cloudflared command not found."
}

@test "authenticate_cloudflared.sh: runs successfully and gives guidance if .env is missing" {
    rm "${BATS_TMPDIR}/.env" # Remove .env provided by setup
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "No .env file found at ${BATS_TMPDIR}/.env"
    assert_output --partial "CF_API_TOKEN and/or ACCOUNT_ID are not set"
    assert_output --partial "cloudflared tunnel login"
    assert_output --partial "(e.g., yourdomain.com)" # Default placeholder when DOMAIN_NAME is not available
}

@test "authenticate_cloudflared.sh: API token and Account ID are set in .env" {
    cat > "${BATS_TMPDIR}/.env" <<EOF
CF_API_TOKEN="test-token-123"
ACCOUNT_ID="test-account-abc"
VERBOSE_LOGGING=false
DOMAIN_NAME="custom.com"
EOF
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "CF_API_TOKEN and ACCOUNT_ID are set in the environment."
    assert_output --partial "export CLOUDFLARE_API_TOKEN=test-token-123"
    assert_output --partial "export CLOUDFLARE_ACCOUNT_ID=test-account-abc"
    assert_output --partial "cloudflared tunnel login" # Still shows login instructions
    assert_output --partial "(e.g., custom.com)" # Uses DOMAIN_NAME from .env
}

@test "authenticate_cloudflared.sh: API token missing, Account ID present in .env" {
    cat > "${BATS_TMPDIR}/.env" <<EOF
ACCOUNT_ID="test-account-only"
VERBOSE_LOGGING=false
DOMAIN_NAME="another.org"
EOF
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "CF_API_TOKEN and/or ACCOUNT_ID are not set"
    assert_output --partial "please ensure CF_API_TOKEN and ACCOUNT_ID are defined in ${BATS_TMPDIR}/.env"
    assert_output --partial "(e.g., another.org)"
}

@test "authenticate_cloudflared.sh: API token present, Account ID missing in .env" {
    cat > "${BATS_TMPDIR}/.env" <<EOF
CF_API_TOKEN="test-token-only"
VERBOSE_LOGGING=false
EOF
    # DOMAIN_NAME will use default from initial setup for this test if not overridden
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "CF_API_TOKEN and/or ACCOUNT_ID are not set"
    assert_output --partial "please ensure CF_API_TOKEN and ACCOUNT_ID are defined in ${BATS_TMPDIR}/.env"
    assert_output --partial "(e.g., mytestdomain.com)" # Uses default DOMAIN_NAME
}


@test "authenticate_cloudflared.sh: Neither API token nor Account ID in .env (default setup)" {
    # This uses the default setup .env which has DOMAIN_NAME but no token/account_id
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "CF_API_TOKEN and/or ACCOUNT_ID are not set"
    assert_output --partial "please ensure CF_API_TOKEN and ACCOUNT_ID are defined in ${BATS_TMPDIR}/.env"
    assert_output --partial "cloudflared tunnel login"
    assert_output --partial "(e.g., mytestdomain.com)" # Uses default DOMAIN_NAME
}

@test "authenticate_cloudflared.sh: Browser login instructions use default placeholder if DOMAIN_NAME not in .env" {
    # .env without DOMAIN_NAME
    cat > "${BATS_TMPDIR}/.env" <<EOF
VERBOSE_LOGGING=false
CF_API_TOKEN="some-token"
ACCOUNT_ID="some-account"
EOF
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "cloudflared tunnel login"
    assert_output --partial "(e.g., yourdomain.com)" # Default placeholder
}

@test "authenticate_cloudflared.sh: Verbose logging enabled from .env" {
    cat > "${BATS_TMPDIR}/.env" <<EOF
VERBOSE_LOGGING=true
CF_API_TOKEN="verbose-token"
ACCOUNT_ID="verbose-account"
DOMAIN_NAME="verbose.net"
EOF
    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "Verbose logging enabled."
    assert_output --partial "CF_API_TOKEN and ACCOUNT_ID are set" # Check other messages still appear
    assert_output --partial "(e.g., verbose.net)"
}
EOF

#!/usr/bin/env bats

# Load bats-support and bats-assert, assuming they are in tests/lib
load 'tests/lib/bats-support/load.bash'
load 'tests/lib/bats-assert/load.bash'

DEFAULT_MOCK_CONFIG_FILENAME="config.yml"

setup() {
    BATS_TMPDIR=$(mktemp -d -t bats-test-XXXXXX)
    export BATS_TMPDIR
    export MOCK_CLOUDFLARED_CONFIG_PATH="${BATS_TMPDIR}/${DEFAULT_MOCK_CONFIG_FILENAME}"

    # Path to the script under test
    SCRIPT_UNDER_TEST_ORIGINAL="${BATS_TEST_DIRNAME}/../5_Symbols/manage_cf_service.sh"
    # Modify script to use mock config path if CLOUDFLARED_CONFIG_PATH is not in .env
    # The script already prioritizes CLOUDFLARED_CONFIG_PATH from .env, then default.
    # For tests, we'll ensure .env specifies our mock path.
    cp "$SCRIPT_UNDER_TEST_ORIGINAL" "${BATS_TMPDIR}/manage_cf_service.sh"
    chmod +x "${BATS_TMPDIR}/manage_cf_service.sh"
    SCRIPT_EXECUTABLE="${BATS_TMPDIR}/manage_cf_service.sh"

    # Default .env content
    cat > "${BATS_TMPDIR}/.env" <<EOF
TUNNEL_NAME="my-managed-tunnel"
CLOUDFLARED_CONFIG_PATH="${MOCK_CLOUDFLARED_CONFIG_PATH}"
CF_API_TOKEN="env-api-token"
ACCOUNT_ID="env-account-id"
VERBOSE_LOGGING=false
EOF

    # Create a default mock cloudflared config file
    echo "tunnel: mock-tunnel-id" > "${MOCK_CLOUDFLARED_CONFIG_PATH}"
    echo "credentials-file: /tmp/mock-creds.json" >> "${MOCK_CLOUDFLARED_CONFIG_PATH}"

    # Mock common commands
    mock_id_u_is_root
    _prime_command_mock "cloudflared" "exists"
    _prime_command_mock "systemctl" "exists"

    # Default mocks for cloudflared and systemctl (can be overridden by tests)
    create_executable_mock "cloudflared" 0 "Mock cloudflared output"
    create_executable_mock "systemctl" 0 "Mock systemctl output"

    # Clear mock call logs
    rm -f "${BATS_TMPDIR}/cloudflared_mock_calls.log"
    rm -f "${BATS_TMPDIR}/systemctl_mock_calls.log"
    # Clear exported env var trackers
    rm -f "${BATS_TMPDIR}/exported_vars.log"
}

teardown() {
    rm -rf "$BATS_TMPDIR"
    unset -f id cloudflared systemctl command
    unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID # Unset exported vars
}

# --- Mocking Helper Functions ---
mock_id_u_is_root() {
    mkdir -p "${BATS_TMPDIR}/bin"
    echo -e '#!/bin/bash\nif [ "$1" == "-u" ]; then echo 0; else exec /usr/bin/id "$@"; fi' > "${BATS_TMPDIR}/bin/id"
    chmod +x "${BATS_TMPDIR}/bin/id"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

_prime_command_mock() {
    local cmd_name="$1"
    local state="$2" # "exists" or "not_exists"
    mkdir -p "${BATS_TMPDIR}/bin"
    if [ "$state" == "exists" ]; then
        if [ ! -f "${BATS_TMPDIR}/bin/${cmd_name}" ]; then
            echo -e "#!/bin/bash\necho \"Mock for ${cmd_name} invoked with: \$@\" >> \"${BATS_TMPDIR}/${cmd_name}_mock_generic_calls.log\"\nexit 0" > "${BATS_TMPDIR}/bin/${cmd_name}"
            chmod +x "${BATS_TMPDIR}/bin/${cmd_name}"
        fi
    else
        rm -f "${BATS_TMPDIR}/bin/${cmd_name}"
    fi
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

create_executable_mock() {
    local cmd_name="$1"
    local default_exit_code="$2"
    local default_output="$3"
    mkdir -p "${BATS_TMPDIR}/bin"
    cat > "${BATS_TMPDIR}/bin/${cmd_name}" <<EOF
#!/bin/bash
# Log call with arguments and potentially exported vars
echo "Mock ${cmd_name} CALLED WITH: \$@" >> "${BATS_TMPDIR}/${cmd_name}_mock_calls.log"
if [ -n "\$CLOUDFLARE_API_TOKEN" ]; then
    echo "CLOUDFLARE_API_TOKEN=\${CLOUDFLARE_API_TOKEN}" >> "${BATS_TMPDIR}/exported_vars.log"
fi
if [ -n "\$CLOUDFLARE_ACCOUNT_ID" ]; then
    echo "CLOUDFLARE_ACCOUNT_ID=\${CLOUDFLARE_ACCOUNT_ID}" >> "${BATS_TMPDIR}/exported_vars.log"
fi

if declare -f "${cmd_name}_mock_logic" > /dev/null; then
    ${cmd_name}_mock_logic "\$@"
else
    echo -n "${default_output}"
    exit ${default_exit_code}
fi
EOF
    chmod +x "${BATS_TMPDIR}/bin/${cmd_name}"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

# --- Test Cases ---

@test "manage_cf_service.sh: fails if no action specified" {
    run bash "${SCRIPT_EXECUTABLE}" "" # No action
    assert_failure
    assert_output --partial "No action specified."
}

@test "manage_cf_service.sh: fails with invalid action" {
    run bash "${SCRIPT_EXECUTABLE}" "fly" # Invalid action
    assert_failure
    assert_output --partial "Invalid action: fly"
}

@test "manage_cf_service.sh: fails if not run as root" {
    mkdir -p "${BATS_TMPDIR}/bin"
    echo -e '#!/bin/bash\nif [ "$1" == "-u" ]; then echo 1; fi' > "${BATS_TMPDIR}/bin/id" # Not root
    chmod +x "${BATS_TMPDIR}/bin/id"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"

    run bash "${SCRIPT_EXECUTABLE}" "status" # Any action
    assert_failure
    assert_output --partial "This script must be run as root or with sudo"
}

@test "manage_cf_service.sh: fails if cloudflared command not found" {
    _prime_command_mock "cloudflared" "not_exists"
    run bash "${SCRIPT_EXECUTABLE}" "status"
    assert_failure
    assert_output --partial "cloudflared command not found."
}

@test "manage_cf_service.sh: 'run' action fails if TUNNEL_NAME not set" {
    sed -i '/TUNNEL_NAME/d' "${BATS_TMPDIR}/.env" # Remove TUNNEL_NAME
    run bash "${SCRIPT_EXECUTABLE}" "run"
    assert_failure
    assert_output --partial "TUNNEL_NAME must be set in .env for the 'run' action."
}

@test "manage_cf_service.sh: 'run' action fails if config file not found" {
    rm "${MOCK_CLOUDFLARED_CONFIG_PATH}" # Remove mock config
    run bash "${SCRIPT_EXECUTABLE}" "run"
    assert_failure
    assert_output --partial "Cloudflared config file not found at ${MOCK_CLOUDFLARED_CONFIG_PATH}"
}

@test "manage_cf_service.sh: 'run' action executes cloudflared tunnel run correctly" {
    run bash "${SCRIPT_EXECUTABLE}" "run"
    assert_success # Assumes mock cloudflared exits 0
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "tunnel --config ${MOCK_CLOUDFLARED_CONFIG_PATH} run my-managed-tunnel"
    assert_file_contains "${BATS_TMPDIR}/exported_vars.log" "CLOUDFLARE_API_TOKEN=env-api-token"
    assert_file_contains "${BATS_TMPDIR}/exported_vars.log" "CLOUDFLARE_ACCOUNT_ID=env-account-id"
}

@test "manage_cf_service.sh: 'install' action executes cloudflared service install" {
    run bash "${SCRIPT_EXECUTABLE}" "install"
    assert_success
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "service install"
    assert_file_contains "${BATS_TMPDIR}/exported_vars.log" "CLOUDFLARE_API_TOKEN=env-api-token"
    assert_file_contains "${BATS_TMPDIR}/exported_vars.log" "CLOUDFLARE_ACCOUNT_ID=env-account-id"
    assert_output --partial "cloudflared service installed successfully."
}

@test "manage_cf_service.sh: 'install' action fails if cloudflared service install fails" {
    create_executable_mock "cloudflared" 1 "cloudflared mock: service install failed" # cloudflared fails
    run bash "${SCRIPT_EXECUTABLE}" "install"
    assert_failure
    assert_output --partial "Failed to install cloudflared service."
}

@test "manage_cf_service.sh: 'start' action executes systemctl start and status" {
    run bash "${SCRIPT_EXECUTABLE}" "start"
    assert_success
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "start cloudflared"
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "status cloudflared --no-pager"
    assert_output --partial "cloudflared service started."
}

@test "manage_cf_service.sh: 'start' action fails if systemctl start fails" {
    systemctl_mock_logic() {
        if [ "$1" == "start" ]; then exit 1; fi
        exit 0 # Other systemctl calls succeed
    }
    export -f systemctl_mock_logic
    run bash "${SCRIPT_EXECUTABLE}" "start"
    assert_failure
    assert_output --partial "Failed to start cloudflared service."
}

@test "manage_cf_service.sh: 'start' action fails if systemctl not found" {
    _prime_command_mock "systemctl" "not_exists"
    run bash "${SCRIPT_EXECUTABLE}" "start"
    assert_failure
    assert_output --partial "systemctl not found. Cannot start service."
}


@test "manage_cf_service.sh: 'stop' action executes systemctl stop and status" {
    run bash "${SCRIPT_EXECUTABLE}" "stop"
    assert_success
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "stop cloudflared"
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "status cloudflared --no-pager"
    assert_output --partial "cloudflared service stopped."
}

@test "manage_cf_service.sh: 'stop' action fails if systemctl stop fails" {
    systemctl_mock_logic() {
        if [ "$1" == "stop" ]; then exit 1; fi
        exit 0
    }
    export -f systemctl_mock_logic
    run bash "${SCRIPT_EXECUTABLE}" "stop"
    assert_failure
    assert_output --partial "Failed to stop cloudflared service."
}

@test "manage_cf_service.sh: 'status' action calls systemctl and cloudflared list/info" {
    run bash "${SCRIPT_EXECUTABLE}" "status"
    assert_success
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "status cloudflared --no-pager"
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "tunnel list"
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "tunnel info my-managed-tunnel"
    assert_file_contains "${BATS_TMPDIR}/exported_vars.log" "CLOUDFLARE_API_TOKEN=env-api-token"
    assert_file_contains "${BATS_TMPDIR}/exported_vars.log" "CLOUDFLARE_ACCOUNT_ID=env-account-id"
}

@test "manage_cf_service.sh: 'status' action without TUNNEL_NAME in .env" {
    sed -i '/TUNNEL_NAME/d' "${BATS_TMPDIR}/.env" # Remove TUNNEL_NAME
    run bash "${SCRIPT_EXECUTABLE}" "status"
    assert_success
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "status cloudflared --no-pager"
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "tunnel list"
    # tunnel info should NOT be called
    if grep -q "tunnel info" "${BATS_TMPDIR}/cloudflared_mock_calls.log"; then
        echo "Error: cloudflared tunnel info was called unexpectedly"
        cat "${BATS_TMPDIR}/cloudflared_mock_calls.log"
        exit 1
    fi
}

@test "manage_cf_service.sh: 'status' action when systemctl not found" {
    _prime_command_mock "systemctl" "not_exists"
    run bash "${SCRIPT_EXECUTABLE}" "status"
    assert_success # Script should still proceed to cloudflared parts
    assert_output --partial "systemctl not found, cannot check system service status."
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "tunnel list"
    assert_file_contains "${BATS_TMPDIR}/cloudflared_mock_calls.log" "tunnel info my-managed-tunnel"
}

@test "manage_cf_service.sh: uses default CLOUDFLARED_CONFIG_PATH if not in .env" {
    sed -i '/CLOUDFLARED_CONFIG_PATH/d' "${BATS_TMPDIR}/.env" # Remove from .env
    # Script should now use DEFAULT_CLOUDFLARED_CONFIG_PATH="/etc/cloudflared/config.yml"
    # We need to ensure our mock cloudflared uses this path.
    # The test will fail if the script doesn't form this default path correctly for the command.
    # We also need to "create" this default file for the script's file existence check.

    # This test is tricky because the script hardcodes the default.
    # For the 'run' action, it checks if the file exists.
    # We can't easily create /etc/cloudflared/config.yml in test env.
    # Solution: Modify the script *in the test* to use a mockable default path,
    # OR, only test actions that don't do a file existence check on the default path if it's hardcoded.
    # The 'run' action is the main one checking. Let's test 'run' and ensure it *tries* the default path.

    # For this test, we'll check that the 'run' command is formed with the default path.
    # We'll let the file existence check fail, as that's expected if the default path is used
    # and the file isn't actually there (which it won't be in /etc/cloudflared/).

    # This test will actually check the failure due to missing default config file.
    # The script should try to use /etc/cloudflared/config.yml
    run bash "${SCRIPT_EXECUTABLE}" "run"
    assert_failure
    assert_output --partial "Cloudflared config file not found at /etc/cloudflared/config.yml"
}

@test "manage_cf_service.sh: verbose logging from .env" {
    echo "VERBOSE_LOGGING=true" > "${BATS_TMPDIR}/.env" # Override setup
    run bash "${SCRIPT_EXECUTABLE}" "status" # Any action that logs
    assert_success
    assert_output --partial "+ id -u" # Example of set -x output
}
EOF

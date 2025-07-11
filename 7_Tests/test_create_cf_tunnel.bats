#!/usr/bin/env bats

# Load bats-support and bats-assert, assuming they are in 7_Tests/lib
load '7_Tests/lib/bats-support/load.bash'
load '7_Tests/lib/bats-assert/load.bash'

setup() {
    BATS_TMPDIR=$(mktemp -d -t bats-test-XXXXXX)
    export BATS_TMPDIR

    # Path to the script under test
    SCRIPT_UNDER_TEST_ORIGINAL="${BATS_TEST_DIRNAME}/../5_Symbols/create_cf_tunnel.sh"
    cp "$SCRIPT_UNDER_TEST_ORIGINAL" "${BATS_TMPDIR}/create_cf_tunnel.sh"
    chmod +x "${BATS_TMPDIR}/create_cf_tunnel.sh"
    SCRIPT_EXECUTABLE="${BATS_TMPDIR}/create_cf_tunnel.sh"

    # Default .env content for most tests
    # Tests can override this by creating their own .env in BATS_TMPDIR
    cat > "${BATS_TMPDIR}/.env" <<EOF
TUNNEL_NAME="my-test-tunnel"
CF_API_TOKEN="test-api-token"
ACCOUNT_ID="test-account-id"
VERBOSE_LOGGING=false
EOF

    # Mock common commands
    mock_id_u_is_root # Assumed by other scripts, though not directly checked here.
    _prime_command_mock "cloudflared" "exists" # cloudflared is installed by default for tests

    # Clear any specific cloudflared mock logic
    unset -f cloudflared_mock_logic
    # Default cloudflared mock (can be specialized by tests)
    create_executable_mock "cloudflared" 0 "Default cloudflared mock output"
}

teardown() {
    rm -rf "$BATS_TMPDIR"
    unset -f id cloudflared command grep sed awk tee mktemp rm
    unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID # Unset exported vars
}

# --- Mocking Helper Functions (subset from install_cloudflared tests, simplified) ---

mock_id_u_is_root() { # Script doesn't check root, but good to have a consistent base
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
            echo -e "#!/bin/bash\necho \"Mock for ${cmd_name} invoked with: \$@\" >&2\nexit 0" > "${BATS_TMPDIR}/bin/${cmd_name}"
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
# Default mock for ${cmd_name}
if declare -f "${cmd_name}_mock_logic" > /dev/null; then
    ${cmd_name}_mock_logic "\$@"
else
    echo "${default_output}"
    exit ${default_exit_code}
fi
EOF
    chmod +x "${BATS_TMPDIR}/bin/${cmd_name}"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

# --- Test Cases ---

@test "create_cf_tunnel.sh: fails if .env file is missing" {
    rm "${BATS_TMPDIR}/.env" # Remove .env provided by setup
    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "No .env file found at ${BATS_TMPDIR}/.env"
}

@test "create_cf_tunnel.sh: fails if cloudflared command not found" {
    _prime_command_mock "cloudflared" "not_exists" # cloudflared is NOT installed
    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "cloudflared command not found."
}

@test "create_cf_tunnel.sh: fails if TUNNEL_NAME not in .env" {
    # Create .env without TUNNEL_NAME
    echo "CF_API_TOKEN=\"test-token\"" > "${BATS_TMPDIR}/.env"
    echo "ACCOUNT_ID=\"test-account\"" >> "${BATS_TMPDIR}/.env"

    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "TUNNEL_NAME is not set in ${BATS_TMPDIR}/.env"
}

@test "create_cf_tunnel.sh: proceeds with warning if API token/Account ID missing (relies on cert.pem)" {
    # .env with TUNNEL_NAME but no API token/Account ID
    echo "TUNNEL_NAME=\"my-cert-tunnel\"" > "${BATS_TMPDIR}/.env"

    # Mock cloudflared tunnel list to return no existing tunnel
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then
            echo "ID                                   NAME             CREATED              CONNECTIONS"
            exit 0
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ] && [ "$3" == "my-cert-tunnel" ]; then
            echo "Created tunnel my-cert-tunnel with id new-tunnel-id-from-cert"
            echo "Tunnel credentials written to /root/.cloudflared/new-tunnel-id-from-cert.json."
            exit 0
        fi
        echo "Unexpected cloudflared call in mock: $@" >&2; exit 1;
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success # Script should still try and succeed if cloudflared command works
    assert_output --partial "CF_API_TOKEN or ACCOUNT_ID is not set"
    assert_output --partial "Attempting tunnel creation. This may rely on an existing cert.pem"
    assert_output --partial "Successfully created tunnel 'my-cert-tunnel' with ID: new-tunnel-id-from-cert"
    assert_line --index 0 "TUNNEL_NAME=\"my-cert-tunnel\"" "${BATS_TMPDIR}/.env" # Original line
    assert_file_contains "${BATS_TMPDIR}/.env" "TUNNEL_ID=\"new-tunnel-id-from-cert\""
    assert_file_contains "${BATS_TMPDIR}/.env" "CREDENTIALS_FILE_PATH=\"/root/.cloudflared/new-tunnel-id-from-cert.json\""
}

@test "create_cf_tunnel.sh: uses API_TOKEN and ACCOUNT_ID if present" {
    # .env already has TUNNEL_NAME, CF_API_TOKEN, ACCOUNT_ID from setup

    # Mock cloudflared to check for exported variables
    # This is hard to check directly in bash mock. We'll check the log output.
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then
            # Assert that env vars are set (this is a bit of a hack in a mock)
            if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
                echo "Error: CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID not exported to cloudflared mock" >&2
                exit 120 # Custom exit code to indicate mock failure
            fi
            if [ "$CLOUDFLARE_API_TOKEN" != "test-api-token" ] || [ "$CLOUDFLARE_ACCOUNT_ID" != "test-account-id" ]; then
                echo "Error: API token/Account ID mismatch in mock. Got '$CLOUDFLARE_API_TOKEN', '$CLOUDFLARE_ACCOUNT_ID'" >&2
                exit 121
            fi
            echo "ID                                   NAME             CREATED              CONNECTIONS" # No existing
            exit 0
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ] && [ "$3" == "my-test-tunnel" ]; then
            echo "Created tunnel my-test-tunnel with id new-api-tunnel-id"
            echo "Tunnel credentials written to /root/.cloudflared/new-api-tunnel-id.json."
            exit 0
        fi
        echo "Unexpected cloudflared call in mock: $@" >&2; exit 1;
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "Using CF_API_TOKEN and ACCOUNT_ID from .env for authentication."
    assert_output --partial "Successfully created tunnel 'my-test-tunnel' with ID: new-api-tunnel-id"
    assert_file_contains "${BATS_TMPDIR}/.env" "TUNNEL_ID=\"new-api-tunnel-id\""
}


@test "create_cf_tunnel.sh: handles existing tunnel" {
    local existing_id="existing-tunnel-12345"
    # Mock cloudflared tunnel list to return an existing tunnel
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then
            echo "ID                                   NAME             CREATED              CONNECTIONS"
            echo "${existing_id} my-test-tunnel 2023-01-01T00:00:00Z 1xLAX"
            exit 0
        fi
        # cloudflared tunnel create should NOT be called
        echo "Error: cloudflared tunnel create was called when tunnel should exist!" >&2; exit 1;
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "Tunnel 'my-test-tunnel' already exists with ID: ${existing_id}"
    # Check that .env is updated with the existing ID
    assert_file_contains "${BATS_TMPDIR}/.env" "TUNNEL_ID=\"${existing_id}\""
    # CREDENTIALS_FILE_PATH should not be added/updated if tunnel create is not run
    assert_file_not_contains "${BATS_TMPDIR}/.env" "CREDENTIALS_FILE_PATH="
}

@test "create_cf_tunnel.sh: creates new tunnel successfully and updates .env" {
    local new_id="newly-created-tunnel-67890"
    local creds_path="/root/.cloudflared/${new_id}.json"
    # Mock cloudflared tunnel list (no existing) and tunnel create (success)
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then
            echo "ID                                   NAME             CREATED              CONNECTIONS" # Empty list
            exit 0
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ] && [ "$3" == "my-test-tunnel" ]; then
            echo "Some pre-amble output about creating..."
            echo "Created tunnel my-test-tunnel with id ${new_id}"
            echo "Tunnel credentials written to ${creds_path}." # Note the trailing dot
            echo "Some post-amble output..."
            exit 0
        fi
        echo "Unexpected cloudflared call: $@" >&2; exit 1;
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "Creating new tunnel 'my-test-tunnel'..."
    assert_output --partial "Successfully created tunnel 'my-test-tunnel' with ID: ${new_id}"
    assert_output --partial "Tunnel credentials written to: ${creds_path}"

    # Check .env updates
    assert_file_contains "${BATS_TMPDIR}/.env" "TUNNEL_ID=\"${new_id}\""
    assert_file_contains "${BATS_TMPDIR}/.env" "CREDENTIALS_FILE_PATH=\"${creds_path}\"" # Script cleans trailing dot

    # Verify .env was modified, not just appended if var existed (e.g. TUNNEL_ID was empty before)
    echo "TUNNEL_ID=\"\"" > "${BATS_TMPDIR}/.env.pre" # Start with empty TUNNEL_ID
    echo "TUNNEL_NAME=\"my-test-tunnel\"" >> "${BATS_TMPDIR}/.env.pre"
    echo "CF_API_TOKEN=\"test-api-token\"" >> "${BATS_TMPDIR}/.env.pre"
    echo "ACCOUNT_ID=\"test-account-id\"" >> "${BATS_TMPDIR}/.env.pre"
    cp "${BATS_TMPDIR}/.env.pre" "${BATS_TMPDIR}/.env"

    run bash "${SCRIPT_EXECUTABLE}" # Run again with this specific .env
    assert_success
    local lines_count_id=$(grep -c "^TUNNEL_ID=" "${BATS_TMPDIR}/.env")
    assert_equal "$lines_count_id" 1 "TUNNEL_ID should appear only once"
    assert_file_contains "${BATS_TMPDIR}/.env" "TUNNEL_ID=\"${new_id}\""
}

@test "create_cf_tunnel.sh: fails if cloudflared tunnel create command fails" {
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then exit 0; # No existing
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ]; then
            echo "Error: Failed to create tunnel (simulated cloudflared error)" >&2
            exit 1 # cloudflared command fails
        fi
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "Failed to create tunnel 'my-test-tunnel'"
}

@test "create_cf_tunnel.sh: fails if cannot parse TUNNEL_ID from create output" {
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then exit 0; # No existing
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ]; then
            echo "Tunnel creation was attempted but output is malformed."
            # Missing the crucial "Created tunnel ... with id ..." line
            exit 0 # cloudflared command itself succeeded, but output is bad
        fi
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "Could not parse Tunnel ID from cloudflared output."
}

@test "create_cf_tunnel.sh: .env update handles adding new CREDENTIALS_FILE_PATH" {
    # Setup .env without CREDENTIALS_FILE_PATH
    cat > "${BATS_TMPDIR}/.env" <<EOF
TUNNEL_NAME="my-test-tunnel"
CF_API_TOKEN="test-api-token"
ACCOUNT_ID="test-account-id"
TUNNEL_ID="old-id-to-be-overwritten"
EOF
    # Mock cloudflared for successful creation
    local new_id="new-tunnel-for-credspath-test"
    local creds_path="/tmp/mock-creds/${new_id}.json"
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then exit 0;
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ]; then
            echo "Created tunnel my-test-tunnel with id ${new_id}"
            echo "Tunnel credentials written to ${creds_path}" # No trailing dot this time
            exit 0
        fi
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_file_contains "${BATS_TMPDIR}/.env" "TUNNEL_ID=\"${new_id}\""
    assert_file_contains "${BATS_TMPDIR}/.env" "CREDENTIALS_FILE_PATH=\"${creds_path}\""
    local lines_count_cred=$(grep -c "^CREDENTIALS_FILE_PATH=" "${BATS_TMPDIR}/.env")
    assert_equal "$lines_count_cred" 1 "CREDENTIALS_FILE_PATH should appear only once"
}

@test "create_cf_tunnel.sh: ensures .env.bak file is removed after sed" {
    # This test relies on sed creating a .bak file.
    # Mock sed to create a .bak file, then check it's removed.
    mkdir -p "${BATS_TMPDIR}/bin"
    cat > "${BATS_TMPDIR}/bin/sed" <<EOF
#!/bin/bash
# Mock sed: creates .bak file and performs a simple substitution for testing
cp "\$3" "\$3.bak"
/usr/bin/sed "\$@" # Call real sed to perform the operation
EOF
    chmod +x "${BATS_TMPDIR}/bin/sed"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"

    # Mock cloudflared for successful creation
    cloudflared_mock_logic() {
        if [ "$1" == "tunnel" ] && [ "$2" == "list" ]; then exit 0;
        elif [ "$1" == "tunnel" ] && [ "$2" == "create" ]; then
            echo "Created tunnel my-test-tunnel with id some-id-for-sed-test"
            echo "Tunnel credentials written to /tmp/creds.json"
            exit 0
        fi
    }
    export -f cloudflared_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_file_exist "${BATS_TMPDIR}/.env" # Original should exist
    assert_file_not_exist "${BATS_TMPDIR}/.env.bak" # Backup should be removed
}

# Mock mktemp for a test (e.g. if mktemp fails, though script doesn't check its failure)
# Mock tee (script doesn't check its failure for the tee part)
# Mock grep, awk (parsing failures are indirectly tested by checking if TUNNEL_ID is found)
# The script uses `grep ... | awk ...`. If these fail, TUNNEL_ID_OUTPUT would be empty.
# This is covered by "fails if cannot parse TUNNEL_ID from create output".
EOF

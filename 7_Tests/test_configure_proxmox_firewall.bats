#!/usr/bin/env bats

# Load bats-support and bats-assert, assuming they are in 7_Tests/lib
load '7_Tests/lib/bats-support/load.bash'
load '7_Tests/lib/bats-assert/load.bash'

PVEPROXY_CONFIG_FILENAME="pveproxy" # The actual name of the file in BATS_TMPDIR

setup() {
    BATS_TMPDIR=$(mktemp -d -t bats-test-XXXXXX)
    export BATS_TMPDIR
    export PVEPROXY_CONFIG_FILE_FULL_PATH="${BATS_TMPDIR}/${PVEPROXY_CONFIG_FILENAME}"


    # Path to the script under test
    SCRIPT_UNDER_TEST_ORIGINAL="${BATS_TEST_DIRNAME}/../5_Symbols/configure_proxmox_firewall.sh"
    # We need to modify the script to point PVEPROXY_CONFIG_FILE to our mock path
    sed "s|^PVEPROXY_CONFIG_FILE=.*|PVEPROXY_CONFIG_FILE=\"${PVEPROXY_CONFIG_FILE_FULL_PATH}\"|" \
        "$SCRIPT_UNDER_TEST_ORIGINAL" > "${BATS_TMPDIR}/configure_proxmox_firewall.sh"
    chmod +x "${BATS_TMPDIR}/configure_proxmox_firewall.sh"
    SCRIPT_EXECUTABLE="${BATS_TMPDIR}/configure_proxmox_firewall.sh"

    # Default .env content
    echo "VERBOSE_LOGGING=false" > "${BATS_TMPDIR}/.env"

    # Create a default mock pveproxy config file for most tests
    # Tests can override this by creating their own before running the script
    echo "# Default mock pveproxy config" > "${PVEPROXY_CONFIG_FILE_FULL_PATH}"
    echo "SOME_OTHER_SETTING=true" >> "${PVEPROXY_CONFIG_FILE_FULL_PATH}"

    # Mock common commands
    mock_id_u_is_root
    _prime_command_mock "systemctl" "exists"
    _prime_command_mock "grep" "exists"
    _prime_command_mock "sed" "exists"
    _prime_command_mock "cp" "exists"
    _prime_command_mock "echo" "exists" # Though echo is a builtin, script might call /bin/echo
    _prime_command_mock "rm" "exists"


    # Default mock for systemctl (succeeds)
    create_executable_mock "systemctl" 0 "systemctl mock: success"
    # Default mock for cp (succeeds)
    create_executable_mock "cp" 0 ""
    # Default mock for sed (succeeds)
    create_executable_mock "sed" 0 ""
     # Default mock for rm (succeeds)
    create_executable_mock "rm" 0 ""
    # Grep needs to be more nuanced, often mocked per test.
    # For now, a generic one that can be overridden:
    create_executable_mock "grep" 1 "" # Default: grep finds nothing (exit 1)
}

teardown() {
    rm -rf "$BATS_TMPDIR"
    unset -f id systemctl grep sed cp echo rm # command
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
            echo -e "#!/bin/bash\necho \"Mock for ${cmd_name} invoked with: \$@\" >&2\n# Add logic here if default behavior is needed, e.g., exit 0 for success\nexit 0" > "${BATS_TMPDIR}/bin/${cmd_name}"
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
    # Capture arguments for assertion if needed
    echo "Mock ${cmd_name} called with: \$@" >> "${BATS_TMPDIR}/${cmd_name}_mock_calls.log"
    echo -n "${default_output}" # Use -n to avoid extra newline if output is for capture
    exit ${default_exit_code}
fi
EOF
    chmod +x "${BATS_TMPDIR}/bin/${cmd_name}"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

# --- Test Cases ---

@test "configure_proxmox_firewall.sh: fails if not run as root" {
    mkdir -p "${BATS_TMPDIR}/bin"
    echo -e '#!/bin/bash\nif [ "$1" == "-u" ]; then echo 1; fi' > "${BATS_TMPDIR}/bin/id" # Not root
    chmod +x "${BATS_TMPDIR}/bin/id"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"

    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "This script must be run as root or with sudo."
}

@test "configure_proxmox_firewall.sh: fails if pveproxy config file not found" {
    rm "${PVEPROXY_CONFIG_FILE_FULL_PATH}" # Remove the mock config file
    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "Proxmox proxy config file not found at ${PVEPROXY_CONFIG_FILE_FULL_PATH}"
}

@test "configure_proxmox_firewall.sh: fails if systemctl command not found" {
    _prime_command_mock "systemctl" "not_exists"
    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "systemctl command not found."
}

@test "configure_proxmox_firewall.sh: correct line already exists - no changes, restarts service" {
    echo "ALLOW_FROM=\"127.0.0.1,::1\"" >> "${PVEPROXY_CONFIG_FILE_FULL_PATH}"
    local original_content=$(cat "${PVEPROXY_CONFIG_FILE_FULL_PATH}")

    # Mock grep to find the exact line
    grep_mock_logic() {
        if [[ "$1" == "-q" && "$2" == "^ALLOW_FROM=\"127.0.0.1,::1\"" && "$3" == "${PVEPROXY_CONFIG_FILE_FULL_PATH}" ]]; then
            return 0 # Line found
        fi
        return 1 # Line not found
    }
    export -f grep_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "already exists in ${PVEPROXY_CONFIG_FILE_FULL_PATH}. No changes needed"
    assert_equal "$(cat "${PVEPROXY_CONFIG_FILE_FULL_PATH}")" "$original_content" # File unchanged
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "restart pveproxy" # Service restarted
    assert_file_not_exist "${PVEPROXY_CONFIG_FILE_FULL_PATH}.bak" # No backup should be created
}

@test "configure_proxmox_firewall.sh: ALLOW_FROM exists but is different - updates line" {
    echo "ALLOW_FROM=\"0.0.0.0\"" > "${PVEPROXY_CONFIG_FILE_FULL_PATH}" # Different existing line

    grep_mock_logic() {
        if [[ "$1" == "-q" && "$2" == "^ALLOW_FROM=\"127.0.0.1,::1\"" && "$3" == "${PVEPROXY_CONFIG_FILE_FULL_PATH}" ]]; then
            return 1 # Correct line not found initially
        elif [[ "$1" == "-q" && "$2" == "^ALLOW_FROM=" && "$3" == "${PVEPROXY_CONFIG_FILE_FULL_PATH}" ]]; then
            return 0 # Generic ALLOW_FROM= found
        fi
        return 1
    }
    export -f grep_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "ALLOW_FROM line found but is different. Backing up and updating..."
    assert_output --partial "Updated ALLOW_FROM line"
    assert_file_contains "${PVEPROXY_CONFIG_FILE_FULL_PATH}" "ALLOW_FROM=\"127.0.0.1,::1\""
    assert_file_not_contains "${PVEPROXY_CONFIG_FILE_FULL_PATH}" "ALLOW_FROM=\"0.0.0.0\""
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "restart pveproxy"
    # Check for backup (name will have timestamp, so check for pattern)
    find "${BATS_TMPDIR}" -name "${PVEPROXY_CONFIG_FILENAME}.bak.*" -print | grep -q .
    assert_success $? "Backup file should exist"
    assert_file_not_exist "${PVEPROXY_CONFIG_FILE_FULL_PATH}.bak-sed" # sed backup removed
}

@test "configure_proxmox_firewall.sh: ALLOW_FROM does not exist - adds line" {
    # Initial PVEPROXY_CONFIG_FILE_FULL_PATH from setup has no ALLOW_FROM line
    grep_mock_logic() {
        # All grep calls for ALLOW_FROM should fail (return 1)
        if [[ "$1" == "-q" && "$2" == "^ALLOW_FROM=\"127.0.0.1,::1\"" && "$3" == "${PVEPROXY_CONFIG_FILE_FULL_PATH}" ]]; then return 1; fi
        if [[ "$1" == "-q" && "$2" == "^ALLOW_FROM=" && "$3" == "${PVEPROXY_CONFIG_FILE_FULL_PATH}" ]]; then return 1; fi
        return 1 # Default grep fail
    }
    export -f grep_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "ALLOW_FROM line not found. Backing up and adding..."
    assert_output --partial "Added ALLOW_FROM"
    assert_file_contains "${PVEPROXY_CONFIG_FILE_FULL_PATH}" "ALLOW_FROM=\"127.0.0.1,::1\""
    assert_file_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "restart pveproxy"
    find "${BATS_TMPDIR}" -name "${PVEPROXY_CONFIG_FILENAME}.bak.*" -print | grep -q .
    assert_success $? "Backup file should exist"
}

@test "configure_proxmox_firewall.sh: fails if sed command fails during update" {
    echo "ALLOW_FROM=\"0.0.0.0\"" > "${PVEPROXY_CONFIG_FILE_FULL_PATH}"
    grep_mock_logic() { # Simulate finding a different ALLOW_FROM line
        if [[ "$2" == "^ALLOW_FROM=" ]]; then return 0; else return 1; fi
    }
    export -f grep_mock_logic

    # Mock sed to fail
    create_executable_mock "sed" 1 "sed mock: failed"

    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "Failed to update ALLOW_FROM line"
    # systemctl restart should not have been called
    assert_file_not_contains "${BATS_TMPDIR}/systemctl_mock_calls.log" "restart pveproxy"
}

@test "configure_proxmox_firewall.sh: fails if systemctl restart pveproxy fails" {
    # Ensure a change is made so restart is attempted
    # (ALLOW_FROM does not exist scenario)
    grep_mock_logic() { return 1; } # All greps for ALLOW_FROM fail
    export -f grep_mock_logic

    # Mock systemctl to fail
    create_executable_mock "systemctl" 1 "systemctl mock: restart failed"

    run bash "${SCRIPT_EXECUTABLE}"
    assert_failure
    assert_output --partial "Failed to restart pveproxy service."
}

@test "configure_proxmox_firewall.sh: sed backup .bak-sed is removed" {
    echo "ALLOW_FROM=\"0.0.0.0\"" > "${PVEPROXY_CONFIG_FILE_FULL_PATH}"
    grep_mock_logic() {
        if [[ "$2" == "^ALLOW_FROM=" ]]; then return 0; else return 1; fi
    }
    export -f grep_mock_logic

    # Mock sed to create a .bak-sed file, then succeed
    sed_mock_logic() {
        cp "$3" "$3.bak-sed" # Simulate sed creating its backup
        # Simulate actual sed operation by modifying the file (simplified)
        echo "ALLOW_FROM=\"127.0.0.1,::1\"" > "$3"
        return 0 # sed succeeds
    }
    export -f sed_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_file_not_exist "${PVEPROXY_CONFIG_FILE_FULL_PATH}.bak-sed"
    assert_output --partial "Updated ALLOW_FROM line" # Ensure sed path was taken
}

@test "configure_proxmox_firewall.sh: verbose logging from .env" {
    echo "VERBOSE_LOGGING=true" > "${BATS_TMPDIR}/.env"
    # Minimal mocks for a successful run path (e.g. line already exists)
    grep_mock_logic() { # Correct line exists
        if [[ "$2" == "^ALLOW_FROM=\"127.0.0.1,::1\"" ]]; then return 0; else return 1; fi
    }
    export -f grep_mock_logic

    run bash "${SCRIPT_EXECUTABLE}"
    assert_success
    assert_output --partial "+ id -u" # Example of set -x output
}
EOF

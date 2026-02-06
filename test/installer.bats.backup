#!/usr/bin/env bats
# Manjaro ARM Pi 5 Installer - Test Suite
# Phase 3 Foundation Tests

# Test helper functions
setup() {
    # Set up test environment
    export TMPDIR="/tmp/manjaro-installer-test-$$"
    mkdir -p "$TMPDIR"
    
    # Load lib/log.sh for testing
    if [ -f "lib/log.sh" ]; then
        # shellcheck source=lib/log.sh
        source lib/log.sh
    fi
}

teardown() {
    # Clean up test environment
    rm -rf "$TMPDIR"
}

# Basic existence tests
@test "main installer script exists" {
    [ -f manjaro-pi5-installer-v2_6.sh ]
    [ -f manjaro-pi5-installer-v3.0.sh ]
}

@test "container wrapper exists" {
    [ -f "Container Wrapper.sh" ]
}

@test "installer script is executable or can be run with bash" {
    [ -f "manjaro-pi5-installer-v2_6.sh" ]
}

# Logging system tests
@test "lib/log.sh exists" {
    [ -f "lib/log.sh" ]
}

@test "lib/log.sh can be sourced" {
    source lib/log.sh
}

@test "log functions are available after sourcing" {
    source lib/log.sh
    command -v log_info
    command -v log_warn
    command -v log_error
    command -v log_debug
}

@test "log_info produces output" {
    source lib/log.sh
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test message"* ]]
}

@test "log_error produces output" {
    source lib/log.sh
    run log_error "error message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"error message"* ]]
}

@test "JSON logging can be enabled" {
    source lib/log.sh
    export LOG_JSON=1
    run log_info "json test"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"msg":"json test"'* ]]
}

@test "log phases can be set" {
    source lib/log.sh
    log_set_phase "testing"
    run log_info "phase test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"testing"* ]]
}

# Directory structure tests
@test "docs directory exists" {
    [ -d "docs" ]
}

@test "Roadmap exists" {
    [ -f "docs/Roadmap" ]
}

@test "COPILOT_GUIDE.md exists" {
    [ -f "docs/COPILOT_GUIDE.md" ]
}

@test "lib directory exists" {
    [ -d "lib" ]
}

# Syntax validation tests
@test "main installer has valid bash syntax" {
    bash -n manjaro-pi5-installer-v2_6.sh
    bash -n manjaro-pi5-installer-v3.0.sh
}

@test "container wrapper has valid bash syntax" {
    bash -n "Container Wrapper.sh"
}

@test "lib/log.sh has valid bash syntax" {
    bash -n lib/log.sh
}

# Boot verification function tests (checking if they exist in main script)
@test "main script contains verify_boot_partition function" {
    grep -q "verify_boot_partition()" manjaro-pi5-installer-v2_6.sh
}

@test "main script contains diagnose_boot_partition function" {
    grep -q "diagnose_boot_partition()" manjaro-pi5-installer-v2_6.sh
}

@test "main script contains repair_boot_partition function" {
    grep -q "repair_boot_partition()" manjaro-pi5-installer-v2_6.sh
}

# Network functions tests
@test "main script contains Wi-Fi scanning function" {
    grep -q "ui_scan_wifi_networks()" manjaro-pi5-installer-v2_6.sh
}

@test "main script contains Wi-Fi connection function" {
    grep -q "ui_connect_wifi()" manjaro-pi5-installer-v2_6.sh
}

# Configuration tests
@test "main script uses set -euo pipefail" {
    head -30 manjaro-pi5-installer-v2_6.sh | grep -q "set -euo pipefail"
    head -30 manjaro-pi5-installer-v3.0.sh | grep -q "set -euo pipefail"
}

@test "container wrapper uses set -euo pipefail" {
    head -n 20 "Container Wrapper.sh" | grep -q "set -euo pipefail"
}

# Documentation tests
@test "Roadmap contains Phase 3 Implementation Plan" {
    grep -q "Phase 3 Implementation Plan" docs/Roadmap
}

@test "Roadmap contains Step 1: Establish Foundation" {
    grep -q "Step 1: Establish Foundation" docs/Roadmap
}

@test "Roadmap contains Plugin Architecture section" {
    grep -q "Plugin Architecture" docs/Roadmap
}

# Makefile tests
@test "Makefile exists" {
    [ -f "Makefile" ]
}

@test "Makefile has dev-shell target" {
    grep -q "^dev-shell:" Makefile
}

@test "Makefile has test target" {
    grep -q "^test:" Makefile
}

@test "Makefile has lint target" {
    grep -q "^lint:" Makefile
}

@test "Makefile has docs target" {
    grep -q "^docs:" Makefile
}

@test "v3.0 installer sources plugin system" {
    grep -q 'source.*lib/plugins.sh' manjaro-pi5-installer-v3.0.sh
}

@test "v3.0 installer calls plugin_init" {
    grep -q 'plugin_init' manjaro-pi5-installer-v3.0.sh
}

@test "v3.0 installer uses plugin phases" {
    grep -q 'plugin_run_phase' manjaro-pi5-installer-v3.0.sh
}

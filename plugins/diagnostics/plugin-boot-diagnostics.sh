#!/usr/bin/env bash
#
# Boot Partition Diagnostics Plugin
# Verifies boot partition integrity and identifies issues
#

PLUGIN_NAME="boot-diagnostics"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("diagnostics")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Diagnostics results
declare -ga DIAG_ISSUES=()
declare -ga DIAG_WARNINGS=()
declare -g DIAG_PASSED=0

# Run boot partition diagnostics
plugin_run_diagnostics() {
    log_info "Boot Diagnostics: Starting boot partition verification"
    log_set_phase "diagnostics-boot"
    
    : "${TMPDIR:=/tmp/manjaro-installer}"
    
    DIAG_ISSUES=()
    DIAG_WARNINGS=()
    DIAG_PASSED=0
    
    _check_kernel
    _check_dtb
    _check_firmware
    _check_overlays
    _check_vc4_overlay
    _check_config_txt
    _check_cmdline_txt
    
    _generate_report
    
    if [[ ${#DIAG_ISSUES[@]} -eq 0 ]]; then
        log_info "Boot diagnostics: PASSED"
        return 0
    else
        log_error "Boot diagnostics: FAILED (${#DIAG_ISSUES[@]} issues)"
        return 1
    fi
}

# Check kernel image
_check_kernel() {
    if [[ -f "${TMPDIR}/root/boot/kernel8.img" ]]; then
        log_debug "✓ kernel8.img found"
        ((DIAG_PASSED++))
    else
        log_error "✗ kernel8.img NOT found"
        DIAG_ISSUES+=("kernel8.img missing - system will not boot")
    fi
}

# Check Device Tree Blob
_check_dtb() {
    if [[ -f "${TMPDIR}/root/boot/bcm2712-rpi-5-b.dtb" ]]; then
        log_debug "✓ Pi 5 DTB found"
        ((DIAG_PASSED++))
    else
        log_error "✗ Pi 5 DTB NOT found"
        DIAG_ISSUES+=("bcm2712-rpi-5-b.dtb missing - hardware initialization will fail")
    fi
}

# Check firmware files
_check_firmware() {
    local fw_count=0
    
    # Check for .dat and .elf files
    if ls "${TMPDIR}"/root/boot/*.dat >/dev/null 2>&1; then
        fw_count=$((fw_count + $(ls "${TMPDIR}"/root/boot/*.dat 2>/dev/null | wc -l)))
    fi
    
    if ls "${TMPDIR}"/root/boot/*.elf >/dev/null 2>&1; then
        fw_count=$((fw_count + $(ls "${TMPDIR}"/root/boot/*.elf 2>/dev/null | wc -l)))
    fi
    
    if [[ ${fw_count} -gt 0 ]]; then
        log_debug "✓ Firmware files found (${fw_count} files)"
        ((DIAG_PASSED++))
    else
        log_error "✗ Firmware files NOT found"
        DIAG_ISSUES+=("No firmware files (*.dat, *.elf) - bootloader will fail")
    fi
}

# Check overlays directory
_check_overlays() {
    if [[ ! -d "${TMPDIR}/root/boot/overlays" ]]; then
        log_error "✗ Overlays directory NOT found"
        DIAG_ISSUES+=("Overlays directory missing - hardware features will be unavailable")
        return 1
    fi
    
    local overlay_count
    overlay_count=$(find "${TMPDIR}/root/boot/overlays/" -name "*.dtbo" 2>/dev/null | wc -l)
    
    if [[ ${overlay_count} -gt 0 ]]; then
        log_debug "✓ Overlays directory found (${overlay_count} overlays)"
        ((DIAG_PASSED++))
    else
        log_warn "⚠ Overlays directory empty"
        DIAG_WARNINGS+=("No overlay files found - hardware features may be limited")
    fi
}

# Check vc4-kms-v3d overlay (critical for display)
_check_vc4_overlay() {
    if [[ -f "${TMPDIR}/root/boot/overlays/vc4-kms-v3d.dtbo" ]] || \
       [[ -f "${TMPDIR}/root/boot/overlays/vc4-kms-v3d-pi5.dtbo" ]]; then
        log_debug "✓ vc4-kms-v3d overlay found"
        ((DIAG_PASSED++))
    else
        log_error "✗ vc4-kms-v3d overlay NOT found"
        DIAG_ISSUES+=("vc4-kms-v3d overlay missing - display will not work")
    fi
}

# Check config.txt
_check_config_txt() {
    if [[ ! -f "${TMPDIR}/root/boot/config.txt" ]]; then
        log_error "✗ config.txt NOT found"
        DIAG_ISSUES+=("config.txt missing - boot configuration unavailable")
        return 1
    fi
    
    log_debug "✓ config.txt found"
    ((DIAG_PASSED++))
    
    # Check for vc4-kms-v3d in config
    if ! grep -q "dtoverlay=vc4-kms-v3d" "${TMPDIR}/root/boot/config.txt"; then
        log_warn "⚠ config.txt missing vc4-kms-v3d"
        DIAG_WARNINGS+=("vc4-kms-v3d not enabled in config.txt - may affect display")
    fi
    
    # Check for Pi 5 specific settings
    if ! grep -q "\[pi5\]" "${TMPDIR}/root/boot/config.txt"; then
        log_warn "⚠ No [pi5] section in config.txt"
        DIAG_WARNINGS+=("No [pi5] section in config.txt - using generic settings")
    fi
}

# Check cmdline.txt
_check_cmdline_txt() {
    if [[ -f "${TMPDIR}/root/boot/cmdline.txt" ]]; then
        log_debug "✓ cmdline.txt found"
        ((DIAG_PASSED++))
        
        # Check for root= parameter
        if ! grep -q "root=" "${TMPDIR}/root/boot/cmdline.txt"; then
            log_error "✗ cmdline.txt missing root= parameter"
            DIAG_ISSUES+=("cmdline.txt missing root parameter - system will not find rootfs")
        fi
    else
        log_error "✗ cmdline.txt NOT found"
        DIAG_ISSUES+=("cmdline.txt missing - kernel command line unavailable")
    fi
}

# Generate diagnostic report
_generate_report() {
    log_info "=== Boot Partition Diagnostics Report ==="
    log_info "Checks passed: ${DIAG_PASSED}"
    log_info "Issues found: ${#DIAG_ISSUES[@]}"
    log_info "Warnings: ${#DIAG_WARNINGS[@]}"
    
    if [[ ${#DIAG_ISSUES[@]} -gt 0 ]]; then
        log_error "Critical Issues:"
        for issue in "${DIAG_ISSUES[@]}"; do
            log_error "  - ${issue}"
        done
    fi
    
    if [[ ${#DIAG_WARNINGS[@]} -gt 0 ]]; then
        log_warn "Warnings:"
        for warning in "${DIAG_WARNINGS[@]}"; do
            log_warn "  - ${warning}"
        done
    fi
    
    log_info "========================================"
}

# Get diagnostic summary as JSON
diagnostics_json() {
    cat <<EOF
{
  "passed": ${DIAG_PASSED},
  "issues": ${#DIAG_ISSUES[@]},
  "warnings": ${#DIAG_WARNINGS[@]},
  "status": "$([[ ${#DIAG_ISSUES[@]} -eq 0 ]] && echo "PASS" || echo "FAIL")"
}
EOF
}

# Export functions
export -f diagnostics_json

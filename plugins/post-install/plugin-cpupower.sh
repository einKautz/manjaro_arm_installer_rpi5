#!/usr/bin/env bash
#
# CPUPower Governor Plugin
# Configures CPU frequency scaling
#

PLUGIN_NAME="cpupower"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("post-install")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Configure CPU governor
plugin_run_post_install() {
    log_info "CPUPower Plugin: Setting up CPU governor"
    log_set_phase "optimize-cpupower"
    
    : "${TMPDIR:=/tmp/manjaro-installer}"
    : "${NSPAWN:=systemd-nspawn -D}"
    
    log_info "Installing cpupower package"
    ${NSPAWN} "${TMPDIR}/root" pacman -S --noconfirm --needed cpupower 2>&1 | tee -a "${TMPDIR}/install.log" || {
        log_error "Failed to install cpupower"
        return 1
    }
    
    log_info "Configuring ondemand governor"
    echo 'GOVERNOR="ondemand"' > "${TMPDIR}/root/etc/default/cpupower"
    
    log_info "Enabling cpupower service"
    ${NSPAWN} "${TMPDIR}/root" systemctl enable cpupower 2>&1 | tee -a "${TMPDIR}/install.log"
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_info "CPUPower configured successfully"
        return 0
    else
        log_error "Failed to enable cpupower service"
        return 1
    fi
}

#!/usr/bin/env bash
#
# Fstrim Timer Plugin
# Enables periodic TRIM for SSDs
#

PLUGIN_NAME="fstrim"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("post-install")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Enable fstrim timer
plugin_run_post_install() {
    log_info "Fstrim Plugin: Enabling weekly TRIM timer"
    log_set_phase "optimize-fstrim"
    
    : "${TMPDIR:=/tmp/manjaro-installer}"
    : "${NSPAWN:=systemd-nspawn -D}"
    
    log_info "Enabling fstrim.timer service"
    ${NSPAWN} "${TMPDIR}/root" systemctl enable fstrim.timer 2>&1 | tee -a "${TMPDIR}/install.log"
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_info "Fstrim timer enabled successfully"
        return 0
    else
        log_error "Failed to enable fstrim timer"
        return 1
    fi
}

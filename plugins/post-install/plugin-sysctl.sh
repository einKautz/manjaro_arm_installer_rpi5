#!/usr/bin/env bash
#
# Sysctl Kernel Tuning Plugin
# Optimizes kernel parameters for Pi 5
#

PLUGIN_NAME="sysctl"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("post-install")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Apply sysctl optimizations
plugin_run_post_install() {
    log_info "Sysctl Plugin: Applying kernel tuning"
    log_set_phase "optimize-sysctl"
    
    : "${TMPDIR:=/tmp/manjaro-installer}"
    
    log_info "Creating sysctl configuration"
    cat > "${TMPDIR}/root/etc/sysctl.d/99-pi5-tuning.conf" <<'EOF'
# Pi 5 Kernel Tuning
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Sysctl tuning applied successfully"
        return 0
    else
        log_error "Failed to create sysctl configuration"
        return 1
    fi
}

#!/usr/bin/env bash
#
# ZRAM Optimization Plugin
# Enables compressed swap in RAM
#

PLUGIN_NAME="zram"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("post-install")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Apply ZRAM optimization
plugin_run_post_install() {
    log_info "ZRAM Plugin: Enabling compressed swap"
    log_set_phase "optimize-zram"
    
    # Import required variables
    : "${TMPDIR:=/tmp/manjaro-installer}"
    : "${NSPAWN:=systemd-nspawn -D}"
    
    # Install zram-generator
    log_info "Installing zram-generator package"
    ${NSPAWN} "${TMPDIR}/root" pacman -S --noconfirm --needed zram-generator 2>&1 | tee -a "${TMPDIR}/install.log" || {
        log_error "Failed to install zram-generator"
        return 1
    }
    
    # Create configuration directory
    mkdir -p "${TMPDIR}/root/etc/systemd/zram-generator.conf.d"
    
    # Write ZRAM configuration
    log_info "Configuring ZRAM"
    cat > "${TMPDIR}/root/etc/systemd/zram-generator.conf.d/zram.conf" <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "ZRAM optimization applied successfully"
        return 0
    else
        log_error "Failed to configure ZRAM"
        return 1
    fi
}

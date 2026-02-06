#!/usr/bin/env bash
#
# Plugin: GPU Memory Optimization
# Configures GPU memory split for Raspberry Pi 5
#

PLUGIN_NAME="gpu-mem"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("post-install")

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

plugin_run_post_install() {
    log_set_phase "gpu-mem-post-install"
    log_info "GPU Memory: Configuring GPU memory split"
    
    local boot_config="${MOUNT_POINT}/boot/config.txt"
    
    if [[ ! -f "$boot_config" ]]; then
        log_warn "GPU Memory: config.txt not found at $boot_config"
        return 0  # Not fatal
    fi
    
    # Determine optimal GPU memory based on use case
    local gpu_mem=128  # Default for desktop environments
    
    # Check if this is a minimal/headless installation
    if [[ "${EDITION:-}" == "minimal" ]]; then
        gpu_mem=16  # Minimal for headless
        log_info "GPU Memory: Setting to ${gpu_mem}MB (headless/minimal)"
    else
        log_info "GPU Memory: Setting to ${gpu_mem}MB (desktop environment)"
    fi
    
    # Remove existing gpu_mem settings
    sed -i '/^gpu_mem=/d' "$boot_config"
    
    # Add optimized GPU memory setting
    if ! grep -q "^gpu_mem=" "$boot_config"; then
        {
            echo ""
            echo "# GPU Memory Configuration (optimized by installer)"
            echo "gpu_mem=${gpu_mem}"
        } >> "$boot_config"
        log_info "GPU Memory: Configured gpu_mem=${gpu_mem} in config.txt"
    fi
    
    # Additional optimization: Disable unnecessary GPU features for headless
    if [[ "${EDITION:-}" == "minimal" ]]; then
        if ! grep -q "^dtoverlay=vc4-kms-v3d,noaudio" "$boot_config"; then
            sed -i 's/^dtoverlay=vc4-kms-v3d$/dtoverlay=vc4-kms-v3d,noaudio/' "$boot_config" 2>/dev/null || true
            log_info "GPU Memory: Disabled GPU audio for headless setup"
        fi
    fi
    
    log_info "GPU Memory: Configuration complete"
    return 0
}

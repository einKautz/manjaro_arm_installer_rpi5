#!/usr/bin/env bash
#
# HAL: Device Tree Overlay Management
# Handles DTB overlays for hardware features
#

# Source logging if not already loaded
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# List available overlays
hal_overlay_list_available() {
    local mount_point="${MOUNT_POINT:-/mnt}"
    local overlay_dir="${mount_point}/boot/overlays"
    
    log_info "HAL Overlay: Listing available overlays"
    
    if [[ ! -d "$overlay_dir" ]]; then
        log_warn "HAL Overlay: Overlay directory not found: $overlay_dir"
        return 1
    fi
    
    local overlays=()
    for overlay in "$overlay_dir"/*.dtbo; do
        if [[ -f "$overlay" ]]; then
            local overlay_name
            overlay_name=$(basename "$overlay" .dtbo)
            overlays+=("$overlay_name")
        fi
    done
    
    if [[ ${#overlays[@]} -eq 0 ]]; then
        log_warn "HAL Overlay: No overlays found"
        return 1
    fi
    
    log_info "HAL Overlay: Found ${#overlays[@]} overlay(s)"
    printf '%s\n' "${overlays[@]}"
    return 0
}

# Enable an overlay
hal_overlay_enable() {
    local overlay_name="$1"
    local parameters="${2:-}"
    local mount_point="${MOUNT_POINT:-/mnt}"
    local boot_config="${mount_point}/boot/config.txt"
    
    if [[ -z "$overlay_name" ]]; then
        log_error "HAL Overlay: No overlay name specified"
        return 1
    fi
    
    log_info "HAL Overlay: Enabling overlay: $overlay_name"
    
    if [[ ! -f "$boot_config" ]]; then
        log_error "HAL Overlay: config.txt not found"
        return 1
    fi
    
    # Check if overlay already enabled
    if grep -q "^dtoverlay=${overlay_name}" "$boot_config"; then
        log_info "HAL Overlay: ${overlay_name} already enabled"
        return 0
    fi
    
    # Add overlay
    if [[ -n "$parameters" ]]; then
        echo "dtoverlay=${overlay_name},${parameters}" >> "$boot_config"
        log_info "HAL Overlay: Enabled ${overlay_name} with parameters: $parameters"
    else
        echo "dtoverlay=${overlay_name}" >> "$boot_config"
        log_info "HAL Overlay: Enabled ${overlay_name}"
    fi
    
    return 0
}

# Disable an overlay
hal_overlay_disable() {
    local overlay_name="$1"
    local mount_point="${MOUNT_POINT:-/mnt}"
    local boot_config="${mount_point}/boot/config.txt"
    
    if [[ -z "$overlay_name" ]]; then
        log_error "HAL Overlay: No overlay name specified"
        return 1
    fi
    
    log_info "HAL Overlay: Disabling overlay: $overlay_name"
    
    if [[ ! -f "$boot_config" ]]; then
        log_error "HAL Overlay: config.txt not found"
        return 1
    fi
    
    # Remove overlay line
    sed -i "/^dtoverlay=${overlay_name}/d" "$boot_config"
    log_info "HAL Overlay: Disabled ${overlay_name}"
    
    return 0
}

# Configure common Pi 5 overlays
hal_overlay_configure_pi5() {
    local mount_point="${MOUNT_POINT:-/mnt}"
    
    log_info "HAL Overlay: Configuring Pi 5 overlays"
    
    # Enable VC4 graphics (should already be there, but ensure it)
    hal_overlay_enable "vc4-kms-v3d"
    
    # Enable I2C if requested
    if [[ "${ENABLE_I2C:-0}" == "1" ]]; then
        hal_overlay_enable "i2c1"
        log_info "HAL Overlay: I2C enabled"
    fi
    
    # Enable SPI if requested
    if [[ "${ENABLE_SPI:-0}" == "1" ]]; then
        hal_overlay_enable "spi"
        log_info "HAL Overlay: SPI enabled"
    fi
    
    # Enable UART if requested
    if [[ "${ENABLE_UART:-0}" == "1" ]]; then
        hal_overlay_enable "uart0"
        log_info "HAL Overlay: UART enabled"
    fi
    
    # Disable Bluetooth if requested (useful for UART on GPIO)
    if [[ "${DISABLE_BT:-0}" == "1" ]]; then
        hal_overlay_enable "disable-bt"
        log_info "HAL Overlay: Bluetooth disabled"
    fi
    
    log_info "HAL Overlay: Pi 5 overlay configuration complete"
    return 0
}

# Get list of currently enabled overlays
hal_overlay_list_enabled() {
    local mount_point="${MOUNT_POINT:-/mnt}"
    local boot_config="${mount_point}/boot/config.txt"
    
    log_info "HAL Overlay: Listing enabled overlays"
    
    if [[ ! -f "$boot_config" ]]; then
        log_error "HAL Overlay: config.txt not found"
        return 1
    fi
    
    local overlays=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^dtoverlay=(.+) ]]; then
            local overlay="${BASH_REMATCH[1]}"
            # Remove parameters if present
            overlay="${overlay%%,*}"
            overlays+=("$overlay")
        fi
    done < "$boot_config"
    
    if [[ ${#overlays[@]} -eq 0 ]]; then
        log_info "HAL Overlay: No overlays currently enabled"
        return 1
    fi
    
    log_info "HAL Overlay: ${#overlays[@]} overlay(s) enabled"
    printf '%s\n' "${overlays[@]}"
    return 0
}

# Export functions
export -f hal_overlay_list_available
export -f hal_overlay_enable
export -f hal_overlay_disable
export -f hal_overlay_configure_pi5
export -f hal_overlay_list_enabled

#!/usr/bin/env bash
#
# HAL: Display Management
# Handles HDMI configuration, resolution detection, and display settings
#

# Source logging if not already loaded
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Detect connected displays
hal_display_detect() {
    log_info "HAL Display: Detecting connected displays"
    
    local displays=()
    
    # Check for HDMI outputs
    if [[ -d /sys/class/drm ]]; then
        for connector in /sys/class/drm/card*/card*-HDMI-*/status; do
            if [[ -f "$connector" ]] && grep -q "^connected$" "$connector"; then
                local display_name
                display_name=$(basename "$(dirname "$connector")")
                displays+=("$display_name")
                log_info "HAL Display: Found connected display: $display_name"
            fi
        done
    fi
    
    if [[ ${#displays[@]} -eq 0 ]]; then
        log_warn "HAL Display: No displays detected"
        return 1
    fi
    
    # Export detected displays
    export HAL_DISPLAYS="${displays[*]}"
    log_info "HAL Display: Detected ${#displays[@]} display(s)"
    return 0
}

# Get display resolution
hal_display_get_resolution() {
    local display="${1:-HDMI-1}"
    
    log_info "HAL Display: Getting resolution for $display"
    
    # Try to read EDID information
    if command -v edid-decode &>/dev/null; then
        local edid_file="/sys/class/drm/${display}/edid"
        if [[ -f "$edid_file" ]]; then
            local resolution
            resolution=$(edid-decode "$edid_file" 2>/dev/null | grep -oP '\d+x\d+' | head -1)
            if [[ -n "$resolution" ]]; then
                log_info "HAL Display: Native resolution: $resolution"
                echo "$resolution"
                return 0
            fi
        fi
    fi
    
    # Default to common resolutions
    log_info "HAL Display: Using default resolution 1920x1080"
    echo "1920x1080"
    return 0
}

# Configure display in target system
hal_display_configure() {
    local mount_point="${MOUNT_POINT:-/mnt}"
    local resolution="${1:-auto}"
    
    log_info "HAL Display: Configuring display settings"
    
    # Create Xorg configuration snippet
    local xorg_display_conf="${mount_point}/etc/X11/xorg.conf.d/10-display.conf"
    
    mkdir -p "$(dirname "$xorg_display_conf")"
    
    if [[ "$resolution" == "auto" ]]; then
        cat > "$xorg_display_conf" << 'EOF'
# Display configuration (automatic)
Section "Monitor"
    Identifier "HDMI-1"
    Option "PreferredMode" "auto"
EndSection
EOF
        log_info "HAL Display: Configured automatic resolution"
    else
        cat > "$xorg_display_conf" << EOF
# Display configuration (${resolution})
Section "Monitor"
    Identifier "HDMI-1"
    Option "PreferredMode" "${resolution}"
EndSection
EOF
        log_info "HAL Display: Configured ${resolution} resolution"
    fi
    
    return 0
}

# Enable/disable HDMI features
hal_display_set_hdmi_options() {
    local mount_point="${MOUNT_POINT:-/mnt}"
    local force_hotplug="${1:-1}"  # 1=force, 0=auto
    local hdmi_group="${2:-0}"     # 0=auto, 1=CEA, 2=DMT
    local hdmi_mode="${3:-0}"      # 0=auto
    
    log_info "HAL Display: Configuring HDMI options"
    
    local boot_config="${mount_point}/boot/config.txt"
    
    if [[ ! -f "$boot_config" ]]; then
        log_warn "HAL Display: config.txt not found"
        return 1
    fi
    
    # Remove existing HDMI settings
    sed -i '/^hdmi_force_hotplug=/d' "$boot_config"
    sed -i '/^hdmi_group=/d' "$boot_config"
    sed -i '/^hdmi_mode=/d' "$boot_config"
    
    # Add HDMI configuration
    {
        echo ""
        echo "# HDMI Configuration (configured by HAL)"
        echo "hdmi_force_hotplug=${force_hotplug}"
        if [[ $hdmi_group -ne 0 ]]; then
            echo "hdmi_group=${hdmi_group}"
        fi
        if [[ $hdmi_mode -ne 0 ]]; then
            echo "hdmi_mode=${hdmi_mode}"
        fi
    } >> "$boot_config"
    
    log_info "HAL Display: HDMI options configured"
    return 0
}

# Check if display manager is needed
hal_display_needs_dm() {
    # Check if GUI packages are installed
    if [[ "${EDITION:-minimal}" == "minimal" ]]; then
        return 1  # No DM needed
    fi
    
    return 0  # DM needed for GUI
}

# Export functions
export -f hal_display_detect
export -f hal_display_get_resolution
export -f hal_display_configure
export -f hal_display_set_hdmi_options
export -f hal_display_needs_dm

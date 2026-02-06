#!/bin/bash
# Plugin: INA3221 Triple-Channel Power Monitor
# Phase: cyberpentester-hardware

# shellcheck disable=SC2034
PLUGIN_NAME="INA3221 Power Monitor"
PLUGIN_DESCRIPTION="Configures INA3221 triple-channel power monitor for battery management"
PLUGIN_PHASE="cyberpentester-hardware"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    # Check if I2C is enabled
    if [[ ! -e /dev/i2c-1 ]]; then
        log_warn "I2C not enabled - INA3221 will not be available"
        return 1
    fi
    
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Configuring INA3221 power monitor..."
    
    # Install required packages
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm python-pip i2c-tools; then
        log_error "Failed to install INA3221 dependencies"
        return 1
    fi
    
    # Install Python I2C library
    systemd-nspawn -D "$ROOT_MOUNT" pip install --break-system-packages smbus2 ina3221 || true
    
    # Create udev rule for I2C access
    cat > "$ROOT_MOUNT/etc/udev/rules.d/99-i2c.rules" <<'EOF'
# Allow users in i2c group to access I2C devices
KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
EOF
    
    # Create i2c group
    systemd-nspawn -D "$ROOT_MOUNT" groupadd -f i2c
    
    # Enable I2C kernel module
    if [[ ! -f "$ROOT_MOUNT/etc/modules-load.d/i2c.conf" ]]; then
        cat > "$ROOT_MOUNT/etc/modules-load.d/i2c.conf" <<'EOF'
i2c-dev
i2c-bcm2835
EOF
    fi
    
    # Create systemd service for power monitoring
    cat > "$ROOT_MOUNT/etc/systemd/system/ina3221-monitor.service" <<'EOF'
[Unit]
Description=INA3221 Power Monitor
After=multi-user.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/battery-monitor.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "INA3221 power monitor configuration complete"
    log_info "Battery monitoring service: battery-monitor.py (will be installed by cyberdeck-scripts plugin)"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

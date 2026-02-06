#!/bin/bash
# Plugin: nRF51422 BLE Sniffer Setup
# Phase: cyberpentester-hardware

# shellcheck disable=SC2034
PLUGIN_NAME="nRF51422 BLE Sniffer"
PLUGIN_DESCRIPTION="Configures Nordic nRF51422 dongles for BLE sniffing and attacks"
PLUGIN_PHASE="cyberpentester-hardware"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    # Always return success - optional hardware
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Configuring nRF51422 BLE sniffer support..."
    
    # Install required packages
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm python-pip python-pyserial wireshark-qt; then
        log_error "Failed to install nRF sniffer dependencies"
        return 1
    fi
    
    # Install btlejack for BLE attacks
    systemd-nspawn -D "$ROOT_MOUNT" pip install --break-system-packages btlejack || true
    
    # Create udev rules for nRF devices
    cat > "$ROOT_MOUNT/etc/udev/rules.d/99-nrf.rules" <<'EOF'
# Nordic Semiconductor nRF51/nRF52 dongles
SUBSYSTEM=="usb", ATTRS{idVendor}=="1915", MODE="0666", GROUP="plugdev"

# Allow access to USB serial devices
KERNEL=="ttyACM[0-9]*", MODE="0666", GROUP="dialout"
KERNEL=="ttyUSB[0-9]*", MODE="0666", GROUP="dialout"
EOF
    
    # Add user to required groups (will be done in user plugin)
    log_info "Note: User must be added to 'plugdev' and 'dialout' groups"
    
    # Create directory for firmware
    mkdir -p "$ROOT_MOUNT/opt/nrf-firmware"
    
    # Create firmware download script
    cat > "$ROOT_MOUNT/opt/nrf-firmware/README.txt" <<'EOF'
Nordic nRF51422 Firmware Files
==============================

To use nRF dongles for BLE sniffing with Wireshark:
1. Download nRF Sniffer from: https://www.nordicsemi.com/Products/Development-tools/nRF-Sniffer-for-Bluetooth-LE
2. Extract and place firmware files here
3. Use nrf-sniffer-setup.sh to flash firmware

For btlejack attacks:
- Install btlejack: pip install btlejack
- Flash btlejack firmware: btlejack -i
- Use btlejack commands for sniffing and attacks

Common nRF51422 addresses:
- Device 1: /dev/ttyACM0
- Device 2: /dev/ttyACM1
EOF
    
    log_info "nRF51422 BLE sniffer configuration complete"
    log_info "Firmware setup: Use /usr/local/bin/nrf-sniffer-setup.sh (will be installed by cyberdeck-scripts plugin)"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

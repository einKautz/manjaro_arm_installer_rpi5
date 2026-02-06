#!/bin/bash
# Plugin: BLE Tools
# Phase: cyberpentester-security

# shellcheck disable=SC2034
PLUGIN_NAME="BLE Tools"
PLUGIN_DESCRIPTION="Installs and configures Bluetooth Low Energy tools"
PLUGIN_PHASE="cyberpentester-security"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Installing BLE tools..."
    
    # Install BlueZ and tools
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm bluez bluez-utils bluez-tools python-pip; then
        log_error "Failed to install BLE packages"
        return 1
    fi
    
    # Install Python BLE libraries
    log_info "Installing Python BLE libraries..."
    systemd-nspawn -D "$ROOT_MOUNT" pip install --break-system-packages pybluez bleak bluepy || true
    
    # Enable Bluetooth service
    systemd-nspawn -D "$ROOT_MOUNT" systemctl enable bluetooth.service
    
    # Configure Bluetooth for BLE scanning
    cat > "$ROOT_MOUNT/etc/bluetooth/main.conf" <<'EOF'
[General]
# Enable privacy for BLE connections
Privacy = device

# Discoverable timeout (0 = always discoverable when enabled)
DiscoverableTimeout = 0

# Pairable timeout (0 = always pairable when enabled)
PairableTimeout = 0

# Enable experimental features (BLE privacy, etc.)
Experimental = true

[Policy]
# Automatically enable controllers
AutoEnable = true
EOF
    
    # Create BLE scanning helper scripts
    log_info "Creating BLE helper scripts..."
    
    # BLE scanner
    cat > "$ROOT_MOUNT/usr/local/bin/ble-scan-simple.sh" <<'EOF'
#!/bin/bash
# Simple BLE scanner using bluetoothctl

echo "Scanning for BLE devices (Ctrl+C to stop)..."
echo "================================================"

bluetoothctl power on
bluetoothctl scan on &
SCAN_PID=$!

# Trap Ctrl+C to stop scanning
trap "bluetoothctl scan off; kill $SCAN_PID 2>/dev/null; exit" INT

# Keep script running
while true; do
    sleep 1
done
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/ble-scan-simple.sh"
    
    # GATT enumeration helper
    cat > "$ROOT_MOUNT/usr/local/bin/ble-gatt-enum.sh" <<'EOF'
#!/bin/bash
# Enumerate GATT services and characteristics

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <BLE_MAC_ADDRESS>"
    echo "Example: $0 AA:BB:CC:DD:EE:FF"
    exit 1
fi

BLE_MAC="$1"

echo "Connecting to $BLE_MAC and enumerating GATT services..."
echo "================================================"

# Use gatttool to enumerate services
gatttool -b "$BLE_MAC" --primary

echo ""
echo "Enumerating characteristics..."
gatttool -b "$BLE_MAC" --characteristics

echo ""
echo "Done. Use gatttool -b $BLE_MAC -I for interactive mode"
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/ble-gatt-enum.sh"
    
    # HCI command helper
    cat > "$ROOT_MOUNT/usr/local/bin/ble-info.sh" <<'EOF'
#!/bin/bash
# Display Bluetooth/BLE adapter information

echo "Bluetooth Adapter Information"
echo "============================="
echo ""

# Show HCI devices
echo "HCI Devices:"
hciconfig -a
echo ""

# Show device features
echo "Bluetooth Features:"
hcitool dev
echo ""

# Show LE features
echo "LE Features:"
btmgmt info
echo ""

echo "To scan for BLE devices: ble-scan-simple.sh"
echo "To enumerate GATT: ble-gatt-enum.sh <MAC>"
echo "Interactive gatttool: gatttool -b <MAC> -I"
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/ble-info.sh"
    
    # Create udev rules for Bluetooth devices
    cat > "$ROOT_MOUNT/etc/udev/rules.d/99-bluetooth.rules" <<'EOF'
# Allow users in bluetooth group to access Bluetooth devices
KERNEL=="rfkill", SUBSYSTEM=="misc", MODE="0664", GROUP="bluetooth"
EOF
    
    # Create bluetooth group
    systemd-nspawn -D "$ROOT_MOUNT" groupadd -f bluetooth
    
    # Create BLE tools reference
    cat > "$ROOT_MOUNT/usr/local/share/ble-tools-reference.txt" <<'EOF'
BLE Tools Reference
===================

Basic Commands:
  hciconfig              - Configure Bluetooth devices
  hcitool                - HCI tool for Bluetooth
  bluetoothctl           - Interactive Bluetooth control
  gatttool               - GATT tool for BLE
  btmon                  - Bluetooth monitor

Scanning:
  ble-scan-simple.sh     - Simple BLE scanner
  hcitool lescan         - LE scan (deprecated but still works)
  bluetoothctl scan on   - Modern scanning method

GATT Operations:
  ble-gatt-enum.sh <MAC> - Enumerate services and characteristics
  gatttool -b <MAC> -I   - Interactive GATT tool

Advanced Tools (requires installation):
  btlejack               - BLE MITM and sniffing (needs nRF hardware)
  bettercap              - Network attack framework with BLE support
  gattacker              - BLE security testing tool

Python Libraries:
  pybluez                - Bluetooth library for Python
  bleak                  - Modern async BLE library
  bluepy                - BLE Python library

Notes:
- Use ble-recon.py for comprehensive BLE reconnaissance
- Use ble-mitm-attack.sh for BLE MITM attacks (requires nRF hardware)
- Always ensure proper authorization before testing
EOF
    
    log_info "BLE tools configuration complete"
    log_info "Helper scripts: ble-scan-simple.sh, ble-gatt-enum.sh, ble-info.sh"
    log_info "Advanced tools: /usr/local/bin/ble-recon.py, /usr/local/bin/ble-mitm-attack.sh"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

#!/bin/bash
# Plugin: Workflow Profiles
# Phase: cyberpentester-workflow

# shellcheck disable=SC2034
PLUGIN_NAME="Workflow Profiles"
PLUGIN_DESCRIPTION="Configures pentesting workflow profiles and quick-launch menus"
PLUGIN_PHASE="cyberpentester-workflow"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Configuring workflow profiles..."
    
    # Create workflow directory
    mkdir -p "$ROOT_MOUNT/opt/workflows"
    
    # WiFi Pentesting Workflow
    cat > "$ROOT_MOUNT/opt/workflows/wifi-pentesting.sh" <<'EOF'
#!/bin/bash
# WiFi Pentesting Workflow

echo "╔════════════════════════════════════════════╗"
echo "║     WiFi Pentesting Workflow              ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "1. Put adapter in monitor mode"
echo "2. Scan for networks"
echo "3. Capture handshake"
echo "4. Crack with wordlist"
echo "5. Return to managed mode"
echo ""

# Check for WiFi adapter
if ! iw dev | grep -q "wlan"; then
    echo "Error: No WiFi adapter detected"
    exit 1
fi

# Get adapter name (usually wlan1 for external)
ADAPTER=$(iw dev | grep Interface | tail -1 | awk '{print $2}')
echo "Using adapter: $ADAPTER"
echo ""

read -r -p "Continue? [y/N] " response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    exit 0
fi

# Step 1: Monitor mode
echo "Step 1: Enabling monitor mode..."
sudo wifi-mode.sh monitor "$ADAPTER"

# Step 2: Scan
echo "Step 2: Scanning for networks..."
echo "Press Ctrl+C after 30 seconds..."
sudo airodump-ng "${ADAPTER}"

# Step 3: Capture (requires manual target selection)
echo "Step 3: To capture handshake:"
echo "  sudo airodump-ng -c <channel> --bssid <BSSID> -w capture ${ADAPTER}"
echo ""
echo "Step 4: To crack:"
echo "  sudo aircrack-ng -w <wordlist> capture-01.cap"
echo ""
echo "Step 5: Return to managed mode:"
echo "  sudo wifi-mode.sh managed $ADAPTER"
EOF
    
    chmod +x "$ROOT_MOUNT/opt/workflows/wifi-pentesting.sh"
    
    # BLE Assessment Workflow
    cat > "$ROOT_MOUNT/opt/workflows/ble-assessment.sh" <<'EOF'
#!/bin/bash
# BLE Assessment Workflow

echo "╔════════════════════════════════════════════╗"
echo "║     BLE Assessment Workflow                ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "1. Enable Bluetooth"
echo "2. Scan for BLE devices"
echo "3. Enumerate GATT services"
echo "4. Test for vulnerabilities"
echo ""

# Check Bluetooth
if ! hciconfig | grep -q "UP RUNNING"; then
    echo "Enabling Bluetooth..."
    sudo hciconfig hci0 up
fi

# Run BLE reconnaissance
echo "Starting BLE reconnaissance..."
ble-recon.py --scan 60 --output /tmp/ble-scan-results.json

echo ""
echo "Scan complete. Results saved to: /tmp/ble-scan-results.json"
echo ""
echo "Next steps:"
echo "  - Review discovered devices"
echo "  - Enumerate GATT: ble-gatt-enum.sh <MAC>"
echo "  - Test for MITM: ble-mitm-attack.sh <MAC>"
EOF
    
    chmod +x "$ROOT_MOUNT/opt/workflows/ble-assessment.sh"
    
    # RF Analysis Workflow
    cat > "$ROOT_MOUNT/opt/workflows/rf-analysis.sh" <<'EOF'
#!/bin/bash
# RF Spectrum Analysis Workflow

echo "╔════════════════════════════════════════════╗"
echo "║     RF Spectrum Analysis Workflow          ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check for RTL-SDR
if ! lsusb | grep -q "Realtek.*DVB-T"; then
    echo "Error: RTL-SDR not detected"
    echo "Plug in RTL-SDR V4 and try again"
    exit 1
fi

echo "RTL-SDR detected!"
echo ""
echo "Available tools:"
echo "1. GQRX (GUI spectrum analyzer)"
echo "2. rtl_power (sweep spectrum)"
echo "3. dump1090 (ADS-B aircraft tracking)"
echo "4. multimon-ng (decode digital modes)"
echo "5. Custom scan (sdr-scan.py)"
echo ""

read -r -p "Select tool [1-5]: " choice

case $choice in
    1)
        echo "Launching GQRX..."
        gqrx &
        ;;
    2)
        echo "Sweeping 80-1000 MHz..."
        rtl_power -f 80M:1000M:1M -g 40 -i 1 -e 30m spectrum.csv
        echo "Results saved to: spectrum.csv"
        ;;
    3)
        echo "Starting ADS-B receiver..."
        dump1090 --interactive --net --gain -10
        ;;
    4)
        echo "Decoding POCSAG/FLEX..."
        rtl_fm -f 439.9875M -M fm -s 22050 | multimon-ng -t raw -a POCSAG512 -a FLEX -
        ;;
    5)
        echo "Running custom SDR scanner..."
        sdr-scan.py --start 80 --end 1000 --step 1
        ;;
    *)
        echo "Invalid selection"
        ;;
esac
EOF
    
    chmod +x "$ROOT_MOUNT/opt/workflows/rf-analysis.sh"
    
    # Create workflow launcher menu
    cat > "$ROOT_MOUNT/usr/local/bin/cyberdeckworkflow.sh" <<'EOF'
#!/bin/bash
# Cyberdeck Workflow Launcher

show_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║    Cyberdeck Pentesting Workflows         ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "1. WiFi Pentesting"
    echo "2. BLE Assessment"
    echo "3. RF Spectrum Analysis"
    echo "4. IoT Device Testing"
    echo "5. Hardware Reverse Engineering"
    echo ""
    echo "6. System Status"
    echo "7. Battery Monitor"
    echo ""
    echo "0. Exit"
    echo ""
}

run_workflow() {
    case $1 in
        1)
            /opt/workflows/wifi-pentesting.sh
            ;;
        2)
            /opt/workflows/ble-assessment.sh
            ;;
        3)
            /opt/workflows/rf-analysis.sh
            ;;
        4)
            echo "IoT Testing workflow - Coming soon"
            echo "Tools: mosquitto, coap-cli, nmap, zigbee2mqtt"
            ;;
        5)
            echo "Hardware RE workflow - Coming soon"
            echo "Tools: openocd, minicom, binwalk, ghidra"
            ;;
        6)
            cyberdeck-status.sh
            ;;
        7)
            battery-monitor.py
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

while true; do
    show_menu
    read -r -p "Select workflow: " choice
    run_workflow "$choice"
    echo ""
    read -r -p "Press Enter to continue..."
done
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/cyberdeck-workflow.sh"
    
    # Create i3 launcher binding
    mkdir -p "$ROOT_MOUNT/etc/skel/.config/i3"
    cat > "$ROOT_MOUNT/etc/skel/.config/i3/config.d/cyberdeck.conf" <<'EOF'
# Cyberdeck workflow launcher binding
bindsym $mod+Shift+p exec alacritty -e cyberdeck-workflow.sh
EOF
    
    log_info "Workflow profiles configuration complete"
    log_info "Launch workflows: cyberdeck-workflow.sh or Mod+Shift+P in i3"
    log_info "Individual workflows: /opt/workflows/*.sh"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

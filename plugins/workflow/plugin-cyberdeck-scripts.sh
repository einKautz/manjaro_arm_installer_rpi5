#!/bin/bash
# Plugin: Cyberdeck Scripts
# Phase: cyberpentester-workflow

# shellcheck disable=SC2034
PLUGIN_NAME="Cyberdeck Scripts"
PLUGIN_DESCRIPTION="Installs cyberdeck automation and utility scripts"
PLUGIN_PHASE="cyberpentester-workflow"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Installing cyberdeck automation scripts..."
    
    # Copy all scripts from scripts/ directory to /usr/local/bin/
    local SCRIPT_DIR
    SCRIPT_DIR="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/scripts"
    
    if [[ -d "$SCRIPT_DIR" ]]; then
        log_info "Copying scripts from $SCRIPT_DIR..."
        
        # Create target directory
        mkdir -p "$ROOT_MOUNT/usr/local/bin"
        
        # Copy all scripts
        find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "*.py" \) -exec cp {} "$ROOT_MOUNT/usr/local/bin/" \;
        
        # Make all scripts executable
        chmod +x "$ROOT_MOUNT/usr/local/bin"/*.sh "$ROOT_MOUNT/usr/local/bin"/*.py 2>/dev/null || true
        
        log_info "Scripts installed to /usr/local/bin/"
    else
        log_warn "Scripts directory not found: $SCRIPT_DIR"
        log_warn "Scripts will need to be installed manually"
    fi
    
    # Create script reference guide
    cat > "$ROOT_MOUNT/usr/local/share/cyberdeck-scripts-reference.txt" <<'EOF'
Cyberdeck Automation Scripts
============================

Battery & Power:
  battery-monitor.py           - Real-time INA3221 power monitoring dashboard
  
WiFi Tools:
  wifi-mode.sh                 - Switch between managed and monitor mode
  antenna-test.sh              - Test WiFi adapter signal strength

SDR Tools:
  sdr-scan.py                  - RF spectrum scanning with RTL-SDR

BLE Tools:
  ble-recon.py                 - Comprehensive BLE reconnaissance
  ble-mitm-attack.sh           - Automated BLE MITM attacks
  nrf-sniffer-setup.sh         - nRF51422 firmware management

System Utilities:
  cyberdeck-status.sh          - System status dashboard
  usb-device-monitor.sh        - USB hotplug monitoring

Usage:
  Most scripts include --help for detailed usage
  Run from any terminal: /usr/local/bin/<script-name>
  Or add /usr/local/bin to PATH (already done)

Examples:
  wifi-mode.sh monitor wlan1
  ble-recon.py --scan 30
  battery-monitor.py --interval 5
  cyberdeck-status.sh
EOF
    
    log_info "Cyberdeck scripts installation complete"
    log_info "Scripts available in: /usr/local/bin/"
    log_info "Reference: /usr/local/share/cyberdeck-scripts-reference.txt"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

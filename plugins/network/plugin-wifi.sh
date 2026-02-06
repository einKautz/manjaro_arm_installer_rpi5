#!/usr/bin/env bash
#
# Wi-Fi Network Configuration Plugin
# Provides Wi-Fi scanning, connection, and testing capabilities
#

PLUGIN_NAME="wifi"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("network" "config")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Global Wi-Fi state
WIFI_SSID=""
WIFI_PASSWORD=""
WIFI_CONNECTED=false

# Network phase: Setup Wi-Fi during installation
plugin_run_network() {
    log_info "Wi-Fi Plugin: Network configuration phase"
    log_set_phase "network-wifi"
    
    # This would typically be called interactively
    # For plugin system, we just ensure NetworkManager is available
    if ! _check_network_manager; then
        log_warn "NetworkManager not available, skipping Wi-Fi setup"
        return 0
    fi
    
    log_info "NetworkManager available for Wi-Fi configuration"
    return 0
}

# Config phase: Write Wi-Fi configuration to installed system
plugin_run_config() {
    log_info "Wi-Fi Plugin: Writing configuration to installed system"
    log_set_phase "config-wifi"
    
    : "${TMPDIR:=/tmp/manjaro-installer}"
    
    if [[ -z "${WIFI_SSID}" ]]; then
        log_info "No Wi-Fi SSID configured, skipping"
        return 0
    fi
    
    _setup_wifi_on_target || {
        log_error "Failed to configure Wi-Fi on target system"
        return 1
    }
    
    log_info "Wi-Fi configuration written to target system"
    return 0
}

# Check if NetworkManager is available
_check_network_manager() {
    if ! command -v nmcli &>/dev/null; then
        log_error "NetworkManager (nmcli) not found"
        return 1
    fi
    
    if ! systemctl is-active --quiet NetworkManager; then
        log_info "Starting NetworkManager service"
        systemctl start NetworkManager 2>/dev/null || true
        sleep 2
    fi
    
    return 0
}

# Scan for available Wi-Fi networks
wifi_scan() {
    log_info "Scanning for Wi-Fi networks"
    
    if ! _check_network_manager; then
        return 1
    fi
    
    # Request fresh scan
    nmcli dev wifi rescan 2>/dev/null || true
    sleep 3
    
    # Get sorted list of networks
    nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | \
        grep -v '^--' | \
        grep -v '^$' | \
        sort -t: -k2 -rn | \
        awk -F: '!seen[$1]++ {print $1 ":" $2 ":" $3}'
}

# Connect to Wi-Fi network
wifi_connect() {
    local ssid="$1"
    local password="$2"
    
    log_info "Connecting to Wi-Fi: ${ssid}"
    
    local result
    if [[ -n "${password}" ]]; then
        nmcli dev wifi connect "${ssid}" password "${password}" 2>&1
        result=$?
    else
        nmcli dev wifi connect "${ssid}" 2>&1
        result=$?
    fi
    
    if [[ ${result} -eq 0 ]]; then
        WIFI_SSID="${ssid}"
        WIFI_PASSWORD="${password}"
        WIFI_CONNECTED=true
        log_info "Successfully connected to ${ssid}"
        return 0
    else
        WIFI_CONNECTED=false
        log_error "Failed to connect to ${ssid}"
        return 1
    fi
}

# Test Internet connectivity
wifi_test_internet() {
    log_info "Testing Internet connectivity"
    
    if ping -c 3 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log_info "Internet connectivity confirmed"
        return 0
    else
        log_warn "No Internet connectivity detected"
        return 1
    fi
}

# Write Wi-Fi configuration to target system
_setup_wifi_on_target() {
    local root_dir="${TMPDIR}/root"
    
    log_info "Writing NetworkManager Wi-Fi configuration"
    
    mkdir -p "${root_dir}/etc/NetworkManager/system-connections"
    
    # Determine connection file based on security
    local conn_file="${root_dir}/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"
    
    if [[ -n "${WIFI_PASSWORD}" ]]; then
        # Secured network
        cat > "${conn_file}" <<EOF
[connection]
id=${WIFI_SSID}
uuid=$(uuidgen)
type=wifi
autoconnect=true
permissions=

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF
    else
        # Open network
        cat > "${conn_file}" <<EOF
[connection]
id=${WIFI_SSID}
uuid=$(uuidgen)
type=wifi
autoconnect=true
permissions=

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF
    fi
    
    # Set proper permissions
    chmod 600 "${conn_file}"
    
    log_info "Wi-Fi configuration written to ${conn_file}"
    return 0
}

# Export functions for use by installer
export -f wifi_scan
export -f wifi_connect
export -f wifi_test_internet

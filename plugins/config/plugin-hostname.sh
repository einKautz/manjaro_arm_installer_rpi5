#!/usr/bin/env bash
#
# Plugin: Hostname Configuration
# Sets system hostname
#

PLUGIN_NAME="hostname"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("config")

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Set hostname
hostname_set() {
    local hostname="${1:-manjaro-arm}"
    
    log_info "Hostname: Setting hostname to '$hostname'"
    
    # Validate hostname (alphanumeric and hyphens only)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "Hostname: Invalid hostname '$hostname' (use alphanumeric and hyphens only)"
        return 1
    fi
    
    # Set hostname in /etc/hostname
    echo "$hostname" > "${MOUNT_POINT}/etc/hostname"
    log_info "Hostname: Written to /etc/hostname"
    
    # Configure /etc/hosts
    cat > "${MOUNT_POINT}/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    log_info "Hostname: Configured /etc/hosts"
    
    return 0
}

# Export helper function
export -f hostname_set

plugin_run_config() {
    log_set_phase "hostname-config"
    log_info "Hostname: Configuring system hostname"
    
    # Use SYSTEM_HOSTNAME if set, otherwise default
    hostname_set "${SYSTEM_HOSTNAME:-manjaro-pi5}"
    
    log_info "Hostname: Configuration complete"
    return 0
}

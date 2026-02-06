#!/usr/bin/env bash
#
# Plugin: User Creation
# Creates user account with proper groups and sudo access
#

PLUGIN_NAME="user"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("config")

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Create user in chroot
user_create() {
    local username="$1"
    local password="$2"
    
    if [[ -z "$username" ]]; then
        log_error "User: Username is required"
        return 1
    fi
    
    log_info "User: Creating user '$username'"
    
    # Create user with home directory
    if systemd-nspawn -D "${MOUNT_POINT}" useradd -m -G wheel,audio,video,optical,storage,power,lp,network,input "$username"; then
        log_info "User: User '$username' created successfully"
    else
        log_error "User: Failed to create user '$username'"
        return 1
    fi
    
    # Set password if provided
    if [[ -n "$password" ]]; then
        if echo "$username:$password" | systemd-nspawn -D "${MOUNT_POINT}" chpasswd; then
            log_info "User: Password set for '$username'"
        else
            log_error "User: Failed to set password for '$username'"
            return 1
        fi
    fi
    
    # Configure sudo access
    local sudoers_file="${MOUNT_POINT}/etc/sudoers.d/${username}"
    echo "$username ALL=(ALL) ALL" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
    log_info "User: Sudo access granted to '$username'"
    
    return 0
}

# Export helper function
export -f user_create

plugin_run_config() {
    log_set_phase "user-config"
    log_info "User: User creation plugin ready"
    
    # Check if USER_NAME and USER_PASSWORD are set
    if [[ -n "${USER_NAME:-}" ]]; then
        user_create "${USER_NAME}" "${USER_PASSWORD:-}"
    else
        log_info "User: No user specified (USER_NAME not set), skipping"
    fi
    
    return 0
}

#!/usr/bin/env bash
#
# Plugin: Locale Configuration
# Sets up system locale and timezone
#

PLUGIN_NAME="locale"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("config")

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Set locale
locale_set() {
    local locale="${1:-en_US.UTF-8}"
    
    log_info "Locale: Setting locale to $locale"
    
    # Uncomment locale in locale.gen
    if [[ -f "${MOUNT_POINT}/etc/locale.gen" ]]; then
        sed -i "s/^#${locale}/${locale}/" "${MOUNT_POINT}/etc/locale.gen"
        log_info "Locale: Enabled $locale in locale.gen"
    fi
    
    # Generate locales
    if systemd-nspawn -D "${MOUNT_POINT}" locale-gen; then
        log_info "Locale: Locales generated successfully"
    else
        log_warn "Locale: Failed to generate locales"
    fi
    
    # Set LANG in locale.conf
    echo "LANG=${locale}" > "${MOUNT_POINT}/etc/locale.conf"
    log_info "Locale: Set LANG=${locale} in locale.conf"
    
    return 0
}

# Set timezone
timezone_set() {
    local timezone="${1:-UTC}"
    
    log_info "Locale: Setting timezone to $timezone"
    
    # Create symlink to timezone
    if systemd-nspawn -D "${MOUNT_POINT}" ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime; then
        log_info "Locale: Timezone set to $timezone"
    else
        log_warn "Locale: Failed to set timezone"
    fi
    
    # Set timezone in timedatectl (will be applied on first boot)
    if [[ -d "${MOUNT_POINT}/etc" ]]; then
        echo "$timezone" > "${MOUNT_POINT}/etc/timezone"
        log_info "Locale: Saved timezone to /etc/timezone"
    fi
    
    return 0
}

# Export helper functions
export -f locale_set
export -f timezone_set

plugin_run_config() {
    log_set_phase "locale-config"
    log_info "Locale: Configuring system locale and timezone"
    
    # Set locale (use SYSTEM_LOCALE if set, otherwise default)
    locale_set "${SYSTEM_LOCALE:-en_US.UTF-8}"
    
    # Set timezone (use SYSTEM_TIMEZONE if set, otherwise default)
    timezone_set "${SYSTEM_TIMEZONE:-UTC}"
    
    log_info "Locale: Configuration complete"
    return 0
}

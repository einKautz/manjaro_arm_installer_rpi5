#!/usr/bin/env bash
#
# Plugin: Package Installation
# Installs edition-specific packages
#

PLUGIN_NAME="packages"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("config")

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Install packages in chroot
packages_install() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "Packages: No packages specified"
        return 0
    fi
    
    log_info "Packages: Installing ${#packages[@]} package(s): ${packages[*]}"
    
    # Update package database first
    log_info "Packages: Updating package database"
    if ! systemd-nspawn -D "${MOUNT_POINT}" pacman -Sy --noconfirm; then
        log_error "Packages: Failed to update package database"
        return 1
    fi
    
    # Install packages
    if systemd-nspawn -D "${MOUNT_POINT}" pacman -S --noconfirm --needed "${packages[@]}"; then
        log_info "Packages: Successfully installed ${#packages[@]} package(s)"
        return 0
    else
        log_error "Packages: Failed to install packages"
        return 1
    fi
}

# Export helper function
export -f packages_install

plugin_run_config() {
    log_set_phase "packages-config"
    log_info "Packages: Package installation plugin ready"
    
    # Define edition-specific packages
    local base_packages=(
        "base-devel"
        "wget"
        "curl"
        "git"
        "nano"
        "vim"
        "htop"
        "neofetch"
    )
    
    local xfce_packages=(
        "xorg-server"
        "xfce4"
        "xfce4-goodies"
        "lightdm"
        "lightdm-gtk-greeter"
        "firefox"
        "thunar-archive-plugin"
        "file-roller"
    )
    
    local kde_packages=(
        "xorg-server"
        "plasma-desktop"
        "plasma-nm"
        "plasma-pa"
        "konsole"
        "dolphin"
        "kate"
        "sddm"
        "firefox"
    )
    
    # Install based on EDITION variable
    case "${EDITION:-minimal}" in
        minimal)
            log_info "Packages: Installing minimal base packages"
            packages_install "${base_packages[@]}"
            ;;
        xfce)
            log_info "Packages: Installing Xfce desktop environment"
            packages_install "${base_packages[@]}" "${xfce_packages[@]}"
            
            # Enable display manager
            systemd-nspawn -D "${MOUNT_POINT}" systemctl enable lightdm
            log_info "Packages: Enabled LightDM display manager"
            ;;
        kde)
            log_info "Packages: Installing KDE Plasma desktop environment"
            packages_install "${base_packages[@]}" "${kde_packages[@]}"
            
            # Enable display manager
            systemd-nspawn -D "${MOUNT_POINT}" systemctl enable sddm
            log_info "Packages: Enabled SDDM display manager"
            ;;
        *)
            log_warn "Packages: Unknown edition '${EDITION}', installing minimal packages"
            packages_install "${base_packages[@]}"
            ;;
    esac
    
    # Install additional packages if EXTRA_PACKAGES is set
    if [[ -n "${EXTRA_PACKAGES:-}" ]]; then
        log_info "Packages: Installing additional packages: $EXTRA_PACKAGES"
        IFS=' ' read -ra extra_array <<< "$EXTRA_PACKAGES"
        packages_install "${extra_array[@]}"
    fi
    
    log_info "Packages: Configuration complete"
    return 0
}

#!/usr/bin/env bash
#
# Manjaro ARM Pi 5 Installer - Plugin-Based Architecture
# Version: 3.0 - Modular Plugin-Driven Installer
#
# Major changes in v3.0:
# - Refactored to use plugin architecture
# - Reduced main script from 1724 → ~500 lines
# - Modular, extensible design
# - All functionality now in plugins
# - Maintains backward compatibility with v2.6
#
set -euo pipefail

# Check for bash
if [ -z "${BASH_VERSION-}" ]; then
    echo "Please run this installer with bash:"
    echo "  bash $0"
    exit 1
fi

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/plugins.sh"

# Global configuration
export ARCH="aarch64"
export BRANCH="unstable"
export DEVICE="rpi5"
export TMPDIR="/tmp/manjaro-installer"
export NSPAWN="systemd-nspawn -D"

# Installation state
export EDITION=""
export DISPLAY_MANAGER=""
export SDCARD=""
export BOOTMODE=""
export USER_NAME=""
export USER_PASSWORD=""
export ROOT_MODE=""
export ROOT_PASSWORD=""
export OPTIMIZATIONS=""
export WIFI_SSID=""
export WIFI_PASSWORD=""
export WIFI_CONNECTED=false
export MOUNT_POINT="${TMPDIR}/root"
export SYSTEM_HOSTNAME="manjaro-pi5"
export SYSTEM_LOCALE="en_US.UTF-8"
export SYSTEM_TIMEZONE="UTC"
export EXTRA_PACKAGES=""

# Pi 5 boot partition sources
PI5_IMAGE_URL="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/Manjaro-ARM-minimal-rpi5-latest.img.xz"
PI5_BOOT_TARBALL="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/boot-rpi5.tar.gz"

# =============================================================================
# Dependency Checks
# =============================================================================

check_dependencies() {
    log_set_phase "dependency-check"
    log_info "Checking required dependencies"
    
    local missing_deps=()
    
    for cmd in dialog parted mkfs.vfat mkfs.ext4 wget git bsdtar systemd-nspawn; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_deps[*]}"
        echo "Error: Required commands not found: ${missing_deps[*]}"
        echo "Please install the required packages and try again."
        exit 1
    fi
    
    log_info "All dependencies satisfied"
    return 0
}

# =============================================================================
# Dialog wrapper
# =============================================================================

dialog_input() {
    local title="$1"
    shift
    local result
    result=$(dialog --clear \
        --title "$title" \
        --ok-label "Next" \
        --cancel-label "Back" \
        "$@" \
        2>&1 >/dev/tty) || return 1
    echo "$result"
}

# =============================================================================
# UI Functions
# =============================================================================

ui_select_edition() {
    local edition
    edition=$(dialog_input "Select Edition" \
        --menu "Choose Manjaro ARM edition:" 15 60 3 \
        "minimal" "Minimal (no GUI)" \
        "xfce" "Xfce Desktop" \
        "kde" "KDE Plasma Desktop") || exit 0
    
    export EDITION="$edition"
    log_info "Selected edition: $EDITION"
}

ui_select_display_manager() {
    if [[ ! "$EDITION" =~ ^(xfce|kde) ]]; then
        return 0  # Skip for minimal
    fi
    
    local dm
    if [[ "$EDITION" == "xfce" ]]; then
        dm="lightdm"
    else
        dm="sddm"
    fi
    
    export DISPLAY_MANAGER="$dm"
    log_info "Display manager: $DISPLAY_MANAGER"
}

ui_select_sdcard() {
    local disks
    mapfile -t disks < <(lsblk -nd -o NAME,SIZE,MODEL | grep -E "sd|mmcblk")
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        dialog --title "Error" --msgbox "No storage devices found!" 8 50
        exit 1
    fi
    
    local menu_items=()
    for disk in "${disks[@]}"; do
        local name size model
        read -r name size model <<< "$disk"
        menu_items+=("/dev/$name" "$size $model")
    done
    
    local sdcard
    sdcard=$(dialog_input "Select SD Card" \
        --menu "Choose target device:" 15 70 5 \
        "${menu_items[@]}") || exit 0
    
    export SDCARD="$sdcard"
    log_info "Selected device: $SDCARD"
}

ui_select_bootmode() {
    export BOOTMODE="sdcard"  # Default for now
    log_info "Boot mode: $BOOTMODE"
}

ui_set_username() {
    local username
    username=$(dialog_input "Username" \
        --inputbox "Enter username for new user:" 8 50 "manjaro") || exit 0
    
    export USER_NAME="$username"
    log_info "Username: $USER_NAME"
}

ui_set_password() {
    local password
    password=$(dialog_input "User Password" \
        --passwordbox "Enter password for user $USER_NAME:" 8 50) || exit 0
    
    export USER_PASSWORD="$password"
    log_info "User password set"
}

ui_set_root_mode() {
    local mode
    mode=$(dialog_input "Root Account" \
        --menu "Configure root account:" 12 60 3 \
        "disable" "Disable root login (use sudo)" \
        "setpw" "Set root password" \
        "sshkey" "SSH key only") || exit 0
    
    export ROOT_MODE="$mode"
    log_info "Root mode: $ROOT_MODE"
}

ui_set_root_password() {
    local password
    password=$(dialog_input "Root Password" \
        --passwordbox "Enter password for root:" 8 50) || exit 0
    
    export ROOT_PASSWORD="$password"
    log_info "Root password set"
}

ui_network_settings_menu() {
    if ! command -v nmcli &>/dev/null; then
        log_warn "NetworkManager not found, skipping Wi-Fi setup"
        return 0
    fi
    
    local choice
    choice=$(dialog_input "Network Settings" \
        --menu "Configure network (optional):" 12 60 3 \
        "skip" "Skip network configuration" \
        "wifi" "Configure Wi-Fi now" \
        "ethernet" "Use Ethernet (default)") || return 0
    
    case "$choice" in
        wifi)
            if command -v wifi_scan &>/dev/null && command -v wifi_connect &>/dev/null; then
                # Wi-Fi plugin functions are available
                local ssid
                ssid=$(wifi_scan | dialog --menu "Select Wi-Fi Network:" 20 60 10 --file - 2>&1 >/dev/tty) || return 0
                
                if [[ -n "$ssid" ]]; then
                    local password
                    password=$(dialog_input "Wi-Fi Password" \
                        --passwordbox "Enter password for $ssid:" 8 50) || return 0
                    
                    export WIFI_SSID="$ssid"
                    export WIFI_PASSWORD="$password"
                    
                    if wifi_connect "$ssid" "$password"; then
                        export WIFI_CONNECTED=true
                        log_info "Connected to Wi-Fi: $ssid"
                    fi
                fi
            else
                log_warn "Wi-Fi plugin not loaded"
            fi
            ;;
        *)
            log_info "Skipping network configuration"
            ;;
    esac
}

ui_select_optimizations() {
    local opts
    opts=$(dialog_input "Optimizations" \
        --checklist "Select optimizations to apply:" 15 60 6 \
        "zram" "Compressed swap (ZRAM)" on \
        "sysctl" "Kernel parameter tuning" on \
        "fstrim" "Weekly SSD TRIM" on \
        "cpupower" "CPU frequency scaling" on \
        "gpu-mem" "GPU memory optimization" on \
        "journald" "Journal size limits" on) || exit 0
    
    export OPTIMIZATIONS="$opts"
    log_info "Selected optimizations: $OPTIMIZATIONS"
}

ui_confirm() {
    dialog --title "Confirm Installation" \
        --yesno "Ready to install:\n\nEdition: $EDITION\nDevice: $SDCARD\nUser: $USER_NAME\n\nWARNING: This will erase all data on $SDCARD!\n\nContinue?" 14 60 || exit 0
    
    log_info "Installation confirmed by user"
}

ui_progress() {
    local title="$1"
    local message="$2"
    log_info "$title: $message"
    dialog --title "$title" --infobox "$message\n\nPlease wait..." 8 60
    sleep 1
}

show_completion_message() {
    dialog --title "Installation Complete" \
        --msgbox "Manjaro ARM has been successfully installed!\n\nDevice: $SDCARD\nEdition: $EDITION\nUser: $USER_NAME\n\nYou can now remove the SD card and boot your Raspberry Pi 5." 12 60
    
    log_info "Installation completed successfully"
}

# =============================================================================
# Core Installation Functions
# =============================================================================

partition_and_format_sdcard() {
    log_set_phase "partitioning"
    log_info "Partitioning device: $SDCARD"
    
    # Unmount any mounted partitions
    umount "${SDCARD}"* 2>/dev/null || true
    
    # Create partition table
    parted -s "$SDCARD" mklabel msdos
    parted -s "$SDCARD" mkpart primary fat32 1MiB 513MiB
    parted -s "$SDCARD" set 1 boot on
    parted -s "$SDCARD" mkpart primary ext4 513MiB 100%
    
    # Wait for partitions
    sleep 2
    partprobe "$SDCARD"
    sleep 2
    
    # Determine partition names
    if [[ "$SDCARD" =~ mmcblk ]]; then
        BOOT_PARTITION="${SDCARD}p1"
        ROOT_PARTITION="${SDCARD}p2"
    else
        BOOT_PARTITION="${SDCARD}1"
        ROOT_PARTITION="${SDCARD}2"
    fi
    
    export BOOT_PARTITION ROOT_PARTITION
    
    # Format partitions
    log_info "Formatting boot partition: $BOOT_PARTITION"
    mkfs.vfat -F 32 -n BOOT "$BOOT_PARTITION"
    
    log_info "Formatting root partition: $ROOT_PARTITION"
    mkfs.ext4 -F -L ROOT "$ROOT_PARTITION"
    
    log_info "Partitioning and formatting complete"
}

mount_root_partition() {
    log_set_phase "mounting"
    mkdir -p "$MOUNT_POINT"
    mount "$ROOT_PARTITION" "$MOUNT_POINT"
    log_info "Mounted root partition: $ROOT_PARTITION → $MOUNT_POINT"
}

mount_boot_partition() {
    mkdir -p "$MOUNT_POINT/boot"
    mount "$BOOT_PARTITION" "$MOUNT_POINT/boot"
    log_info "Mounted boot partition: $BOOT_PARTITION → $MOUNT_POINT/boot"
}

installer_get_armprofiles() {
    log_set_phase "armprofiles"
    log_info "Cloning ARM profiles repository"
    
    local profiles_dir="${TMPDIR}/arm-profiles"
    
    if [[ -d "$profiles_dir" ]]; then
        rm -rf "$profiles_dir"
    fi
    
    git clone --depth 1 https://gitlab.manjaro.org/manjaro-arm/applications/arm-profiles.git "$profiles_dir"
    log_info "ARM profiles cloned"
}

download_generic_rootfs() {
    log_set_phase "download"
    local rootfs_url="https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-${ARCH}-latest.tar.gz"
    local rootfs_file="${TMPDIR}/rootfs.tar.gz"
    
    log_info "Downloading rootfs from: $rootfs_url"
    
    if [[ -f "$rootfs_file" ]]; then
        log_info "Rootfs already downloaded, skipping"
        return 0
    fi
    
    wget -O "$rootfs_file" "$rootfs_url"
    log_info "Rootfs downloaded"
}

extract_generic_rootfs() {
    log_set_phase "extract"
    local rootfs_file="${TMPDIR}/rootfs.tar.gz"
    
    log_info "Extracting rootfs to $MOUNT_POINT"
    bsdtar -xpf "$rootfs_file" -C "$MOUNT_POINT"
    log_info "Rootfs extraction complete"
}

setup_keyrings_and_mirrors() {
    log_set_phase "keyrings"
    log_info "Setting up package keyrings and mirrors"
    
    # Initialize pacman keyring
    $NSPAWN "$MOUNT_POINT" pacman-key --init
    $NSPAWN "$MOUNT_POINT" pacman-key --populate archlinuxarm manjaro
    
    # Update mirrors
    $NSPAWN "$MOUNT_POINT" pacman -Sy --noconfirm
    
    log_info "Keyrings and mirrors configured"
}

install_pi5_base_system() {
    log_set_phase "base-system"
    log_info "Installing Pi 5 base system packages"
    
    local base_packages=(
        linux-rpi5
        linux-rpi5-headers
        raspberrypi-bootloader-x
        raspberrypi-firmware
        firmware-raspberrypi
    )
    
    $NSPAWN "$MOUNT_POINT" pacman -S --noconfirm --needed "${base_packages[@]}"
    log_info "Pi 5 base system installed"
}

configure_boot_files() {
    log_set_phase "boot-config"
    log_info "Configuring boot files"
    
    local boot_config="${MOUNT_POINT}/boot/config.txt"
    
    if [[ ! -f "$boot_config" ]]; then
        log_warn "config.txt not found, creating"
        cat > "$boot_config" << 'EOF'
# Raspberry Pi 5 Configuration
arm_64bit=1
kernel=kernel8.img

# Enable VC4 graphics
dtoverlay=vc4-kms-v3d

# Audio
dtparam=audio=on

# HDMI
hdmi_force_hotplug=1
EOF
    fi
    
    # cmdline.txt
    local cmdline="${MOUNT_POINT}/boot/cmdline.txt"
    echo "root=LABEL=ROOT rootfstype=ext4 rootwait console=tty1 console=serial0,115200" > "$cmdline"
    
    log_info "Boot configuration complete"
}

install_pi5_hardware_support() {
    log_set_phase "hardware"
    log_info "Installing Pi 5 hardware support packages"
    
    local hw_packages=(
        rpi5-eeprom
    )
    
    $NSPAWN "$MOUNT_POINT" pacman -S --noconfirm --needed "${hw_packages[@]}" || true
    log_info "Hardware support installed"
}

install_edition_packages() {
    log_set_phase "edition"
    log_info "Installing edition packages will be handled by packages plugin"
    # This is now handled by the packages plugin
}

setup_network() {
    log_set_phase "network-config"
    log_info "Network configuration will be handled by wifi plugin"
    # This is now handled by the wifi plugin
}

setup_display_manager() {
    log_set_phase "display-manager"
    log_info "Display manager setup is handled by packages plugin"
    # This is now handled by the packages plugin
}

cleanup_and_unmount() {
    log_set_phase "cleanup"
    log_info "Cleaning up and unmounting"
    
    sync
    
    umount "$MOUNT_POINT/boot" 2>/dev/null || true
    umount "$MOUNT_POINT" 2>/dev/null || true
    
    log_info "Cleanup complete"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Initialize logging
    mkdir -p "$TMPDIR"
    log_info "=== Manjaro ARM Pi 5 Installer v3.0 Started ==="
    log_set_phase "initialization"
    
    # Check dependencies
    check_dependencies
    
    # Initialize plugin system
    log_info "Initializing plugin system"
    plugin_init
    
    # UI Flow - Gather user input
    ui_select_edition
    ui_network_settings_menu
    ui_select_display_manager
    ui_select_sdcard
    ui_select_bootmode
    ui_set_username
    ui_set_password
    ui_set_root_mode
    if [[ "$ROOT_MODE" == "setpw" ]]; then
        ui_set_root_password
    fi
    ui_select_optimizations
    ui_confirm
    
    # === Installation Steps ===
    
    # Partitioning and mounting
    ui_progress "Partitioning" "Creating partitions on $SDCARD..."
    partition_and_format_sdcard
    
    ui_progress "Mounting" "Mounting partitions..."
    mount_root_partition
    mount_boot_partition
    
    # Download and extract
    ui_progress "Downloading" "Downloading base system..."
    installer_get_armprofiles
    download_generic_rootfs
    
    ui_progress "Extracting" "Extracting root filesystem..."
    extract_generic_rootfs
    
    # Package setup
    ui_progress "Package Keys" "Setting up package keyrings..."
    setup_keyrings_and_mirrors
    
    ui_progress "Base System" "Installing base Pi 5 system..."
    install_pi5_base_system
    
    # === Plugin Phases ===
    
    # Hardware detection
    ui_progress "Hardware" "Detecting hardware..."
    plugin_run_phase "detect"
    
    # Boot partition setup
    ui_progress "Boot Partition" "Setting up Pi 5 boot files..."
    plugin_run_phase "boot"
    configure_boot_files
    
    # Network configuration
    if [[ "$WIFI_CONNECTED" == true ]]; then
        ui_progress "Network" "Configuring network..."
        plugin_run_phase "network"
    fi
    
    # Hardware support
    ui_progress "Hardware Support" "Installing Pi 5 hardware support..."
    install_pi5_hardware_support
    
    # System configuration
    ui_progress "System Config" "Configuring system..."
    plugin_run_phase "config"
    
    # Post-install optimizations
    ui_progress "Optimizations" "Applying optimizations..."
    plugin_run_phase "post-install"
    
    # Diagnostics
    ui_progress "Verification" "Verifying installation..."
    plugin_run_phase "diagnostics"
    
    # Cleanup
    ui_progress "Finalizing" "Cleaning up..."
    cleanup_and_unmount
    
    # Completion
    show_completion_message
    
    log_info "=== Installation Complete ==="
}

# Run installer
main "$@"

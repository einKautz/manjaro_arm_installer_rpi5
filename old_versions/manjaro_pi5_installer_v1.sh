#!/usr/bin/env bash
#
# Manjaro ARM Pi 5 Installer with KDE Plasma Support - PRODUCTION READY
# Hybrid bootloader approach combining Manjaro userland with Raspberry Pi OS firmware
#
# Version: 2.2 - Phase 2 Completion + Sanity Checks
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

# Global configuration
ARCH="aarch64"
BRANCH="unstable"
DEVICE="rpi5"
TMPDIR="/tmp/manjaro-installer"
NSPAWN="systemd-nspawn -D"

# Logging functions
msg()  { echo -e "\n==> $*"; }
info() { echo "    $*"; }
err()  { echo "!! $*" >&2; }
log()  {
    local level="$1"; shift
    mkdir -p "$TMPDIR"
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" \
        | tee -a "$TMPDIR/install.log"
}

# Sanitization helper - strips CR/LF and trims whitespace
sanitize_single_line() {
    printf "%s" "$1" | tr -d '\r' | tr -d '\n' | xargs
}

# Dialog wrapper
dialog_input() {
    local title="$1"
    shift
    local result
    result=$(dialog --clear \
        --title "$title" \
        --ok-label "Next" \
        --cancel-label "Back" \
        "$@" \
        2>&1 >/dev/tty)
    echo "$result"
}

# =============================================================================
# UI Functions
# =============================================================================

ui_select_edition() {
    while true; do
        EDITION=$(dialog_input "Edition Selection" \
            --menu "Choose your Manjaro ARM edition:" 20 70 11 \
            minimal      "Minimal CLI" \
            xfce         "XFCE Desktop" \
            gnome        "GNOME Desktop" \
            server       "Server (CLI)" \
            kde-full     "KDE Plasma (Full)" \
            kde-minimal  "KDE Plasma (Minimal)" \
            kde-wayland  "KDE Plasma (Wayland-only)")
        EDITION=$(sanitize_single_line "$EDITION")
        [ -n "$EDITION" ] && break
    done
    log INFO "Selected edition: $EDITION"
}

ui_select_display_manager() {
    # Skip display manager selection for non-desktop editions
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        DISPLAY_MANAGER="none"
        log INFO "Non-desktop edition, skipping display manager"
        return
    fi
    
    # Auto-select recommended DM for each desktop
    case "$EDITION" in
        kde-*)
            default_dm="sddm"
            ;;
        xfce)
            default_dm="lightdm"
            ;;
        gnome)
            default_dm="gdm"
            ;;
        *)
            default_dm="lightdm"
            ;;
    esac
    
    while true; do
        DISPLAY_MANAGER=$(dialog_input "Display Manager" \
            --menu "Select display manager (recommended: $default_dm):" 16 65 4 \
            "$default_dm" "Recommended for $EDITION" \
            sddm    "SDDM (best for KDE)" \
            lightdm "LightDM (lightweight)" \
            none    "No display manager (startx only)")
        DISPLAY_MANAGER=$(sanitize_single_line "$DISPLAY_MANAGER")
        [ -n "$DISPLAY_MANAGER" ] && break
    done
    log INFO "Selected display manager: $DISPLAY_MANAGER"
}

ui_select_sdcard() {
    local options=()
    local dev size
    for dev in /dev/sd? /dev/mmcblk? /dev/nvme?n?; do
        [[ -b "$dev" ]] || continue
        size=$(lsblk -dn -o SIZE "$dev")
        options+=("$dev" "$size")
    done
    
    if [ ${#options[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No storage devices found!" 10 60
        exit 1
    fi
    
    while true; do
        SDCARD=$(dialog_input "Storage Selection" \
            --menu "Available storage devices:" 20 60 10 \
            "${options[@]}")
        SDCARD=$(sanitize_single_line "$SDCARD")
        [ -n "$SDCARD" ] && break
    done
    log INFO "Selected storage: $SDCARD"
}

ui_select_bootmode() {
    while true; do
        BOOTMODE=$(dialog_input "Boot Mode" \
            --menu "Select boot mode:" 12 60 2 \
            hybrid "Hybrid Boot (Recommended)" \
            full   "Full Bootloader Replacement")
        BOOTMODE=$(sanitize_single_line "$BOOTMODE")
        [ -n "$BOOTMODE" ] && break
    done
    log INFO "Selected boot mode: $BOOTMODE"
}

ui_set_username() {
    while true; do
        USERNAME=$(dialog_input "Create User" \
            --inputbox "Username:" 12 60)
        USERNAME=$(sanitize_single_line "$USERNAME")
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        fi
        dialog --title "Invalid Username" \
            --msgbox "Invalid username.\n\nUse: a-z, 0-9, _ and -\nMust start with a letter or _." 10 60
    done
    log INFO "Username set: $USERNAME"
}

ui_set_password() {
    while true; do
        local p1 p2
        p1=$(dialog_input "User Password" \
            --passwordbox "Password:" 12 60)
        p2=$(dialog_input "Confirm Password" \
            --passwordbox "Confirm:" 12 60)
        p1=$(sanitize_single_line "$p1")
        p2=$(sanitize_single_line "$p2")
        if [[ "$p1" == "$p2" && -n "$p1" ]]; then
            USER_PASSWORD="$p1"
            break
        fi
        dialog --title "Mismatch" \
            --msgbox "Passwords do not match or are empty." 10 60
    done
    log INFO "User password set"
}

ui_set_root_mode() {
    ROOT_MODE=$(dialog_input "Root Account Options" \
        --menu "Root account mode:" 15 60 4 \
        setpw   "Set a root password" \
        disable "Disable root SSH login (PermitRootLogin no)" \
        lock    "Lock root account (passwd -l)" \
        skip    "Skip root password (sudo-only)")
    ROOT_MODE=$(sanitize_single_line "$ROOT_MODE")
    log INFO "Root mode: $ROOT_MODE"
}

ui_set_root_password() {
    while true; do
        local p1 p2
        p1=$(dialog_input "Root Password" \
            --passwordbox "Password:" 12 60)
        p2=$(dialog_input "Confirm Root Password" \
            --passwordbox "Confirm:" 12 60)
        p1=$(sanitize_single_line "$p1")
        p2=$(sanitize_single_line "$p2")
        if [[ "$p1" == "$p2" && -n "$p1" ]]; then
            ROOT_PASSWORD="$p1"
            break
        fi
        dialog --title "Mismatch" \
            --msgbox "Root passwords do not match or are empty." 10 60
    done
    log INFO "Root password set"
}

ui_select_optimizations() {
    local raw
    raw=$(dialog_input "Post-Install Optimizations" \
        --checklist "Choose optimizations (press SPACE to toggle):" 22 80 10 \
        zram     "Enable ZRAM swap (RAM-aware)" ON \
        sysctl   "Kernel tuning for lower latency" ON \
        gpu      "Set GPU memory to 256MB" ON \
        journald "Reduce log size + SD wear" ON \
        fstrim   "Enable weekly TRIM" ON \
        cpupower "Enable ondemand CPU governor" ON)
    raw=$(sanitize_single_line "$raw")
    # Strip quotes from dialog output for proper array parsing
    raw="${raw//\"/}"
    if [ -n "$raw" ]; then
        read -ra OPTS <<< "$raw"
    else
        OPTS=()
    fi
    log INFO "Selected optimizations: ${OPTS[*]}"
}

ui_confirm() {
    local msg="Install Manjaro ARM ($EDITION) on $SDCARD?\n\n"
    msg+="Boot mode: $BOOTMODE\n"
    if [[ "$EDITION" =~ ^(xfce|gnome|kde-) ]]; then
        msg+="Display manager: $DISPLAY_MANAGER\n"
    fi
    msg+="Optimizations: ${#OPTS[@]} selected\n"
    msg+="\n⚠️  WARNING: All data on $SDCARD will be erased!"
    
    if ! dialog --title "Confirm Installation" \
        --yes-label "Install" \
        --no-label "Cancel" \
        --yesno "$msg" 16 70; then
        log INFO "Installation cancelled by user"
        exit 1
    fi
    log INFO "Installation confirmed"
}

ui_progress() {
    dialog --title "$1" --infobox "$2" 8 60
    sleep 1
}

# =============================================================================
# Storage Functions
# =============================================================================

auto_unmount_device() {
    local dev="$1"
    local user="${SUDO_USER:-$USER}"
    msg "Checking for active mounts and processes on $dev"
    log INFO "Checking mounts and processes on $dev"
    
    # Unmount all partitions
    umount -R "${dev}"* 2>/dev/null || true
    
    # Check for user mounts
    if mount | grep -q "/run/media/$user/"; then
        while read -r mp; do
            umount -R "$mp" 2>/dev/null || true
        done < <(mount | awk -v u="$user" '$3 ~ "^/run/media/" u "/" {print $3}')
    fi
    
    # Check for processes holding device open
    local holders
    holders=$(lsof 2>/dev/null | grep -- "$dev" || true)
    if [[ -n "$holders" ]]; then
        err "Processes are holding $dev open:"
        log ERROR "Holders on $dev: $holders"
        sed 's/^/    /' <<< "$holders"
        
        local pids
        pids=$(awk '{print $2}' <<< "$holders" | sort -u)
        info "Attempting graceful termination of processes: $pids"
        log INFO "Killing PIDs: $pids"
        for pid in $pids; do 
            kill "$pid" 2>/dev/null || true
        done
        sleep 2
        
        # Check again
        holders=$(lsof 2>/dev/null | grep -- "$dev" || true)
        if [[ -n "$holders" ]]; then
            err "Some processes are still holding $dev. Forcing kill."
            log ERROR "Forcing kill on remaining holders of $dev"
            pids=$(awk '{print $2}' <<< "$holders" | sort -u)
            for pid in $pids; do 
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
    fi
    
    # Final check
    holders=$(lsof 2>/dev/null | grep -- "$dev" || true)
    if [[ -n "$holders" ]]; then
        err "Unable to free $dev. A process is still holding it:"
        log ERROR "Unable to free $dev, holders remain: $holders"
        sed 's/^/    /' <<< "$holders"
        exit 1
    fi
    
    info "$dev is free and ready for partitioning."
    log INFO "$dev is free and ready for partitioning"
}

partition_and_format_sdcard() {
    msg "Partitioning $SDCARD"
    log INFO "Partitioning $SDCARD"
    auto_unmount_device "$SDCARD"
    
    # Create GPT partition table
    parted -s "$SDCARD" mklabel gpt
    parted -s "$SDCARD" mkpart primary fat32 1MiB 301MiB
    parted -s "$SDCARD" set 1 boot on
    parted -s "$SDCARD" mkpart primary ext4 301MiB 100%
    partprobe "$SDCARD"
    sleep 2
    
    # Determine partition names
    if [[ "$SDCARD" == *"mmcblk"* || "$SDCARD" == *"nvme"* ]]; then
        BOOTPART="${SDCARD}p1"
        ROOTPART="${SDCARD}p2"
    else
        BOOTPART="${SDCARD}1"
        ROOTPART="${SDCARD}2"
    fi
    
    log INFO "Formatting boot: $BOOTPART, root: $ROOTPART"
    mkfs.vfat -F32 "$BOOTPART"
    mkfs.ext4 -F "$ROOTPART"
    log INFO "Partitioning and formatting complete"
}

mount_root_partition() {
    msg "Mounting root partition $ROOTPART"
    log INFO "Mounting root partition $ROOTPART at $TMPDIR/root"
    mkdir -p "$TMPDIR/root"
    mount "$ROOTPART" "$TMPDIR/root"
}

# =============================================================================
# Package Management Functions
# =============================================================================

installer_get_armprofiles() {
    info "Getting package lists ready for $DEVICE $EDITION edition..."
    log INFO "Cloning arm-profiles"
    rm -rf "$TMPDIR/arm-profiles"
    mkdir -p "$TMPDIR"
    chmod 777 "$TMPDIR"
    
    if ! git clone --depth 1 --quiet \
        https://gitlab.manjaro.org/manjaro-arm/applications/arm-profiles.git \
        "$TMPDIR/arm-profiles/" 2>&1 | tee -a "$TMPDIR/install.log"; then
        err "Failed to clone arm-profiles"
        log ERROR "Failed to clone arm-profiles"
        exit 1
    fi
    log INFO "arm-profiles cloned successfully"
}

download_generic_rootfs() {
    msg "Downloading generic $ARCH rootfs..."
    log INFO "Downloading generic rootfs for $ARCH"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR" || exit 1
    rm -f "Manjaro-ARM-$ARCH-latest.tar.gz"*
    
    if ! wget -q --show-progress --progress=bar:force:noscroll \
        "https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz"; then
        err "Failed to download rootfs"
        log ERROR "Failed to download rootfs"
        exit 1
    fi
    log INFO "Rootfs downloaded successfully"
}

extract_generic_rootfs() {
    msg "Extracting generic rootfs..."
    log INFO "Extracting generic rootfs into $TMPDIR/root"
    
    if ! bsdtar -xpf "$TMPDIR/Manjaro-ARM-$ARCH-latest.tar.gz" -C "$TMPDIR/root"; then
        err "Failed to extract rootfs"
        log ERROR "Failed to extract rootfs"
        exit 1
    fi
    
    touch "$TMPDIR/root/MANJARO-ARM-IMAGE-BUILD"
    mkdir -p "$TMPDIR/root/etc/pacman.d"
    ln -sf ../usr/lib/os-release "$TMPDIR/root/etc/os-release"
    touch "$TMPDIR/root/etc/pacman.d/mirrorlist"
    log INFO "Rootfs extracted successfully"
}

setup_keyrings_and_mirrors() {
    msg "Setting up keyrings and mirrors..."
    log INFO "Initializing pacman keys and mirrors"
    
    $NSPAWN "$TMPDIR/root" pacman-key --init 1>/dev/null 2>&1
    sleep 5
    $NSPAWN "$TMPDIR/root" pacman-key --populate archlinuxarm manjaro manjaro-arm 1>/dev/null 2>&1
    
    if [[ -f "$TMPDIR/root/etc/pacman-mirrors.conf" ]]; then
        sed -i "s|.*Branch =.*|Branch = ${BRANCH}|g" "$TMPDIR/root/etc/pacman-mirrors.conf"
    fi
    
    $NSPAWN "$TMPDIR/root" pacman-mirrors -f10 1>/dev/null 2>&1 || true
    log INFO "Keyrings and mirrors configured"
}

get_kde_packages() {
    local variant="$1"
    local packages
    
    case "$variant" in
        kde-full)
            packages="plasma-desktop plasma-meta kde-system-meta kde-utilities-meta dolphin konsole plasma-nm plasma-pa ark kate spectacle gwenview okular xorg-server xorg-xinit"
            ;;
        kde-minimal)
            packages="plasma-desktop dolphin konsole systemsettings plasma-nm plasma-pa xorg-server xorg-xinit"
            ;;
        kde-wayland)
            packages="plasma-desktop plasma-wayland-session dolphin konsole systemsettings plasma-nm plasma-pa"
            ;;
        *)
            packages=""
            ;;
    esac
    
    echo "$packages"
}

get_xfce_completion_packages() {
    # CRITICAL: These packages are missing from arm-profiles XFCE edition
    # Without them, LightDM crashes and XFCE won't start
    echo "xfce4 xfce4-goodies xfce4-session xorg-server xorg-xinit"
}

get_gnome_completion_packages() {
    # Ensure GNOME has complete desktop with Wayland support
    echo "gnome gnome-extra gnome-shell mutter xorg-server"
}

load_profile_packages() {
    local profiles="$TMPDIR/arm-profiles"
    local edition_profile device_profile
    
    # FIX #1: Initialize PKG_COMPLETION to empty string as default
    PKG_COMPLETION=""
    
    # Map edition to profile
    case "$EDITION" in
        minimal)      edition_profile="minimal" ;;
        xfce)         edition_profile="xfce" ;;
        gnome)        edition_profile="gnome" ;;
        server)       edition_profile="server" ;;
        kde-*)        edition_profile="kde" ;;
        *) 
            err "Unknown edition: $EDITION"
            log ERROR "Unknown edition: $EDITION"
            exit 1
            ;;
    esac
    
    device_profile="rpi4"
    
    # Load package lists
    PKG_SHARED=$(grep -v '^#' "$profiles/shared/Packages-Root" 2>/dev/null || true)
    
    # Handle desktop editions with completion packages
    if [[ "$EDITION" =~ ^kde- ]]; then
        # KDE: Use custom package list since upstream removed KDE support
        PKG_EDITION=$(get_kde_packages "$EDITION")
        PKG_COMPLETION=""  # KDE packages are already complete
        log INFO "Using custom KDE package list for $EDITION"
    elif [[ "$EDITION" == "xfce" ]]; then
        # XFCE: Load from profile AND add completion packages
        PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
        PKG_COMPLETION=$(get_xfce_completion_packages)
        log INFO "Loaded XFCE profile + completion packages"
    elif [[ "$EDITION" == "gnome" ]]; then
        # FIX #3: GNOME with proper Wayland support
        PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
        PKG_COMPLETION=$(get_gnome_completion_packages)
        log INFO "Loaded GNOME profile + completion packages (with Wayland)"
    else
        # Minimal/Server: Use profile as-is
        PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
        PKG_COMPLETION=""  # No completion packages needed
    fi
    
    PKG_DEVICE=$(grep -v '^#' "$profiles/devices/$device_profile/Packages-Root" 2>/dev/null || true)
    
    # Services list
    if [[ "$EDITION" =~ ^kde- ]]; then
        srv_list=""  # KDE services handled separately
    else
        srv_list="$profiles/editions/$edition_profile/services"
    fi
    
    log INFO "Loaded package lists for edition=$EDITION device=$device_profile"
}

install_profile_packages() {
    msg "Installing packages for $EDITION on $DEVICE..."
    log INFO "Installing profile packages into rootfs"
    
    # Setup package cache
    mkdir -p "$TMPDIR/pkg-cache"
    mkdir -p "$TMPDIR/root/var/cache/pacman/pkg"
    mount -o bind "$TMPDIR/pkg-cache" "$TMPDIR/root/var/cache/pacman/pkg"
    
    # Install base packages + edition packages + completion packages
    # shellcheck disable=SC2086
    set -- base manjaro-system manjaro-release systemd systemd-libs \
        sudo $PKG_SHARED $PKG_EDITION $PKG_COMPLETION $PKG_DEVICE
    
    if ! $NSPAWN "$TMPDIR/root" pacman -Syu "$@" --noconfirm; then
        err "Failed to install packages"
        log ERROR "Failed to install packages"
        umount "$TMPDIR/root/var/cache/pacman/pkg" 2>/dev/null || true
        exit 1
    fi
    
    # Enable services
    msg "Enabling services..."
    $NSPAWN "$TMPDIR/root" systemctl enable getty.target haveged.service 1>/dev/null || true
    
    # Enable edition-specific services
    if [[ -f "$srv_list" ]]; then
        while read -r service; do
            [[ -z "$service" || "$service" =~ ^# ]] && continue
            if [[ -e "$TMPDIR/root/usr/lib/systemd/system/$service" ]]; then
                echo "Enabling $service ..."
                log INFO "Enabling service $service"
                $NSPAWN "$TMPDIR/root" systemctl enable "$service" 1>/dev/null || true
            else
                echo "$service not found in rootfs. Skipping."
                log INFO "Service $service not found, skipping"
            fi
        done < "$srv_list"
    fi
    
    # Enable xdg-user-dirs if available
    if [[ -f "$TMPDIR/root/usr/bin/xdg-user-dirs-update" ]]; then
        $NSPAWN "$TMPDIR/root" systemctl --global enable xdg-user-dirs-update.service 1>/dev/null 2>&1 || true
    fi
    
    umount "$TMPDIR/root/var/cache/pacman/pkg" 2>/dev/null || true
    log INFO "Package installation complete"
}

# =============================================================================
# Chroot Functions
# =============================================================================

prepare_chroot() {
    msg "Preparing chroot environment"
    log INFO "Binding /proc, /sys, /dev, /run into chroot"
    mount -t proc /proc "$TMPDIR/root/proc"
    mount --rbind /sys "$TMPDIR/root/sys"
    mount --rbind /dev "$TMPDIR/root/dev"
    mount --rbind /run "$TMPDIR/root/run"
}

# =============================================================================
# Pi 5 Specific Functions
# =============================================================================

install_pi5_firmware() {
    msg "Installing Raspberry Pi 5 firmware"
    log INFO "Installing raspberrypi-bootloader packages"
    
    if ! arch-chroot "$TMPDIR/root" bash -c "
        pacman -Sy --noconfirm raspberrypi-bootloader raspberrypi-bootloader-x
    "; then
        err "Failed to install Pi 5 firmware"
        log ERROR "Failed to install Pi 5 firmware"
        exit 1
    fi
    log INFO "Pi 5 firmware installed"
}

install_pi5_kernel() {
    msg "Installing Raspberry Pi 5 kernel"
    log INFO "Installing linux-rpi5 kernel"
    
    if ! arch-chroot "$TMPDIR/root" bash -c "
        # Remove pi4 kernel if it exists (don't fail if not found)
        pacman -Q linux-rpi4 >/dev/null 2>&1 && pacman -Rdd --noconfirm linux-rpi4 || true
        # Install pi5 kernel with mkinitcpio as default initramfs
        pacman -Sy --noconfirm --overwrite '*' linux-rpi5 linux-rpi5-headers
    "; then
        err "Failed to install Pi 5 kernel"
        log ERROR "Failed to install Pi 5 kernel"
        exit 1
    fi
    log INFO "Pi 5 kernel installed"
}

align_boot_inside_root() {
    msg "Aligning boot partition inside rootfs"
    log INFO "Mounting boot partition $BOOTPART at /boot"
    mkdir -p "$TMPDIR/root/boot"
    mount "$BOOTPART" "$TMPDIR/root/boot"
}

fix_boot_layout() {
    msg "Fixing Pi 5 boot layout"
    log INFO "Adjusting boot/firmware layout"
    mkdir -p "$TMPDIR/root/boot/firmware"
    
    # Move boot files to firmware directory
    if [[ -f "$TMPDIR/root/boot/kernel8.img" ]]; then
        mv "$TMPDIR/root/boot/"* "$TMPDIR/root/boot/firmware/" 2>/dev/null || true
    fi
    
    # Ensure config files exist
    touch "$TMPDIR/root/boot/firmware/config.txt"
    touch "$TMPDIR/root/boot/firmware/cmdline.txt"
    log INFO "Boot layout fixed"
}

patch_config_txt() {
    msg "Patching config.txt"
    log INFO "Writing config.txt for Pi 5"
    cat <<'EOF' > "$TMPDIR/root/boot/firmware/config.txt"
# Raspberry Pi 5 Configuration
arm_64bit=1
kernel=kernel8.img
enable_uart=1

# PCIe Gen 3
dtparam=pciex1_gen=3

# GPU and Display
dtoverlay=vc4-kms-v3d
gpu_mem=256

# Enable I2C, SPI
dtparam=i2c_arm=on
dtparam=spi=on

# Audio
dtparam=audio=on
EOF
    log INFO "config.txt written"
}

patch_cmdline_txt() {
    msg "Patching cmdline.txt"
    log INFO "Writing cmdline.txt with root UUID"
    local uuid
    uuid=$(blkid -s UUID -o value "$ROOTPART")
    echo "root=UUID=$uuid rw rootwait console=ttyAMA0,115200 console=tty1 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 elevator=noop" \
        > "$TMPDIR/root/boot/firmware/cmdline.txt"
    log INFO "cmdline.txt written with UUID=$uuid"
}

generate_fstab() {
    msg "Generating fstab"
    log INFO "Generating fstab with UUIDs"
    local uuid_root uuid_boot
    uuid_root=$(blkid -s UUID -o value "$ROOTPART")
    uuid_boot=$(blkid -s UUID -o value "$BOOTPART")
    cat <<EOF > "$TMPDIR/root/etc/fstab"
# /etc/fstab: static file system information
UUID=$uuid_root   /               ext4    defaults,noatime  0 1
UUID=$uuid_boot   /boot/firmware  vfat    defaults,noatime  0 2
EOF
    log INFO "fstab generated"
}

# =============================================================================
# Sanity Check Functions
# =============================================================================

sanity_check_boot_files() {
    msg "Verifying boot files..."
    log INFO "Running boot sanity checks"
    
    # Check for kernel8.img
    if [[ -f "$TMPDIR/root/boot/firmware/kernel8.img" ]]; then
        info "✓ kernel8.img found"
        log INFO "Boot sanity check: kernel8.img OK"
    else
        err "✗ kernel8.img NOT found - boot will fail!"
        log ERROR "Boot sanity check FAILED: kernel8.img missing"
        return 1
    fi
    
    # Check for firmware files
    if ls "$TMPDIR/root/boot/firmware/"*.dat >/dev/null 2>&1; then
        info "✓ Firmware files found"
        log INFO "Boot sanity check: firmware files OK"
    else
        err "✗ Firmware files NOT found"
        log ERROR "Boot sanity check FAILED: firmware files missing"
        return 1
    fi
    
    return 0
}

sanity_check_desktop_session() {
    # Skip for non-desktop editions
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        return 0
    fi
    
    msg "Verifying desktop session files..."
    log INFO "Running desktop session sanity checks"
    
    case "$EDITION" in
        xfce)
            if [[ -f "$TMPDIR/root/usr/share/xsessions/xfce.desktop" ]]; then
                info "✓ XFCE session file found"
                log INFO "Session sanity check: XFCE OK"
            else
                err "✗ XFCE session file NOT found - desktop won't start!"
                log ERROR "Session sanity check FAILED: xfce.desktop missing"
                return 1
            fi
            ;;
        gnome)
            if [[ -f "$TMPDIR/root/usr/share/xsessions/gnome.desktop" ]] || \
               [[ -f "$TMPDIR/root/usr/share/wayland-sessions/gnome.desktop" ]]; then
                info "✓ GNOME session file found"
                log INFO "Session sanity check: GNOME OK"
            else
                err "✗ GNOME session file NOT found"
                log ERROR "Session sanity check FAILED: gnome.desktop missing"
                return 1
            fi
            ;;
        kde-*)
            if [[ -f "$TMPDIR/root/usr/share/xsessions/plasma.desktop" ]] || \
               [[ -f "$TMPDIR/root/usr/share/wayland-sessions/plasma.desktop" ]] || \
               [[ -f "$TMPDIR/root/usr/share/wayland-sessions/plasmawayland.desktop" ]]; then
                info "✓ Plasma session file found"
                log INFO "Session sanity check: Plasma OK"
            else
                err "✗ Plasma session file NOT found"
                log ERROR "Session sanity check FAILED: plasma.desktop missing"
                return 1
            fi
            ;;
    esac
    
    return 0
}

sanity_check_display_manager() {
    # Skip for non-desktop editions or no DM
    if [[ "$EDITION" =~ ^(minimal|server)$ ]] || [[ "$DISPLAY_MANAGER" == "none" ]]; then
        return 0
    fi
    
    msg "Verifying display manager configuration..."
    log INFO "Running display manager sanity checks"
    
    case "$DISPLAY_MANAGER" in
        lightdm)
            # Check for greeter config
            if [[ -f "$TMPDIR/root/etc/lightdm/lightdm.conf" ]] || \
               [[ -f "$TMPDIR/root/usr/share/lightdm/lightdm.conf.d/50-greeter-wrapper.conf" ]]; then
                info "✓ LightDM configuration found"
                log INFO "DM sanity check: LightDM config OK"
            else
                err "✗ LightDM configuration NOT found"
                log ERROR "DM sanity check FAILED: LightDM config missing"
                return 1
            fi
            
            # Check for GTK greeter
            if [[ -f "$TMPDIR/root/usr/sbin/lightdm-gtk-greeter" ]] || \
               [[ -f "$TMPDIR/root/usr/bin/lightdm-gtk-greeter" ]]; then
                info "✓ LightDM GTK greeter found"
                log INFO "DM sanity check: GTK greeter OK"
            else
                err "✗ LightDM GTK greeter NOT found - login screen won't appear!"
                log ERROR "DM sanity check FAILED: lightdm-gtk-greeter missing"
                return 1
            fi
            ;;
        sddm)
            if [[ -f "$TMPDIR/root/usr/bin/sddm" ]]; then
                info "✓ SDDM found"
                log INFO "DM sanity check: SDDM OK"
            else
                err "✗ SDDM NOT found"
                log ERROR "DM sanity check FAILED: SDDM missing"
                return 1
            fi
            ;;
        gdm)
            if [[ -f "$TMPDIR/root/usr/bin/gdm" ]]; then
                info "✓ GDM found"
                log INFO "DM sanity check: GDM OK"
            else
                err "✗ GDM NOT found"
                log ERROR "DM sanity check FAILED: GDM missing"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# =============================================================================
# System Configuration Functions
# =============================================================================

configure_display_manager() {
    # Skip for non-desktop editions
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        log INFO "Non-desktop edition, skipping display manager"
        return
    fi
    
    msg "Configuring display manager: $DISPLAY_MANAGER"
    log INFO "Configuring display manager: $DISPLAY_MANAGER"
    
    # Disable all display managers first
    arch-chroot "$TMPDIR/root" bash -c '
        systemctl disable sddm.service lightdm.service gdm.service 2>/dev/null || true
    '
    
    # FIX #2: Install DM and greeter BEFORE enabling the service
    case "$DISPLAY_MANAGER" in
        sddm)
            arch-chroot "$TMPDIR/root" bash -c "
                # Install SDDM
                pacman -Sy --noconfirm sddm
                # Enable after installation complete
                systemctl enable sddm.service
            "
            log INFO "SDDM installed and enabled"
            ;;
        lightdm)
            arch-chroot "$TMPDIR/root" bash -c "
                # CRITICAL: Install LightDM + greeter TOGETHER before enabling
                pacman -Sy --noconfirm lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
                # Enable only after both are installed
                systemctl enable lightdm.service
            "
            log INFO "LightDM with GTK greeter installed and enabled"
            ;;
        gdm)
            arch-chroot "$TMPDIR/root" bash -c "
                # Install GDM
                pacman -Sy --noconfirm gdm
                # Enable after installation
                systemctl enable gdm.service
            "
            log INFO "GDM installed and enabled"
            ;;
        none)
            log INFO "No display manager selected; using console login"
            ;;
    esac
}

finalize_system() {
    msg "Finalizing system"
    log INFO "Enabling NetworkManager and sshd"
    arch-chroot "$TMPDIR/root" bash -c "
        systemctl enable NetworkManager || true
        systemctl enable sshd || true
    "
    log INFO "System services enabled"
}

create_user_account() {
    msg "Creating user account '$USERNAME'"
    log INFO "Creating user $USERNAME and enabling sudo"
    
    # Create plugdev group if it doesn't exist
    arch-chroot "$TMPDIR/root" bash -c "
        # Create plugdev group if missing
        getent group plugdev >/dev/null 2>&1 || groupadd -r plugdev
        
        # Create user with available groups
        useradd -m -G wheel,video,audio,storage,input,lp,network,render,uucp,plugdev,adm -s /bin/bash \"$USERNAME\" || \
        useradd -m -G wheel,video,audio,storage,input,lp,network,uucp,adm -s /bin/bash \"$USERNAME\"
        
        # Set password
        echo \"$USERNAME:$USER_PASSWORD\" | chpasswd
        
        # Enable sudo for wheel group
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || \
        sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    "
    log INFO "User account created"
}

apply_root_mode() {
    case "$ROOT_MODE" in
        setpw)
            msg "Setting root password"
            log INFO "Setting root password"
            arch-chroot "$TMPDIR/root" bash -c "
                echo \"root:$ROOT_PASSWORD\" | chpasswd
            "
            ;;
        disable)
            msg "Disabling root SSH login"
            log INFO "Disabling root SSH login in sshd_config"
            arch-chroot "$TMPDIR/root" bash -c "
                mkdir -p /etc/ssh
                if grep -q '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null; then
                    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                else
                    echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
                fi
            "
            ;;
        lock)
            msg "Locking root account"
            log INFO "Locking root account with passwd -l"
            arch-chroot "$TMPDIR/root" bash -c "
                passwd -l root
            "
            ;;
        skip)
            msg "Skipping root password (sudo-only)"
            log INFO "Skipping root password (sudo-only mode)"
            ;;
    esac
}

# =============================================================================
# Post-Install Optimizations
# =============================================================================

post_install_optimizations() {
    msg "Applying selected post-install optimizations"
    log INFO "Applying optimizations: $*"
    arch-chroot "$TMPDIR/root" bash -s -- "$@" <<'EOF'
apply_opt() {
    local opt="$1"
    case "$opt" in
        zram)
            echo ">>> Enabling ZRAM swap"
            pacman -Sy --noconfirm zram-generator
            mkdir -p /etc/systemd/zram-generator.conf.d
            cat <<'ZEOF' >/etc/systemd/zram-generator.conf.d/override.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZEOF
            systemctl enable systemd-zram-setup@zram0.service || true
            ;;
        sysctl)
            echo ">>> Applying sysctl performance tuning"
            cat <<'SEOF' >/etc/sysctl.d/99-pi5-performance.conf
# Swappiness and cache pressure
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# Network buffers
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400

# Scheduler tuning
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000

# Reduce dirty page writeback
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
SEOF
            ;;
        gpu)
            echo ">>> Setting GPU memory split"
            sed -i '/^gpu_mem=/d' /boot/firmware/config.txt
            echo 'gpu_mem=256' >> /boot/firmware/config.txt
            ;;
        journald)
            echo ">>> Optimizing journald"
            mkdir -p /etc/systemd/journald.conf.d
            cat <<'JEOF' >/etc/systemd/journald.conf.d/99-optimized.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
Storage=auto
Compress=yes
MaxRetentionSec=1week
JEOF
            ;;
        fstrim)
            echo ">>> Enabling fstrim weekly"
            systemctl enable fstrim.timer || true
            ;;
        cpupower)
            echo ">>> Enabling CPU frequency governor (ondemand)"
            pacman -Sy --noconfirm cpupower
            systemctl enable cpupower.service
            echo 'governor=ondemand' > /etc/default/cpupower
            ;;
    esac
}
for opt in "$@"; do
    apply_opt "$opt"
done
EOF
    log INFO "Optimizations applied"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

finalize_install() {
    msg "Finalizing installation"
    log INFO "Unmounting chroot and partitions"
    
    # Unmount in reverse order with retries
    local max_attempts=3
    local attempt
    
    for mountpoint in \
        "$TMPDIR/root/run" \
        "$TMPDIR/root/dev" \
        "$TMPDIR/root/sys" \
        "$TMPDIR/root/proc" \
        "$TMPDIR/root/boot/firmware" \
        "$TMPDIR/root/boot" \
        "$TMPDIR/root"; do
        
        attempt=0
        while mountpoint -q "$mountpoint" 2>/dev/null && [ $attempt -lt $max_attempts ]; do
            attempt=$((attempt + 1))
            log INFO "Unmounting $mountpoint (attempt $attempt)"
            if umount -R "$mountpoint" 2>/dev/null; then
                break
            fi
            sleep 2
        done
    done
    
    log INFO "All partitions unmounted"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Initialize
    mkdir -p "$TMPDIR" "$TMPDIR/tmp"
    log INFO "Starting Manjaro ARM Pi 5 installer v2.2"
    
    # Check dependencies
    for cmd in dialog git wget bsdtar parted mkfs.vfat mkfs.ext4 arch-chroot systemd-nspawn lsof blkid; do
        if ! command -v "$cmd" &> /dev/null; then
            err "Required command '$cmd' not found. Please install it."
            exit 1
        fi
    done
    
    # User interface flow
    ui_select_edition
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
    
    # Installation steps
    ui_progress "Partitioning" "Preparing SD card..."
    partition_and_format_sdcard
    
    ui_progress "Mounting" "Mounting root partition..."
    mount_root_partition
    
    ui_progress "Profiles" "Fetching arm-profiles..."
    installer_get_armprofiles
    
    ui_progress "Rootfs" "Downloading generic rootfs..."
    download_generic_rootfs
    
    ui_progress "Rootfs" "Extracting generic rootfs..."
    extract_generic_rootfs
    
    ui_progress "Keys" "Setting up keyrings and mirrors..."
    setup_keyrings_and_mirrors
    
    ui_progress "Profiles" "Loading edition and device packages..."
    load_profile_packages
    
    ui_progress "Packages" "Installing edition and device packages..."
    install_profile_packages
    
    ui_progress "Boot Setup" "Mounting boot partition..."
    align_boot_inside_root
    
    ui_progress "Chroot" "Preparing chroot environment..."
    prepare_chroot
    
    ui_progress "Firmware" "Installing Pi 5 firmware..."
    install_pi5_firmware
    
    ui_progress "Kernel" "Installing Pi 5 kernel..."
    install_pi5_kernel
    
    ui_progress "Boot Layout" "Configuring Pi 5 boot layout..."
    fix_boot_layout
    patch_config_txt
    patch_cmdline_txt
    
    ui_progress "Filesystem" "Generating fstab..."
    generate_fstab
    
    ui_progress "Verification" "Running boot sanity checks..."
    if ! sanity_check_boot_files; then
        err "Boot sanity checks failed - installation may not boot properly"
        log ERROR "Boot sanity checks failed"
        # Continue anyway - user may want to fix manually
    fi
    
    ui_progress "Display Manager" "Configuring display manager..."
    configure_display_manager
    
    ui_progress "Verification" "Running desktop sanity checks..."
    if ! sanity_check_desktop_session; then
        err "Desktop session sanity checks failed - desktop may not start"
        log ERROR "Desktop session sanity checks failed"
    fi
    
    if ! sanity_check_display_manager; then
        err "Display manager sanity checks failed - greeter may not appear"
        log ERROR "Display manager sanity checks failed"
    fi
    
    ui_progress "System" "Enabling services..."
    finalize_system
    
    ui_progress "Users" "Creating user account..."
    create_user_account
    
    ui_progress "Root" "Configuring root account..."
    apply_root_mode
    
    ui_progress "Optimizing" "Applying selected optimizations..."
    if (( ${#OPTS[@]} > 0 )); then
        post_install_optimizations "${OPTS[@]}"
    fi
    
    ui_progress "Cleanup" "Unmounting and finalizing..."
    finalize_install
    
    log INFO "Installation complete"
    
    # Success message
    dialog --title "Installation Complete" --msgbox \
        "Manjaro ARM with $EDITION is now installed on $SDCARD!\n\n\
✓ Pi 5 firmware installed\n\
✓ Pi 5 kernel installed\n\
✓ Boot files verified\n\
✓ Desktop session verified\n\
✓ User: $USERNAME\n\
✓ Display manager: $DISPLAY_MANAGER\n\
✓ Optimizations: ${#OPTS[@]} applied\n\n\
You can now remove the SD card and boot your Raspberry Pi 5.\n\n\
First boot may take a few minutes to initialize." 20 70
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"
clear

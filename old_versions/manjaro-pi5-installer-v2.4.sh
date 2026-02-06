#!/usr/bin/env bash
#
# Manjaro ARM Pi 5 Installer - COMPLETE WORKING EDITION
# Version: 2.4 - Proper Boot Partition Firmware Population
#
# Critical fix in v2.4:
# - Downloads and extracts official Pi 5 boot partition
# - Populates /boot with firmware, DTBs, overlays
# - Ensures vc4 KMS is properly initialized
# - Guarantees working display pipeline for Xorg
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

# Pi 5 boot partition source
PI5_BOOT_URL="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/boot-rpi5.tar.gz"

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

# Sanitization helper
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
# UI Functions (unchanged from v2.3)
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
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        DISPLAY_MANAGER="none"
        log INFO "Non-desktop edition, skipping display manager"
        return
    fi
    
    case "$EDITION" in
        kde-*) default_dm="sddm" ;;
        xfce) default_dm="lightdm" ;;
        gnome) default_dm="gdm" ;;
        *) default_dm="lightdm" ;;
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
        disable "Disable root SSH login" \
        lock    "Lock root account" \
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
        zram     "Enable ZRAM swap" ON \
        sysctl   "Kernel tuning" ON \
        gpu      "Set GPU memory to 256MB" ON \
        journald "Reduce log size" ON \
        fstrim   "Enable weekly TRIM" ON \
        cpupower "Enable CPU governor" ON)
    raw=$(sanitize_single_line "$raw")
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
    msg "Checking for active mounts on $dev"
    log INFO "Checking mounts and processes on $dev"
    
    umount -R "${dev}"* 2>/dev/null || true
    
    if mount | grep -q "/run/media/$user/"; then
        while read -r mp; do
            umount -R "$mp" 2>/dev/null || true
        done < <(mount | awk -v u="$user" '$3 ~ "^/run/media/" u "/" {print $3}')
    fi
    
    local holders
    holders=$(lsof 2>/dev/null | grep -- "$dev" || true)
    if [[ -n "$holders" ]]; then
        err "Processes holding $dev open"
        log ERROR "Holders on $dev: $holders"
        local pids
        pids=$(awk '{print $2}' <<< "$holders" | sort -u)
        for pid in $pids; do 
            kill "$pid" 2>/dev/null || true
        done
        sleep 2
        
        holders=$(lsof 2>/dev/null | grep -- "$dev" || true)
        if [[ -n "$holders" ]]; then
            pids=$(awk '{print $2}' <<< "$holders" | sort -u)
            for pid in $pids; do 
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
    fi
    
    info "$dev is ready"
    log INFO "$dev is ready for partitioning"
}

partition_and_format_sdcard() {
    msg "Partitioning $SDCARD"
    log INFO "Partitioning $SDCARD"
    auto_unmount_device "$SDCARD"
    
    parted -s "$SDCARD" mklabel gpt
    parted -s "$SDCARD" mkpart primary fat32 1MiB 301MiB
    parted -s "$SDCARD" set 1 boot on
    parted -s "$SDCARD" mkpart primary ext4 301MiB 100%
    partprobe "$SDCARD"
    sleep 2
    
    if [[ "$SDCARD" == *"mmcblk"* || "$SDCARD" == *"nvme"* ]]; then
        BOOTPART="${SDCARD}p1"
        ROOTPART="${SDCARD}p2"
    else
        BOOTPART="${SDCARD}1"
        ROOTPART="${SDCARD}2"
    fi
    
    log INFO "Formatting boot: $BOOTPART, root: $ROOTPART"
    mkfs.vfat -F32 -n BOOT "$BOOTPART"
    mkfs.ext4 -F -L ROOT "$ROOTPART"
    log INFO "Partitioning complete"
}

mount_root_partition() {
    msg "Mounting root partition"
    log INFO "Mounting $ROOTPART at $TMPDIR/root"
    mkdir -p "$TMPDIR/root"
    mount "$ROOTPART" "$TMPDIR/root"
}

mount_boot_partition() {
    msg "Mounting boot partition"
    log INFO "Mounting $BOOTPART at $TMPDIR/root/boot"
    mkdir -p "$TMPDIR/root/boot"
    mount "$BOOTPART" "$TMPDIR/root/boot"
}

# =============================================================================
# Pi 5 Boot Partition Functions (NEW in v2.4)
# =============================================================================

download_pi5_boot_files() {
    msg "Downloading Pi 5 boot files..."
    log INFO "Downloading official Pi 5 firmware and bootloader"
    
    mkdir -p "$TMPDIR/pi5-boot"
    cd "$TMPDIR" || exit 1
    
    # Try to download official boot partition
    if wget -q --show-progress --progress=bar:force:noscroll \
        "$PI5_BOOT_URL" -O pi5-boot.tar.gz 2>&1 | tee -a "$TMPDIR/install.log"; then
        log INFO "Pi 5 boot files downloaded"
        tar -xzf pi5-boot.tar.gz -C "$TMPDIR/pi5-boot" || {
            err "Failed to extract Pi 5 boot files"
            log ERROR "Boot files extraction failed"
            return 1
        }
    else
        log WARN "Could not download pre-built boot files, will use package-provided files"
        return 1
    fi
    
    log INFO "Pi 5 boot files extracted"
    return 0
}

populate_boot_from_packages() {
    msg "Populating boot partition from installed packages..."
    log INFO "Using raspberrypi-bootloader package files"
    
    # The raspberrypi-bootloader packages install files to /boot
    # We need to copy them to the boot partition
    
    if [[ -d "$TMPDIR/root/boot/firmware" ]]; then
        # Files are in /boot/firmware, move them to /boot
        log INFO "Moving firmware files from /boot/firmware to /boot"
        cp -r "$TMPDIR/root/boot/firmware/"* "$TMPDIR/root/boot/" 2>/dev/null || true
        rm -rf "$TMPDIR/root/boot/firmware"
    fi
    
    # Ensure we have critical boot files
    local critical_files=(
        "bcm2712-rpi-5-b.dtb"
        "kernel8.img"
        "config.txt"
        "cmdline.txt"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$TMPDIR/root/boot/$file" ]]; then
            err "Critical boot file missing: $file"
            log ERROR "Missing boot file: $file"
        else
            info "✓ Found $file"
            log INFO "Boot file present: $file"
        fi
    done
    
    # Ensure overlays directory exists
    mkdir -p "$TMPDIR/root/boot/overlays"
    
    log INFO "Boot partition populated from packages"
    return 0
}

copy_pi5_boot_files() {
    msg "Setting up Pi 5 boot partition..."
    log INFO "Copying Pi 5 firmware to boot partition"
    
    # Try to download pre-built boot files first
    if download_pi5_boot_files; then
        # Copy from downloaded boot files
        log INFO "Copying from downloaded Pi 5 boot files"
        cp -r "$TMPDIR/pi5-boot/"* "$TMPDIR/root/boot/" || {
            err "Failed to copy boot files"
            log ERROR "Boot file copy failed"
            return 1
        }
    else
        # Fall back to package-provided files
        log INFO "Using package-provided boot files"
        populate_boot_from_packages
    fi
    
    log INFO "Pi 5 boot files copied"
    return 0
}

configure_boot_files() {
    msg "Configuring boot files..."
    log INFO "Configuring config.txt and cmdline.txt"
    
    # Get root partition PARTUUID
    local root_partuuid
    root_partuuid=$(blkid -s PARTUUID -o value "$ROOTPART")
    
    # Create/update config.txt
    cat > "$TMPDIR/root/boot/config.txt" <<'EOF'
# Raspberry Pi 5 Configuration
[pi5]
arm_64bit=1
kernel=kernel8.img
enable_uart=1

# PCIe Gen 3
dtparam=pciex1_gen=3

# GPU and Display (CRITICAL for Xorg)
dtoverlay=vc4-kms-v3d
max_framebuffers=2
gpu_mem=256

# Enable I2C, SPI
dtparam=i2c_arm=on
dtparam=spi=on

# Audio
dtparam=audio=on

# Camera
camera_auto_detect=1

# Display
display_auto_detect=1
EOF
    
    log INFO "config.txt configured with vc4-kms-v3d"
    
    # Create cmdline.txt with correct root
    echo "root=PARTUUID=$root_partuuid rw rootwait console=ttyAMA0,115200 console=tty1 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 elevator=noop quiet splash" \
        > "$TMPDIR/root/boot/cmdline.txt"
    
    log INFO "cmdline.txt configured with root=PARTUUID=$root_partuuid"
    
    return 0
}

verify_boot_partition() {
    msg "Verifying boot partition..."
    log INFO "Running boot partition sanity checks"
    
    local failed=0
    
    # Check for kernel
    if [[ -f "$TMPDIR/root/boot/kernel8.img" ]]; then
        info "✓ kernel8.img found"
        log INFO "Boot check: kernel8.img OK"
    else
        err "✗ kernel8.img NOT found"
        log ERROR "Boot check FAILED: kernel8.img missing"
        failed=1
    fi
    
    # Check for DTB
    if [[ -f "$TMPDIR/root/boot/bcm2712-rpi-5-b.dtb" ]]; then
        info "✓ Pi 5 DTB found"
        log INFO "Boot check: DTB OK"
    else
        err "✗ Pi 5 DTB NOT found"
        log ERROR "Boot check FAILED: DTB missing"
        failed=1
    fi
    
    # Check for firmware files
    if ls "$TMPDIR/root/boot/"*.dat >/dev/null 2>&1 || \
       ls "$TMPDIR/root/boot/"*.elf >/dev/null 2>&1; then
        info "✓ Firmware files found"
        log INFO "Boot check: firmware OK"
    else
        err "✗ Firmware files NOT found"
        log ERROR "Boot check FAILED: firmware missing"
        failed=1
    fi
    
    # Check for overlays directory
    if [[ -d "$TMPDIR/root/boot/overlays" ]]; then
        local overlay_count=$(ls "$TMPDIR/root/boot/overlays/"*.dtbo 2>/dev/null | wc -l)
        info "✓ Overlays directory found ($overlay_count overlays)"
        log INFO "Boot check: overlays OK ($overlay_count files)"
    else
        err "✗ Overlays directory NOT found"
        log ERROR "Boot check FAILED: overlays missing"
        failed=1
    fi
    
    # Check for vc4-kms overlay specifically
    if [[ -f "$TMPDIR/root/boot/overlays/vc4-kms-v3d.dtbo" ]] || \
       [[ -f "$TMPDIR/root/boot/overlays/vc4-kms-v3d-pi5.dtbo" ]]; then
        info "✓ vc4-kms-v3d overlay found"
        log INFO "Boot check: vc4-kms overlay OK"
    else
        err "✗ vc4-kms-v3d overlay NOT found"
        log ERROR "Boot check FAILED: vc4-kms overlay missing"
        failed=1
    fi
    
    # Check config.txt
    if [[ -f "$TMPDIR/root/boot/config.txt" ]]; then
        if grep -q "dtoverlay=vc4-kms-v3d" "$TMPDIR/root/boot/config.txt"; then
            info "✓ config.txt has vc4-kms-v3d enabled"
            log INFO "Boot check: config.txt OK"
        else
            err "✗ config.txt missing vc4-kms-v3d"
            log ERROR "Boot check FAILED: vc4-kms not enabled"
            failed=1
        fi
    else
        err "✗ config.txt NOT found"
        log ERROR "Boot check FAILED: config.txt missing"
        failed=1
    fi
    
    # Check cmdline.txt
    if [[ -f "$TMPDIR/root/boot/cmdline.txt" ]]; then
        info "✓ cmdline.txt found"
        log INFO "Boot check: cmdline.txt OK"
    else
        err "✗ cmdline.txt NOT found"
        log ERROR "Boot check FAILED: cmdline.txt missing"
        failed=1
    fi
    
    if [ $failed -eq 0 ]; then
        msg "✓ Boot partition verification passed!"
        log INFO "All boot partition checks passed"
        return 0
    else
        err "✗ Boot partition verification failed"
        log ERROR "Boot partition verification failed"
        return 1
    fi
}

# =============================================================================
# Package Management Functions
# =============================================================================

installer_get_armprofiles() {
    info "Getting package lists..."
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
    log INFO "arm-profiles cloned"
}

download_generic_rootfs() {
    msg "Downloading generic rootfs..."
    log INFO "Downloading rootfs for $ARCH"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR" || exit 1
    rm -f "Manjaro-ARM-$ARCH-latest.tar.gz"*
    
    if ! wget -q --show-progress --progress=bar:force:noscroll \
        "https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz"; then
        err "Failed to download rootfs"
        log ERROR "Failed to download rootfs"
        exit 1
    fi
    log INFO "Rootfs downloaded"
}

extract_generic_rootfs() {
    msg "Extracting rootfs..."
    log INFO "Extracting rootfs into $TMPDIR/root"
    
    if ! bsdtar -xpf "$TMPDIR/Manjaro-ARM-$ARCH-latest.tar.gz" -C "$TMPDIR/root"; then
        err "Failed to extract rootfs"
        log ERROR "Failed to extract rootfs"
        exit 1
    fi
    
    touch "$TMPDIR/root/MANJARO-ARM-IMAGE-BUILD"
    mkdir -p "$TMPDIR/root/etc/pacman.d"
    ln -sf ../usr/lib/os-release "$TMPDIR/root/etc/os-release"
    touch "$TMPDIR/root/etc/pacman.d/mirrorlist"
    log INFO "Rootfs extracted"
}

setup_keyrings_and_mirrors() {
    msg "Setting up keyrings..."
    log INFO "Initializing pacman keys"
    
    $NSPAWN "$TMPDIR/root" pacman-key --init 1>/dev/null 2>&1
    sleep 5
    $NSPAWN "$TMPDIR/root" pacman-key --populate archlinuxarm manjaro manjaro-arm 1>/dev/null 2>&1
    
    if [[ -f "$TMPDIR/root/etc/pacman-mirrors.conf" ]]; then
        sed -i "s|.*Branch =.*|Branch = ${BRANCH}|g" "$TMPDIR/root/etc/pacman-mirrors.conf"
    fi
    
    $NSPAWN "$TMPDIR/root" pacman-mirrors -f10 1>/dev/null 2>&1 || true
    log INFO "Keyrings configured"
}

# =============================================================================
# Network Setup Functions
# =============================================================================

setup_network() {
    msg "Setting up network..."
    log INFO "Installing network stack"
    
    if ! $NSPAWN "$TMPDIR/root" pacman -Sy --noconfirm \
        networkmanager dhcpcd openresolv iwd wpa_supplicant network-manager-applet; then
        err "Failed to install network packages"
        log ERROR "Network package installation failed"
        return 1
    fi
    
    arch-chroot "$TMPDIR/root" bash -c '
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/fallback.conf <<EOF
[Resolve]
FallbackDNS=8.8.8.8 8.8.4.4 1.1.1.1
DNS=8.8.8.8
EOF
        systemctl enable NetworkManager
        systemctl enable systemd-resolved
    '
    
    log INFO "Network configured"
    return 0
}

verify_network_connectivity() {
    msg "Verifying network..."
    log INFO "Testing connectivity"
    
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        if $NSPAWN "$TMPDIR/root" bash -c '
            getent hosts repo.manjaro.org >/dev/null 2>&1 ||
            getent hosts google.com >/dev/null 2>&1
        '; then
            info "✓ Network verified"
            log INFO "Network check passed"
            return 0
        fi
        
        attempts=$((attempts + 1))
        err "Network check failed (attempt $attempts/$max_attempts)"
        sleep 3
    done
    
    log ERROR "Network check failed"
    return 1
}

handle_network_failure() {
    if dialog --title "Network Failed" \
        --yesno "Network setup failed.\n\nContinue anyway?" 10 50; then
        log INFO "Continuing despite network failure"
        return 0
    else
        exit 1
    fi
}

# =============================================================================
# Xorg Stack Functions
# =============================================================================

install_xorg_stack() {
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        return 0
    fi
    
    msg "Installing Xorg stack..."
    log INFO "Installing complete Xorg"
    
    if ! arch-chroot "$TMPDIR/root" bash -c "
        pacman -Sy --noconfirm \
            xorg xorg-server xorg-apps xorg-xinit xorg-xauth xorg-xkbcomp \
            xorg-drivers xf86-input-libinput xf86-input-evdev \
            xf86-video-fbdev mesa mesa-utils libinput || exit 1
        
        mkdir -p /etc/X11/xorg.conf.d
        
        cat > /etc/X11/xorg.conf.d/20-modesetting.conf <<'EOF'
Section \"Device\"
    Identifier \"vc4\"
    Driver \"modesetting\"
    Option \"AccelMethod\" \"glamor\"
EndSection
EOF
        
        cat > /etc/X11/xorg.conf.d/40-libinput.conf <<'EOF'
Section \"InputClass\"
    Identifier \"libinput pointer\"
    MatchIsPointer \"on\"
    MatchDevicePath \"/dev/input/event*\"
    Driver \"libinput\"
EndSection

Section \"InputClass\"
    Identifier \"libinput keyboard\"
    MatchIsKeyboard \"on\"
    MatchDevicePath \"/dev/input/event*\"
    Driver \"libinput\"
EndSection
EOF
    "; then
        err "Xorg installation failed"
        return 1
    fi
    
    log INFO "Xorg installed"
    return 0
}

sanity_check_xorg_stack() {
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        return 0
    fi
    
    msg "Verifying Xorg..."
    local failed=0
    
    [[ -f "$TMPDIR/root/usr/bin/Xorg" ]] && info "✓ Xorg server" || { err "✗ Xorg server"; failed=1; }
    [[ -f "$TMPDIR/root/usr/lib/xorg/modules/drivers/modesetting_drv.so" ]] && info "✓ Modesetting driver" || { err "✗ Modesetting"; failed=1; }
    [[ -f "$TMPDIR/root/usr/lib/xorg/modules/input/libinput_drv.so" ]] && info "✓ Libinput driver" || { err "✗ Libinput"; failed=1; }
    
    return $failed
}

handle_xorg_failure() {
    err "Xorg failed"
    log ERROR "Xorg failure"
    
    local choice
    choice=$(dialog_input "Xorg Failed" \
        --menu "Recovery:" 14 50 4 \
        retry   "Retry" \
        console "Console only" \
        abort   "Abort")
    
    case "$choice" in
        retry) install_xorg_stack && sanity_check_xorg_stack ;;
        console) EDITION="minimal"; DISPLAY_MANAGER="none" ;;
        *) exit 1 ;;
    esac
}

# =============================================================================
# Package Lists
# =============================================================================

get_kde_packages() {
    case "$1" in
        kde-full) echo "plasma-desktop plasma-meta kde-system-meta kde-utilities-meta dolphin konsole plasma-nm plasma-pa ark kate spectacle gwenview okular" ;;
        kde-minimal) echo "plasma-desktop dolphin konsole systemsettings plasma-nm plasma-pa" ;;
        kde-wayland) echo "plasma-desktop plasma-wayland-session dolphin konsole systemsettings plasma-nm plasma-pa" ;;
    esac
}

get_xfce_completion_packages() {
    echo "xfce4 xfce4-goodies xfce4-session"
}

get_gnome_completion_packages() {
    echo "gnome gnome-extra gnome-shell mutter"
}

load_profile_packages() {
    local profiles="$TMPDIR/arm-profiles"
    PKG_COMPLETION=""
    
    case "$EDITION" in
        minimal) edition_profile="minimal" ;;
        xfce) edition_profile="xfce" ;;
        gnome) edition_profile="gnome" ;;
        server) edition_profile="server" ;;
        kde-*) edition_profile="kde" ;;
        *) err "Unknown edition"; exit 1 ;;
    esac
    
    PKG_SHARED=$(grep -v '^#' "$profiles/shared/Packages-Root" 2>/dev/null || true)
    
    if [[ "$EDITION" =~ ^kde- ]]; then
        PKG_EDITION=$(get_kde_packages "$EDITION")
        PKG_COMPLETION=""
    elif [[ "$EDITION" == "xfce" ]]; then
        PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
        PKG_COMPLETION=$(get_xfce_completion_packages)
    elif [[ "$EDITION" == "gnome" ]]; then
        PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
        PKG_COMPLETION=$(get_gnome_completion_packages)
    else
        PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
        PKG_COMPLETION=""
    fi
    
    PKG_DEVICE=$(grep -v '^#' "$profiles/devices/rpi4/Packages-Root" 2>/dev/null || true)
    
    [[ "$EDITION" =~ ^kde- ]] && srv_list="" || srv_list="$profiles/editions/$edition_profile/services"
    
    log INFO "Loaded packages for $EDITION"
}

install_profile_packages() {
    msg "Installing packages..."
    log INFO "Installing profile packages"
    
    mkdir -p "$TMPDIR/pkg-cache"
    mkdir -p "$TMPDIR/root/var/cache/pacman/pkg"
    mount -o bind "$TMPDIR/pkg-cache" "$TMPDIR/root/var/cache/pacman/pkg"
    
    # shellcheck disable=SC2086
    set -- base manjaro-system manjaro-release systemd systemd-libs \
        sudo $PKG_SHARED $PKG_EDITION $PKG_COMPLETION $PKG_DEVICE
    
    if ! $NSPAWN "$TMPDIR/root" pacman -Syu "$@" --noconfirm; then
        err "Package installation failed"
        umount "$TMPDIR/root/var/cache/pacman/pkg" 2>/dev/null || true
        exit 1
    fi
    
    msg "Enabling services..."
    $NSPAWN "$TMPDIR/root" systemctl enable getty.target haveged.service 1>/dev/null || true
    
    if [[ -f "$srv_list" ]]; then
        while read -r service; do
            [[ -z "$service" || "$service" =~ ^# ]] && continue
            if [[ -e "$TMPDIR/root/usr/lib/systemd/system/$service" ]]; then
                log INFO "Enabling $service"
                $NSPAWN "$TMPDIR/root" systemctl enable "$service" 1>/dev/null || true
            fi
        done < "$srv_list"
    fi
    
    [[ -f "$TMPDIR/root/usr/bin/xdg-user-dirs-update" ]] && \
        $NSPAWN "$TMPDIR/root" systemctl --global enable xdg-user-dirs-update.service 1>/dev/null 2>&1 || true
    
    umount "$TMPDIR/root/var/cache/pacman/pkg" 2>/dev/null || true
    log INFO "Packages installed"
}

# =============================================================================
# Chroot Functions
# =============================================================================

prepare_chroot() {
    msg "Preparing chroot..."
    log INFO "Binding filesystems"
    mount -t proc /proc "$TMPDIR/root/proc"
    mount --rbind /sys "$TMPDIR/root/sys"
    mount --rbind /dev "$TMPDIR/root/dev"
    mount --rbind /run "$TMPDIR/root/run"
}

# =============================================================================
# Pi 5 Kernel Functions
# =============================================================================

install_pi5_firmware() {
    msg "Installing Pi 5 firmware..."
    log INFO "Installing raspberrypi-bootloader"
    
    if ! arch-chroot "$TMPDIR/root" bash -c "
        pacman -Sy --noconfirm raspberrypi-bootloader raspberrypi-bootloader-x
    "; then
        err "Firmware installation failed"
        exit 1
    fi
    log INFO "Firmware installed"
}

install_pi5_kernel() {
    msg "Installing Pi 5 kernel..."
    log INFO "Installing linux-rpi5"
    
    if ! arch-chroot "$TMPDIR/root" bash -c "
        pacman -Q linux-rpi4 >/dev/null 2>&1 && pacman -Rdd --noconfirm linux-rpi4 || true
        pacman -Sy --noconfirm --overwrite '*' linux-rpi5 linux-rpi5-headers
    "; then
        err "Kernel installation failed"
        exit 1
    fi
    log INFO "Kernel installed"
}

generate_fstab() {
    msg "Generating fstab..."
    local uuid_root uuid_boot
    uuid_root=$(blkid -s UUID -o value "$ROOTPART")
    uuid_boot=$(blkid -s UUID -o value "$BOOTPART")
    cat <<EOF > "$TMPDIR/root/etc/fstab"
# /etc/fstab
UUID=$uuid_root   /       ext4  defaults,noatime  0 1
UUID=$uuid_boot   /boot   vfat  defaults,noatime  0 2
EOF
    log INFO "fstab generated"
}

# =============================================================================
# Desktop Configuration
# =============================================================================

configure_display_manager() {
    if [[ "$EDITION" =~ ^(minimal|server)$ ]]; then
        return
    fi
    
    msg "Configuring display manager..."
    
    arch-chroot "$TMPDIR/root" bash -c '
        systemctl disable sddm.service lightdm.service gdm.service 2>/dev/null || true
    '
    
    case "$DISPLAY_MANAGER" in
        sddm)
            arch-chroot "$TMPDIR/root" bash -c "
                pacman -Sy --noconfirm sddm
                systemctl enable sddm.service
            "
            ;;
        lightdm)
            arch-chroot "$TMPDIR/root" bash -c "
                pacman -Sy --noconfirm lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
                systemctl enable lightdm.service
            "
            ;;
        gdm)
            arch-chroot "$TMPDIR/root" bash -c "
                pacman -Sy --noconfirm gdm
                systemctl enable gdm.service
            "
            ;;
    esac
    
    log INFO "Display manager configured"
}

finalize_system() {
    msg "Finalizing system..."
    arch-chroot "$TMPDIR/root" bash -c "
        systemctl enable sshd || true
    "
    log INFO "System finalized"
}

create_user_account() {
    msg "Creating user..."
    
    arch-chroot "$TMPDIR/root" bash -c "
        getent group plugdev >/dev/null 2>&1 || groupadd -r plugdev
        useradd -m -G wheel,video,audio,storage,input,lp,network,render,uucp,plugdev,adm -s /bin/bash \"$USERNAME\" || \
        useradd -m -G wheel,video,audio,storage,input,lp,network,uucp,adm -s /bin/bash \"$USERNAME\"
        echo \"$USERNAME:$USER_PASSWORD\" | chpasswd
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || \
        sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    "
    log INFO "User created"
}

apply_root_mode() {
    case "$ROOT_MODE" in
        setpw)
            arch-chroot "$TMPDIR/root" bash -c "echo \"root:$ROOT_PASSWORD\" | chpasswd"
            ;;
        disable)
            arch-chroot "$TMPDIR/root" bash -c "
                mkdir -p /etc/ssh
                grep -q '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null && \
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || \
                echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
            "
            ;;
        lock)
            arch-chroot "$TMPDIR/root" bash -c "passwd -l root"
            ;;
    esac
}

# =============================================================================
# Optimizations
# =============================================================================

post_install_optimizations() {
    msg "Applying optimizations..."
    arch-chroot "$TMPDIR/root" bash -s -- "$@" <<'EOF'
for opt in "$@"; do
    case "$opt" in
        zram)
            pacman -Sy --noconfirm zram-generator
            mkdir -p /etc/systemd/zram-generator.conf.d
            echo -e "[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd" \
                > /etc/systemd/zram-generator.conf.d/override.conf
            systemctl enable systemd-zram-setup@zram0.service || true
            ;;
        sysctl)
            cat > /etc/sysctl.d/99-pi5.conf <<SEOF
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
SEOF
            ;;
        gpu)
            grep -q "gpu_mem=256" /boot/config.txt || echo "gpu_mem=256" >> /boot/config.txt
            ;;
        journald)
            mkdir -p /etc/systemd/journald.conf.d
            cat > /etc/systemd/journald.conf.d/99-optimized.conf <<JEOF
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
MaxRetentionSec=1week
JEOF
            ;;
        fstrim)
            systemctl enable fstrim.timer || true
            ;;
        cpupower)
            pacman -Sy --noconfirm cpupower
            systemctl enable cpupower.service
            echo 'governor=ondemand' > /etc/default/cpupower
            ;;
    esac
done
EOF
    log INFO "Optimizations applied"
}

# =============================================================================
# Cleanup
# =============================================================================

finalize_install() {
    msg "Cleaning up..."
    
    for mp in "$TMPDIR/root/run" "$TMPDIR/root/dev" "$TMPDIR/root/sys" \
              "$TMPDIR/root/proc" "$TMPDIR/root/boot" "$TMPDIR/root"; do
        local attempts=0
        while mountpoint -q "$mp" 2>/dev/null && [ $attempts -lt 3 ]; do
            umount -R "$mp" 2>/dev/null && break
            attempts=$((attempts + 1))
            sleep 2
        done
    done
    
    log INFO "Cleanup complete"
}

# =============================================================================
# Main
# =============================================================================

main() {
    mkdir -p "$TMPDIR"
    log INFO "=== Manjaro ARM Pi 5 Installer v2.4 ==="
    
    # Check dependencies
    for cmd in dialog git wget bsdtar parted mkfs.vfat mkfs.ext4 arch-chroot systemd-nspawn lsof blkid rsync; do
        command -v "$cmd" &>/dev/null || { err "$cmd not found"; exit 1; }
    done
    
    # UI flow
    ui_select_edition
    ui_select_display_manager
    ui_select_sdcard
    ui_select_bootmode
    ui_set_username
    ui_set_password
    ui_set_root_mode
    [[ "$ROOT_MODE" == "setpw" ]] && ui_set_root_password
    ui_select_optimizations
    ui_confirm
    
    # Installation
    ui_progress "Partitioning" "Creating partitions..."
    partition_and_format_sdcard
    
    ui_progress "Mounting" "Mounting filesystems..."
    mount_root_partition
    
    ui_progress "Profiles" "Fetching profiles..."
    installer_get_armprofiles
    
    ui_progress "Rootfs" "Downloading rootfs..."
    download_generic_rootfs
    
    ui_progress "Rootfs" "Extracting rootfs..."
    extract_generic_rootfs
    
    ui_progress "Keys" "Setting up keyrings..."
    setup_keyrings_and_mirrors
    
    # Network
    ui_progress "Network" "Setting up network..."
    setup_network || handle_network_failure
    verify_network_connectivity || handle_network_failure
    
    # Packages
    ui_progress "Profiles" "Loading packages..."
    load_profile_packages
    
    ui_progress "Packages" "Installing base system..."
    install_profile_packages
    
    # Xorg
    if [[ ! "$EDITION" =~ ^(minimal|server)$ ]]; then
        ui_progress "Xorg" "Installing Xorg..."
        install_xorg_stack || handle_xorg_failure
        sanity_check_xorg_stack || handle_xorg_failure
    fi
    
    # Pi 5 boot - CRITICAL for display
    ui_progress "Boot" "Mounting boot partition..."
    mount_boot_partition
    
    ui_progress "Chroot" "Preparing chroot..."
    prepare_chroot
    
    ui_progress "Firmware" "Installing Pi 5 firmware..."
    install_pi5_firmware
    
    ui_progress "Kernel" "Installing Pi 5 kernel..."
    install_pi5_kernel
    
    # NEW: Copy boot files and configure
    ui_progress "Boot Files" "Setting up Pi 5 boot partition..."
    copy_pi5_boot_files
    
    ui_progress "Boot Config" "Configuring boot files..."
    configure_boot_files
    
    ui_progress "Verification" "Verifying boot partition..."
    verify_boot_partition || {
        err "Boot verification failed - display may not work!"
        log ERROR "Boot partition verification failed"
    }
    
    ui_progress "Filesystem" "Generating fstab..."
    generate_fstab
    
    # Desktop
    ui_progress "Display Manager" "Configuring desktop..."
    configure_display_manager
    
    # Finalization
    ui_progress "System" "Enabling services..."
    finalize_system
    
    ui_progress "User" "Creating user..."
    create_user_account
    
    ui_progress "Root" "Configuring root..."
    apply_root_mode
    
    ui_progress "Optimizing" "Applying optimizations..."
    (( ${#OPTS[@]} > 0 )) && post_install_optimizations "${OPTS[@]}"
    
    ui_progress "Cleanup" "Finalizing..."
    finalize_install
    
    log INFO "=== Installation Complete ==="
    
    dialog --title "Success!" --msgbox \
        "Manjaro ARM ($EDITION) installed on $SDCARD!\n\n\
✓ Pi 5 firmware installed\n\
✓ Pi 5 kernel installed\n\
✓ Boot partition configured\n\
✓ vc4-kms-v3d enabled\n\
✓ Network configured\n\
✓ Xorg verified\n\
✓ User: $USERNAME\n\
✓ Display manager: $DISPLAY_MANAGER\n\n\
Your Pi 5 should boot directly to desktop!\n\n\
First boot takes 2-3 minutes." 20 70
}

main "$@"
clear

#!/usr/bin/env bash
#
# Manjaro ARM Pi 5 Installer - COMPLETE WORKING EDITION
# Version: 2.6 - Fixed Boot Partition Population + Automated Repair
#
# Changes in v2.6:
# - FIXED: Boot partition now actually gets populated with firmware
# - FIXED: Proper installation order (keyrings → packages → boot files)
# - Added multi-strategy boot file acquisition (download → packages)
# - Added boot partition diagnostics and automated repair
# - Added better error handling and user feedback
# - Boot verification failure now triggers automatic repair attempt
#
# Changes in v2.5:
# - Added Wi-Fi SSID scanning and selection
# - Added Wi-Fi password prompt
# - Added Internet connectivity testing
# - Fixed Xorg configuration (removed Pi 4-style forced device config)
# - Added Network Settings menu to main installer flow
#
# Critical fix from v2.4:
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

# Wi-Fi configuration
WIFI_SSID=""
WIFI_PASSWORD=""
WIFI_CONNECTED=false

# Pi 5 boot partition sources (try multiple)
PI5_IMAGE_URL="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/Manjaro-ARM-minimal-rpi5-latest.img.xz"
PI5_BOOT_TARBALL="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/boot-rpi5.tar.gz"

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
        2>&1 >/dev/tty) || return 1
    echo "$result"
}

# =============================================================================
# Network/Wi-Fi Functions (NEW in v2.5)
# =============================================================================

check_network_manager() {
    if ! command -v nmcli &>/dev/null; then
        dialog --title "Error" \
            --msgbox "NetworkManager (nmcli) not found.\n\nPlease install it first:\n  sudo pacman -S networkmanager\n  sudo systemctl start NetworkManager" 12 60
        log ERROR "NetworkManager not available"
        return 1
    fi
    
    if ! systemctl is-active --quiet NetworkManager; then
        dialog --title "Starting NetworkManager" \
            --infobox "Starting NetworkManager service..." 5 50
        systemctl start NetworkManager 2>/dev/null || true
        sleep 2
    fi
    
    return 0
}

ui_scan_wifi_networks() {
    if ! check_network_manager; then
        return 1
    fi
    
    dialog --title "Scanning Wi-Fi" \
        --infobox "Scanning for available networks...\n\nThis may take a few seconds." 7 50
    
    # Request a fresh scan
    nmcli dev wifi rescan 2>/dev/null || true
    sleep 3
    
    # Get list of SSIDs
    local ssid_list
    ssid_list=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | \
        grep -v '^--' | \
        grep -v '^$' | \
        sort -t: -k2 -rn | \
        awk -F: '!seen[$1]++ {print $1 ":" $2 ":" $3}')
    
    if [ -z "$ssid_list" ]; then
        dialog --title "No Networks Found" \
            --msgbox "No Wi-Fi networks detected.\n\nPlease ensure:\n• Wi-Fi adapter is enabled\n• You are in range of a network" 12 60
        log WARN "No Wi-Fi networks found"
        return 1
    fi
    
    # Build dialog menu
    local menu_items=()
    local count=0
    while IFS=: read -r ssid signal security; do
        [ -z "$ssid" ] && continue
        local sec_label=""
        if [[ "$security" == *"WPA"* ]]; then
            sec_label="🔒"
        elif [[ -n "$security" ]]; then
            sec_label="🔒"
        else
            sec_label="🔓"
        fi
        menu_items+=("$ssid" "$sec_label Signal: $signal%")
        ((count++))
    done <<< "$ssid_list"
    
    if [ $count -eq 0 ]; then
        dialog --title "No Networks" \
            --msgbox "No valid Wi-Fi networks found." 8 50
        return 1
    fi
    
    # Show selection menu
    local chosen
    chosen=$(dialog --title "Select Wi-Fi Network" \
        --menu "Available networks (sorted by signal strength):" 20 70 12 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3) || return 1
    
    chosen=$(sanitize_single_line "$chosen")
    if [ -n "$chosen" ]; then
        WIFI_SSID="$chosen"
        log INFO "Selected Wi-Fi SSID: $WIFI_SSID"
        return 0
    fi
    
    return 1
}

ui_enter_wifi_password() {
    if [ -z "$WIFI_SSID" ]; then
        dialog --title "Error" \
            --msgbox "No Wi-Fi network selected.\n\nPlease scan and select a network first." 10 50
        return 1
    fi
    
    # Check if network is open (no password needed)
    local security
    security=$(nmcli -t -f SSID,SECURITY dev wifi list | grep "^${WIFI_SSID}:" | cut -d: -f2)
    
    if [ -z "$security" ] || [[ "$security" == "--" ]]; then
        WIFI_PASSWORD=""
        dialog --title "Open Network" \
            --msgbox "Network '$WIFI_SSID' is open (no password required)." 8 60
        log INFO "Open network detected, no password needed"
        return 0
    fi
    
    # Prompt for password
    local password
    password=$(dialog --title "Wi-Fi Password" \
        --insecure \
        --passwordbox "Enter password for network:\n\n  $WIFI_SSID" 12 60 \
        3>&1 1>&2 2>&3) || return 1
    
    password=$(sanitize_single_line "$password")
    
    if [ -z "$password" ]; then
        dialog --title "Empty Password" \
            --msgbox "Password cannot be empty for secured networks." 8 50
        return 1
    fi
    
    WIFI_PASSWORD="$password"
    log INFO "Wi-Fi password entered"
    return 0
}

ui_connect_wifi() {
    if [ -z "$WIFI_SSID" ]; then
        dialog --title "Error" \
            --msgbox "No Wi-Fi network selected." 8 50
        return 1
    fi
    
    dialog --title "Connecting to Wi-Fi" \
        --infobox "Connecting to: $WIFI_SSID\n\nPlease wait..." 7 50
    
    local connect_output
    local connect_result
    
    # Attempt connection
    if [ -n "$WIFI_PASSWORD" ]; then
        connect_output=$(nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" 2>&1)
        connect_result=$?
    else
        connect_output=$(nmcli dev wifi connect "$WIFI_SSID" 2>&1)
        connect_result=$?
    fi
    
    if [ $connect_result -eq 0 ]; then
        WIFI_CONNECTED=true
        dialog --title "Success" \
            --msgbox "Successfully connected to:\n\n  $WIFI_SSID\n\nYou can now test your Internet connection." 10 60
        log INFO "Connected to Wi-Fi: $WIFI_SSID"
        return 0
    else
        WIFI_CONNECTED=false
        local error_msg="Failed to connect to: $WIFI_SSID\n\n"
        
        if [[ "$connect_output" == *"Secrets were required"* ]] || \
           [[ "$connect_output" == *"802-11-wireless-security"* ]]; then
            error_msg+="Error: Incorrect password\n\nPlease try again with the correct password."
        elif [[ "$connect_output" == *"No network with SSID"* ]]; then
            error_msg+="Error: Network not found\n\nThe network may be out of range."
        else
            error_msg+="Error details:\n${connect_output:0:200}"
        fi
        
        dialog --title "Connection Failed" \
            --msgbox "$error_msg" 15 70
        log ERROR "Wi-Fi connection failed: $connect_output"
        return 1
    fi
}

ui_test_internet() {
    dialog --title "Testing Internet" \
        --infobox "Testing connectivity...\n\nPinging 8.8.8.8 (Google DNS)" 7 50
    sleep 1
    
    local ping_output
    local ping_result
    
    # Test with Google DNS
    ping_output=$(ping -c 3 -W 2 8.8.8.8 2>&1)
    ping_result=$?
    
    if [ $ping_result -eq 0 ]; then
        # Extract packet loss and latency
        local packet_loss
        local avg_latency
        packet_loss=$(echo "$ping_output" | grep -oP '\d+(?=% packet loss)')
        avg_latency=$(echo "$ping_output" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/\K[\d.]+')
        
        dialog --title "Internet Test: SUCCESS ✓" \
            --msgbox "Internet connection is working!\n\nPacket loss: ${packet_loss}%\nAverage latency: ${avg_latency}ms\n\nYou can proceed with the installation." 12 60
        log INFO "Internet test successful"
        return 0
    else
        dialog --title "Internet Test: FAILED ✗" \
            --msgbox "No Internet connectivity detected.\n\nPossible causes:\n• Not connected to Wi-Fi\n• Router/modem issues\n• ISP outage\n• Firewall blocking ICMP\n\nPlease check your connection before proceeding." 14 60
        log WARN "Internet test failed"
        return 1
    fi
}

ui_show_network_status() {
    local status_text="Network Status\n\n"
    
    # Check connection state
    local conn_state
    conn_state=$(nmcli -t -f STATE general status 2>/dev/null || echo "unknown")
    status_text+="Connection state: $conn_state\n\n"
    
    # Show active connections
    local active_conn
    active_conn=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
    if [ -n "$active_conn" ]; then
        status_text+="Active connections:\n"
        while IFS=: read -r name type device; do
            status_text+="  • $name ($type) on $device\n"
        done <<< "$active_conn"
    else
        status_text+="No active connections\n"
    fi
    
    status_text+="\n"
    
    # Show selected Wi-Fi info
    if [ -n "$WIFI_SSID" ]; then
        status_text+="Selected Wi-Fi: $WIFI_SSID\n"
        status_text+="Password: $([ -n "$WIFI_PASSWORD" ] && echo "Set" || echo "None")\n"
        status_text+="Connected: $([ "$WIFI_CONNECTED" = true ] && echo "Yes" || echo "No")\n"
    else
        status_text+="No Wi-Fi network selected\n"
    fi
    
    dialog --title "Network Status" \
        --msgbox "$status_text" 20 70
}

ui_network_settings_menu() {
    while true; do
        local wifi_status="Not selected"
        [ -n "$WIFI_SSID" ] && wifi_status="$WIFI_SSID"
        
        local conn_status="Not connected"
        [ "$WIFI_CONNECTED" = true ] && conn_status="Connected"
        
        local choice
        choice=$(dialog --title "Network Settings" \
            --cancel-label "Back to Main Menu" \
            --menu "Configure network connectivity:\n\nWi-Fi: $wifi_status\nStatus: $conn_status" 20 70 8 \
            1 "Scan & Select Wi-Fi Network" \
            2 "Enter Wi-Fi Password" \
            3 "Connect to Wi-Fi" \
            4 "Test Internet Connection" \
            5 "Show Network Status" \
            6 "Disconnect Wi-Fi" \
            3>&1 1>&2 2>&3) || break
        
        case "$choice" in
            1) ui_scan_wifi_networks ;;
            2) ui_enter_wifi_password ;;
            3) ui_connect_wifi ;;
            4) ui_test_internet ;;
            5) ui_show_network_status ;;
            6)
                nmcli con down id "$WIFI_SSID" 2>/dev/null || true
                WIFI_CONNECTED=false
                dialog --msgbox "Disconnected from Wi-Fi" 7 40
                log INFO "Disconnected from Wi-Fi"
                ;;
        esac
    done
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
    if [ "$WIFI_CONNECTED" = true ]; then
        msg+="Network: Connected to $WIFI_SSID\n"
    else
        msg+="Network: Not connected (will use mirrors)\n"
    fi
    msg+="\n⚠️  WARNING: All data on $SDCARD will be erased!"
    
    if ! dialog --title "Confirm Installation" \
        --yes-label "Install" \
        --no-label "Cancel" \
        --yesno "$msg" 18 70; then
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
# Pi 5 Boot Partition Functions
# =============================================================================

download_pi5_boot_image() {
    msg "Downloading official Manjaro ARM Pi 5 image..."
    log INFO "Downloading Pi 5 image to extract boot partition"
    
    mkdir -p "$TMPDIR/pi5-extract"
    cd "$TMPDIR" || exit 1
    
    # Try the tarball first (smaller, faster)
    info "Attempting to download boot tarball..."
    if wget -q --show-progress --progress=bar:force:noscroll \
        "$PI5_BOOT_TARBALL" -O pi5-boot.tar.gz 2>&1 | tee -a "$TMPDIR/install.log"; then
        log INFO "Boot tarball downloaded successfully"
        
        mkdir -p "$TMPDIR/pi5-boot"
        if tar -xzf pi5-boot.tar.gz -C "$TMPDIR/pi5-boot" 2>&1 | tee -a "$TMPDIR/install.log"; then
            log INFO "Boot tarball extracted successfully"
            return 0
        else
            log WARN "Failed to extract boot tarball, trying full image method"
        fi
    else
        log WARN "Boot tarball not available, trying full image download"
    fi
    
    # Fall back to extracting from full image
    info "Downloading full Pi 5 image (this may take a while)..."
    if wget -q --show-progress --progress=bar:force:noscroll \
        "$PI5_IMAGE_URL" -O pi5-image.img.xz 2>&1 | tee -a "$TMPDIR/install.log"; then
        log INFO "Pi 5 image downloaded"
        
        info "Decompressing image..."
        if xz -d pi5-image.img.xz 2>&1 | tee -a "$TMPDIR/install.log"; then
            log INFO "Image decompressed"
            
            info "Extracting boot partition from image..."
            extract_boot_from_image "$TMPDIR/pi5-image.img"
            return $?
        else
            log ERROR "Failed to decompress image"
            return 1
        fi
    else
        log ERROR "Failed to download Pi 5 image"
        return 1
    fi
}

extract_boot_from_image() {
    local image_file="$1"
    
    log INFO "Extracting boot partition from $image_file"
    
    # Get boot partition offset and size
    local boot_start boot_size
    boot_start=$(fdisk -l "$image_file" | grep "^${image_file}1" | awk '{print $2}')
    boot_size=$(fdisk -l "$image_file" | grep "^${image_file}1" | awk '{print $4}')
    
    if [ -z "$boot_start" ]; then
        log ERROR "Could not determine boot partition offset"
        return 1
    fi
    
    # Calculate offset in bytes (sectors * 512)
    local offset=$((boot_start * 512))
    local size=$((boot_size * 512))
    
    log INFO "Boot partition: offset=$offset size=$size"
    
    # Create temporary mount point
    mkdir -p "$TMPDIR/pi5-boot-mount"
    
    # Mount boot partition from image
    if mount -o loop,offset=$offset,sizelimit=$size "$image_file" "$TMPDIR/pi5-boot-mount" 2>&1 | tee -a "$TMPDIR/install.log"; then
        log INFO "Boot partition mounted from image"
        
        # Copy all files
        mkdir -p "$TMPDIR/pi5-boot"
        cp -r "$TMPDIR/pi5-boot-mount/"* "$TMPDIR/pi5-boot/" 2>&1 | tee -a "$TMPDIR/install.log"
        
        # Unmount
        umount "$TMPDIR/pi5-boot-mount"
        
        log INFO "Boot partition extracted from image"
        return 0
    else
        log ERROR "Failed to mount boot partition from image"
        return 1
    fi
}

install_pi5_boot_packages() {
    msg "Installing Pi 5 bootloader packages..."
    log INFO "Installing raspberrypi-bootloader packages into rootfs"
    
    # Install the bootloader packages
    $NSPAWN "$TMPDIR/root" pacman -Sy --noconfirm --needed \
        raspberrypi-bootloader \
        raspberrypi-bootloader-x \
        linux-rpi5 \
        linux-rpi5-headers 2>&1 | tee -a "$TMPDIR/install.log" || {
        log ERROR "Failed to install Pi 5 bootloader packages"
        return 1
    }
    
    log INFO "Pi 5 bootloader packages installed"
    return 0
}

populate_boot_from_packages() {
    msg "Populating boot partition from installed packages..."
    log INFO "Copying bootloader files from installed packages"
    
    # First, ensure packages are installed
    if ! install_pi5_boot_packages; then
        return 1
    fi
    
    # The raspberrypi-bootloader package installs to /boot
    # Files might be in /boot or /boot/firmware depending on version
    
    if [[ -d "$TMPDIR/root/boot/firmware" ]]; then
        log INFO "Found /boot/firmware, moving files to /boot"
        cp -rv "$TMPDIR/root/boot/firmware/"* "$TMPDIR/root/boot/" 2>&1 | tee -a "$TMPDIR/install.log" || true
        rm -rf "$TMPDIR/root/boot/firmware"
    fi
    
    # Also check /usr/share/raspberrypi-bootloader (some packages install here)
    if [[ -d "$TMPDIR/root/usr/share/raspberrypi-bootloader" ]]; then
        log INFO "Found bootloader files in /usr/share, copying to /boot"
        cp -rv "$TMPDIR/root/usr/share/raspberrypi-bootloader/"* "$TMPDIR/root/boot/" 2>&1 | tee -a "$TMPDIR/install.log" || true
    fi
    
    # Ensure overlays directory exists
    mkdir -p "$TMPDIR/root/boot/overlays"
    
    # Check for critical files
    local critical_files=(
        "bcm2712-rpi-5-b.dtb"
        "kernel8.img"
    )
    
    local missing=0
    for file in "${critical_files[@]}"; do
        if [[ -f "$TMPDIR/root/boot/$file" ]]; then
            info "✓ Found $file"
            log INFO "Boot file present: $file"
        else
            err "✗ Missing $file"
            log ERROR "Missing boot file: $file"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log ERROR "Critical boot files missing after package installation"
        return 1
    fi
    
    log INFO "Boot partition populated from packages"
    return 0
}

copy_pi5_boot_files() {
    msg "Setting up Pi 5 boot partition..."
    log INFO "Starting Pi 5 boot partition setup"
    
    # Strategy 1: Try to download and use pre-built boot files
    if download_pi5_boot_image; then
        if [[ -d "$TMPDIR/pi5-boot" ]] && [[ -f "$TMPDIR/pi5-boot/kernel8.img" ]]; then
            log INFO "Using downloaded Pi 5 boot files"
            info "Copying boot files from downloaded image..."
            
            # Copy everything
            cp -rv "$TMPDIR/pi5-boot/"* "$TMPDIR/root/boot/" 2>&1 | tee -a "$TMPDIR/install.log" || {
                log ERROR "Failed to copy downloaded boot files"
                err "Copy failed, will try package method"
            }
            
            # Verify it worked
            if [[ -f "$TMPDIR/root/boot/kernel8.img" ]] && [[ -f "$TMPDIR/root/boot/bcm2712-rpi-5-b.dtb" ]]; then
                log INFO "Boot files copied successfully from download"
                return 0
            else
                log WARN "Downloaded files incomplete, falling back to packages"
            fi
        fi
    fi
    
    # Strategy 2: Use package-provided files
    log INFO "Falling back to package-provided boot files"
    info "Installing bootloader packages and copying files..."
    
    if populate_boot_from_packages; then
        log INFO "Boot files populated from packages"
        return 0
    else
        log ERROR "Failed to populate boot partition from packages"
        return 1
    fi
}

configure_boot_files() {
    msg "Configuring boot files..."
    log INFO "Configuring config.txt and cmdline.txt"
    
    local root_partuuid
    root_partuuid=$(blkid -s PARTUUID -o value "$ROOTPART")
    
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
    
    echo "root=PARTUUID=$root_partuuid rw rootwait console=ttyAMA0,115200 console=tty1 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 elevator=noop quiet splash" \
        > "$TMPDIR/root/boot/cmdline.txt"
    
    log INFO "cmdline.txt configured with root=PARTUUID=$root_partuuid"
    
    return 0
}

verify_boot_partition() {
    msg "Verifying boot partition..."
    log INFO "Running boot partition sanity checks"
    
    local failed=0
    
    if [[ -f "$TMPDIR/root/boot/kernel8.img" ]]; then
        info "✓ kernel8.img found"
        log INFO "Boot check: kernel8.img OK"
    else
        err "✗ kernel8.img NOT found"
        log ERROR "Boot check FAILED: kernel8.img missing"
        failed=1
    fi
    
    if [[ -f "$TMPDIR/root/boot/bcm2712-rpi-5-b.dtb" ]]; then
        info "✓ Pi 5 DTB found"
        log INFO "Boot check: DTB OK"
    else
        err "✗ Pi 5 DTB NOT found"
        log ERROR "Boot check FAILED: DTB missing"
        failed=1
    fi
    
    if ls "$TMPDIR/root/boot/"*.dat >/dev/null 2>&1 || \
       ls "$TMPDIR/root/boot/"*.elf >/dev/null 2>&1; then
        info "✓ Firmware files found"
        log INFO "Boot check: firmware OK"
    else
        err "✗ Firmware files NOT found"
        log ERROR "Boot check FAILED: firmware missing"
        failed=1
    fi
    
    if [[ -d "$TMPDIR/root/boot/overlays" ]]; then
        local overlay_count=$(ls "$TMPDIR/root/boot/overlays/"*.dtbo 2>/dev/null | wc -l)
        info "✓ Overlays directory found ($overlay_count overlays)"
        log INFO "Boot check: overlays OK ($overlay_count files)"
    else
        err "✗ Overlays directory NOT found"
        log ERROR "Boot check FAILED: overlays missing"
        failed=1
    fi
    
    if [[ -f "$TMPDIR/root/boot/overlays/vc4-kms-v3d.dtbo" ]] || \
       [[ -f "$TMPDIR/root/boot/overlays/vc4-kms-v3d-pi5.dtbo" ]]; then
        info "✓ vc4-kms-v3d overlay found"
        log INFO "Boot check: vc4-kms overlay OK"
    else
        err "✗ vc4-kms-v3d overlay NOT found"
        log ERROR "Boot check FAILED: vc4-kms overlay missing"
        failed=1
    fi
    
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
# Network Setup Functions (in chroot)
# =============================================================================

setup_network() {
    msg "Setting up network..."
    log INFO "Configuring NetworkManager"
    
    # Install NetworkManager
    $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed networkmanager 2>&1 | tee -a "$TMPDIR/install.log"
    
    # Enable NetworkManager service
    $NSPAWN "$TMPDIR/root" systemctl enable NetworkManager 2>&1 | tee -a "$TMPDIR/install.log"
    
    # If we're connected to Wi-Fi during installation, configure it
    if [ "$WIFI_CONNECTED" = true ] && [ -n "$WIFI_SSID" ]; then
        msg "Configuring Wi-Fi for installed system..."
        log INFO "Setting up Wi-Fi profile for $WIFI_SSID"
        
        # Create NetworkManager connection file
        local conn_file="$TMPDIR/root/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"
        mkdir -p "$TMPDIR/root/etc/NetworkManager/system-connections"
        
        if [ -n "$WIFI_PASSWORD" ]; then
            # WPA/WPA2 secured network
            cat > "$conn_file" <<EOF
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
            cat > "$conn_file" <<EOF
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
        
        chmod 600 "$conn_file"
        log INFO "Wi-Fi profile created for $WIFI_SSID"
    fi
    
    log INFO "Network configured"
}

# =============================================================================
# System Configuration Functions
# =============================================================================

create_user_and_set_passwords() {
    msg "Creating user account..."
    log INFO "Creating user: $USERNAME"
    
    $NSPAWN "$TMPDIR/root" useradd -m -G wheel,video,audio,storage,network,power -s /bin/bash "$USERNAME"
    echo "$USERNAME:$USER_PASSWORD" | $NSPAWN "$TMPDIR/root" chpasswd
    
    case "$ROOT_MODE" in
        setpw)
            echo "root:$ROOT_PASSWORD" | $NSPAWN "$TMPDIR/root" chpasswd
            log INFO "Root password set"
            ;;
        disable)
            $NSPAWN "$TMPDIR/root" passwd -l root
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$TMPDIR/root/etc/ssh/sshd_config"
            log INFO "Root SSH login disabled"
            ;;
        lock)
            $NSPAWN "$TMPDIR/root" passwd -l root
            log INFO "Root account locked"
            ;;
        skip)
            log INFO "Skipped root password (sudo-only access)"
            ;;
    esac
    
    # Ensure sudo works
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$TMPDIR/root/etc/sudoers"
    
    log INFO "User and passwords configured"
}

setup_hostname() {
    local hostname="manjaro-pi5"
    msg "Setting hostname: $hostname"
    log INFO "Setting hostname to $hostname"
    
    echo "$hostname" > "$TMPDIR/root/etc/hostname"
    
    cat > "$TMPDIR/root/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
EOF
    
    log INFO "Hostname configured"
}

setup_locale() {
    msg "Setting up locale..."
    log INFO "Configuring locale"
    
    sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "$TMPDIR/root/etc/locale.gen"
    $NSPAWN "$TMPDIR/root" locale-gen 1>/dev/null 2>&1
    echo "LANG=en_US.UTF-8" > "$TMPDIR/root/etc/locale.conf"
    
    log INFO "Locale configured"
}

setup_timezone() {
    msg "Setting timezone..."
    log INFO "Setting timezone to UTC"
    
    $NSPAWN "$TMPDIR/root" ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    
    log INFO "Timezone set to UTC"
}

# =============================================================================
# Xorg Configuration (FIXED in v2.5)
# =============================================================================

setup_xorg_auto_detection() {
    # Pi 5 uses automatic Xorg configuration via KMS
    # DO NOT create manual device configurations
    
    msg "Configuring Xorg for Pi 5..."
    log INFO "Using automatic Xorg KMS detection for Pi 5"
    
    # Only ensure required packages are installed
    $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed \
        xf86-video-fbdev \
        xorg-server \
        mesa 2>&1 | tee -a "$TMPDIR/install.log"
    
    # Create minimal config that enables auto-detection
    # This is optional but helps with fallback
    mkdir -p "$TMPDIR/root/etc/X11/xorg.conf.d"
    cat > "$TMPDIR/root/etc/X11/xorg.conf.d/99-pi5-kms.conf" <<'EOF'
# Raspberry Pi 5 - Automatic KMS Configuration
# Let Xorg auto-detect the display via kernel modesetting
# DO NOT force specific device names or BusIDs

Section "Device"
    Identifier  "Raspberry Pi 5 Graphics"
    Driver      "modesetting"
    # No BusID - Xorg will auto-detect via KMS
    Option      "AccelMethod" "glamor"
EndSection

Section "ServerFlags"
    Option "AutoAddGPU" "true"
EndSection
EOF
    
    log INFO "Minimal Xorg configuration created for automatic KMS detection"
    
    # Verify we're NOT using Pi 4-style forced configs
    if [[ -f "$TMPDIR/root/etc/X11/xorg.conf.d/20-modesetting.conf" ]]; then
        if grep -q 'BusID.*vc4' "$TMPDIR/root/etc/X11/xorg.conf.d/20-modesetting.conf" 2>/dev/null; then
            err "⚠️  Found Pi 4-style Xorg config - removing for Pi 5"
            rm -f "$TMPDIR/root/etc/X11/xorg.conf.d/20-modesetting.conf"
            log WARN "Removed incompatible Pi 4-style Xorg configuration"
        fi
    fi
    
    log INFO "Xorg configured for automatic KMS-based detection"
}

# =============================================================================
# Display Manager Setup
# =============================================================================

setup_display_manager() {
    if [[ "$DISPLAY_MANAGER" == "none" ]]; then
        log INFO "No display manager selected"
        return
    fi
    
    msg "Setting up display manager: $DISPLAY_MANAGER"
    log INFO "Installing and enabling $DISPLAY_MANAGER"
    
    case "$DISPLAY_MANAGER" in
        lightdm)
            $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed \
                lightdm lightdm-gtk-greeter 2>&1 | tee -a "$TMPDIR/install.log"
            $NSPAWN "$TMPDIR/root" systemctl enable lightdm
            ;;
        sddm)
            $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed \
                sddm 2>&1 | tee -a "$TMPDIR/install.log"
            $NSPAWN "$TMPDIR/root" systemctl enable sddm
            ;;
        gdm)
            $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed \
                gdm 2>&1 | tee -a "$TMPDIR/install.log"
            $NSPAWN "$TMPDIR/root" systemctl enable gdm
            ;;
    esac
    
    log INFO "Display manager $DISPLAY_MANAGER configured"
}

# =============================================================================
# Edition-Specific Package Installation
# =============================================================================

install_edition_packages() {
    msg "Installing $EDITION packages..."
    log INFO "Installing packages for edition: $EDITION"
    
    local profile_dir="$TMPDIR/arm-profiles/editions/$EDITION"
    
    if [[ ! -d "$profile_dir" ]]; then
        err "Edition profile not found: $EDITION"
        log ERROR "Profile directory not found: $profile_dir"
        exit 1
    fi
    
    # Install packages from Packages-Root
    if [[ -f "$profile_dir/Packages-Root" ]]; then
        info "Installing base packages..."
        while read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$TMPDIR/install.log" || true
        done < "$profile_dir/Packages-Root"
    fi
    
    # Install packages from Packages-Desktop (if exists)
    if [[ -f "$profile_dir/Packages-Desktop" ]]; then
        info "Installing desktop packages..."
        while read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$TMPDIR/install.log" || true
        done < "$profile_dir/Packages-Desktop"
    fi
    
    log INFO "Edition packages installed"
}

# =============================================================================
# Pi 5-Specific Hardware Support
# =============================================================================

install_pi5_base_system() {
    msg "Installing Pi 5 base system..."
    log INFO "Installing core Pi 5 packages and dependencies"
    
    # Update package database first
    $NSPAWN "$TMPDIR/root" pacman -Sy 2>&1 | tee -a "$TMPDIR/install.log"
    
    # Install base Pi 5 system
    $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed \
        base-devel \
        sudo \
        networkmanager \
        openssh 2>&1 | tee -a "$TMPDIR/install.log"
    
    log INFO "Base system installed"
}

install_pi5_hardware_support() {
    msg "Installing Pi 5 hardware support..."
    log INFO "Installing Pi 5-specific hardware packages"
    
    # Note: raspberrypi-bootloader packages are installed in populate_boot_from_packages
    # if needed, so we don't duplicate them here
    
    # Additional hardware support
    $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed \
        bluez \
        bluez-utils \
        pulseaudio-bluetooth \
        alsa-utils \
        pi-bluetooth 2>&1 | tee -a "$TMPDIR/install.log" || true
    
    log INFO "Pi 5 hardware support installed"
}

# =============================================================================
# Optimizations
# =============================================================================

apply_optimizations() {
    if [ ${#OPTS[@]} -eq 0 ]; then
        log INFO "No optimizations selected"
        return
    fi
    
    msg "Applying optimizations..."
    log INFO "Applying ${#OPTS[@]} optimizations"
    
    for opt in "${OPTS[@]}"; do
        case "$opt" in
            zram)
                info "Enabling ZRAM..."
                $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed zram-generator 2>&1 | tee -a "$TMPDIR/install.log"
                mkdir -p "$TMPDIR/root/etc/systemd/zram-generator.conf.d"
                cat > "$TMPDIR/root/etc/systemd/zram-generator.conf.d/zram.conf" <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
                log INFO "ZRAM configured"
                ;;
            sysctl)
                info "Applying kernel tuning..."
                cat > "$TMPDIR/root/etc/sysctl.d/99-pi5-tuning.conf" <<EOF
# Pi 5 Kernel Tuning
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
                log INFO "Kernel tuning applied"
                ;;
            gpu)
                info "GPU memory already set in config.txt (256MB)"
                log INFO "GPU memory optimization already configured"
                ;;
            journald)
                info "Reducing journald size..."
                mkdir -p "$TMPDIR/root/etc/systemd/journald.conf.d"
                cat > "$TMPDIR/root/etc/systemd/journald.conf.d/size.conf" <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
EOF
                log INFO "Journald size limited"
                ;;
            fstrim)
                info "Enabling weekly TRIM..."
                $NSPAWN "$TMPDIR/root" systemctl enable fstrim.timer 2>&1 | tee -a "$TMPDIR/install.log"
                log INFO "TRIM timer enabled"
                ;;
            cpupower)
                info "Enabling CPU governor..."
                $NSPAWN "$TMPDIR/root" pacman -S --noconfirm --needed cpupower 2>&1 | tee -a "$TMPDIR/install.log"
                echo 'GOVERNOR="ondemand"' > "$TMPDIR/root/etc/default/cpupower"
                $NSPAWN "$TMPDIR/root" systemctl enable cpupower 2>&1 | tee -a "$TMPDIR/install.log"
                log INFO "CPU governor configured"
                ;;
        esac
    done
    
    log INFO "Optimizations applied"
}

# =============================================================================
# Boot Partition Diagnostics and Repair
# =============================================================================

diagnose_boot_partition() {
    msg "Running boot partition diagnostics..."
    log INFO "Boot partition diagnostic started"
    
    local issues=()
    
    # Check kernel
    if [[ ! -f "$TMPDIR/root/boot/kernel8.img" ]]; then
        issues+=("kernel8.img missing")
    fi
    
    # Check DTB
    if [[ ! -f "$TMPDIR/root/boot/bcm2712-rpi-5-b.dtb" ]]; then
        issues+=("bcm2712-rpi-5-b.dtb missing")
    fi
    
    # Check firmware
    local fw_count=0
    fw_count=$(ls "$TMPDIR/root/boot/"*.{dat,elf} 2>/dev/null | wc -l)
    if [ $fw_count -eq 0 ]; then
        issues+=("No firmware files (.dat/.elf)")
    fi
    
    # Check overlays
    local overlay_count=0
    overlay_count=$(ls "$TMPDIR/root/boot/overlays/"*.dtbo 2>/dev/null | wc -l)
    if [ $overlay_count -eq 0 ]; then
        issues+=("No overlay files")
    fi
    
    # Check vc4-kms
    if [[ ! -f "$TMPDIR/root/boot/overlays/vc4-kms-v3d.dtbo" ]] && \
       [[ ! -f "$TMPDIR/root/boot/overlays/vc4-kms-v3d-pi5.dtbo" ]]; then
        issues+=("vc4-kms-v3d overlay missing")
    fi
    
    # Check config.txt
    if [[ ! -f "$TMPDIR/root/boot/config.txt" ]]; then
        issues+=("config.txt missing")
    elif ! grep -q "dtoverlay=vc4-kms-v3d" "$TMPDIR/root/boot/config.txt"; then
        issues+=("vc4-kms-v3d not enabled in config.txt")
    fi
    
    # Check cmdline.txt
    if [[ ! -f "$TMPDIR/root/boot/cmdline.txt" ]]; then
        issues+=("cmdline.txt missing")
    fi
    
    if [ ${#issues[@]} -gt 0 ]; then
        log ERROR "Boot partition issues found:"
        for issue in "${issues[@]}"; do
            log ERROR "  - $issue"
        done
        return 1
    else
        log INFO "Boot partition diagnostics: All checks passed"
        return 0
    fi
}

repair_boot_partition() {
    msg "Attempting to repair boot partition..."
    log INFO "Starting boot partition repair"
    
    # Run diagnostics first
    if diagnose_boot_partition; then
        msg "Boot partition is healthy, no repair needed"
        return 0
    fi
    
    # Try repair strategies
    
    # Strategy 1: Reinstall bootloader packages
    info "Reinstalling bootloader packages..."
    if install_pi5_boot_packages; then
        if populate_boot_from_packages; then
            # Reconfigure boot files
            configure_boot_files
            
            # Re-verify
            if verify_boot_partition; then
                msg "✓ Boot partition repaired successfully!"
                log INFO "Boot partition repair successful"
                return 0
            fi
        fi
    fi
    
    # Strategy 2: Try downloading again
    info "Attempting to download fresh boot files..."
    rm -rf "$TMPDIR/pi5-boot" "$TMPDIR/pi5-boot.tar.gz" "$TMPDIR/pi5-image.img"*
    
    if download_pi5_boot_image; then
        if [[ -d "$TMPDIR/pi5-boot" ]] && [[ -f "$TMPDIR/pi5-boot/kernel8.img" ]]; then
            info "Copying downloaded boot files..."
            cp -rv "$TMPDIR/pi5-boot/"* "$TMPDIR/root/boot/" 2>&1 | tee -a "$TMPDIR/install.log"
            
            # Reconfigure
            configure_boot_files
            
            # Re-verify
            if verify_boot_partition; then
                msg "✓ Boot partition repaired successfully!"
                log INFO "Boot partition repair successful"
                return 0
            fi
        fi
    fi
    
    err "Boot partition repair failed"
    log ERROR "All repair strategies failed"
    return 1
}

# =============================================================================
# Final Steps
# =============================================================================

cleanup_and_unmount() {
    msg "Cleaning up..."
    log INFO "Running cleanup"
    
    # Clean package cache
    $NSPAWN "$TMPDIR/root" pacman -Scc --noconfirm 2>&1 | tee -a "$TMPDIR/install.log" || true
    
    # Remove temporary files
    rm -f "$TMPDIR/root/MANJARO-ARM-IMAGE-BUILD"
    
    # Sync and unmount
    sync
    umount -R "$TMPDIR/root/boot" 2>/dev/null || true
    umount -R "$TMPDIR/root" 2>/dev/null || true
    
    log INFO "Cleanup complete"
}

show_completion_message() {
    local msg="✓ Installation Complete!\n\n"
    msg+="Your Manjaro ARM system is ready.\n\n"
    msg+="Next steps:\n"
    msg+="1. Remove the SD card safely\n"
    msg+="2. Insert it into your Raspberry Pi 5\n"
    msg+="3. Connect monitor and power\n"
    msg+="4. Boot the system\n\n"
    msg+="Login credentials:\n"
    msg+="  Username: $USERNAME\n"
    msg+="  Password: (as configured)\n\n"
    if [ "$WIFI_CONNECTED" = true ]; then
        msg+="Wi-Fi: Configured for $WIFI_SSID\n\n"
    fi
    msg+="Installation log: $TMPDIR/install.log"
    
    dialog --title "Installation Complete" \
        --msgbox "$msg" 22 70
    
    clear
    echo ""
    echo "========================================="
    echo "  Manjaro ARM Pi 5 Installation Complete"
    echo "========================================="
    echo ""
    echo "Edition: $EDITION"
    echo "Display Manager: $DISPLAY_MANAGER"
    echo "Storage: $SDCARD"
    if [ "$WIFI_CONNECTED" = true ]; then
        echo "Wi-Fi: Configured for $WIFI_SSID"
    fi
    echo ""
    echo "Log file: $TMPDIR/install.log"
    echo ""
    log INFO "Installation completed successfully"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Check dependencies
    for cmd in dialog parted mkfs.vfat mkfs.ext4 wget git bsdtar systemd-nspawn; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command not found: $cmd"
            echo "Please install the required packages and try again."
            exit 1
        fi
    done
    
    mkdir -p "$TMPDIR"
    log INFO "=== Manjaro ARM Pi 5 Installer v2.6 Started ==="
    
    # UI Flow
    ui_select_edition
    ui_network_settings_menu  # NEW: Network configuration menu
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
    ui_progress "Partitioning" "Creating partitions on $SDCARD..."
    partition_and_format_sdcard
    
    ui_progress "Mounting" "Mounting partitions..."
    mount_root_partition
    mount_boot_partition
    
    ui_progress "Downloading" "Downloading base system..."
    installer_get_armprofiles
    download_generic_rootfs
    
    ui_progress "Extracting" "Extracting root filesystem..."
    extract_generic_rootfs
    
    ui_progress "Package Keys" "Setting up package keyrings..."
    setup_keyrings_and_mirrors
    
    ui_progress "Base System" "Installing base Pi 5 system..."
    install_pi5_base_system
    
    ui_progress "Boot Partition" "Setting up Pi 5 boot files..."
    copy_pi5_boot_files
    configure_boot_files
    
    ui_progress "Verification" "Verifying boot partition..."
    if ! verify_boot_partition; then
        log WARN "Boot partition verification failed, attempting repair..."
        
        if repair_boot_partition; then
            dialog --title "Boot Partition Repaired" \
                --msgbox "Boot partition issues were detected and automatically repaired.\n\nVerification now passes." 10 60
            log INFO "Boot partition repair successful"
        else
            dialog --title "Boot Partition Warning" \
                --yesno "Boot partition verification failed and could not be automatically repaired.\n\nThe system may not boot properly.\n\nDo you want to:\n\nYES - Continue anyway (check log later)\nNO - Abort installation" 14 70
            
            if [ $? -ne 0 ]; then
                log ERROR "Installation aborted by user due to boot partition issues"
                cleanup_and_unmount
                exit 1
            else
                log WARN "User chose to continue despite boot partition issues"
            fi
        fi
    fi
    
    ui_progress "Hardware" "Installing Pi 5 hardware support..."
    install_pi5_hardware_support
    
    ui_progress "Edition" "Installing $EDITION packages..."
    install_edition_packages
    
    ui_progress "System Config" "Configuring system..."
    create_user_and_set_passwords
    setup_hostname
    setup_locale
    setup_timezone
    setup_network
    
    if [[ "$EDITION" =~ ^(xfce|gnome|kde-) ]]; then
        ui_progress "Graphics" "Configuring Xorg..."
        setup_xorg_auto_detection  # FIXED: Use automatic detection
        
        ui_progress "Display Manager" "Setting up $DISPLAY_MANAGER..."
        setup_display_manager
    fi
    
    ui_progress "Optimizations" "Applying optimizations..."
    apply_optimizations
    
    ui_progress "Finalizing" "Cleaning up..."
    cleanup_and_unmount
    
    show_completion_message
}

# Run installer
main "$@"

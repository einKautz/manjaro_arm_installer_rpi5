#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASH_VERSION-}" ]; then
    echo "Please run this installer with bash:"
    echo "  bash $0"
    exit 1
fi

ARCH="aarch64"
BRANCH="unstable"
DEVICE="rpi5"
TMPDIR="/tmp/manjaro-installer"
NSPAWN="systemd-nspawn -D"

msg()  { echo -e "\n==> $*"; }
info() { echo "    $*"; }
err()  { echo "!! $*" >&2; }
log()  {
    local level="$1"; shift
    mkdir -p "$TMPDIR"
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" \
        | tee -a "$TMPDIR/install.log"
}

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

ui_select_edition() {
    while true; do
        EDITION=$(dialog_input "Edition Selection" "Choose your Manjaro ARM edition:" \
            --menu "Choose your Manjaro ARM edition:" 15 60 5 \
            minimal "Minimal CLI" \
            xfce    "XFCE Desktop" \
            gnome   "GNOME Desktop" \
            server  "Server (CLI)")
        [ -n "$EDITION" ] && break
    done
}

ui_select_sdcard() {
    local options=()
    local dev size
    for dev in /dev/sd? /dev/mmcblk? /dev/nvme?n?; do
        [[ -b "$dev" ]] || continue
        size=$(lsblk -dn -o SIZE "$dev")
        options+=("$dev" "$size")
    done
    while true; do
        SDCARD=$(dialog_input "Storage Selection" "Select the SD card to install Manjaro ARM onto:" \
            --menu "Available storage devices:" 20 60 10 \
            "${options[@]}")
        [ -n "$SDCARD" ] && break
    done
}

ui_select_bootmode() {
    while true; do
        BOOTMODE=$(dialog_input "Boot Mode" "Choose boot mode:" \
            --menu "Select boot mode:" 12 60 2 \
            hybrid "Hybrid Boot (Recommended)" \
            full   "Full Bootloader Replacement")
        [ -n "$BOOTMODE" ] && break
    done
}

ui_set_username() {
    while true; do
        USERNAME=$(dialog_input "Create User" "Enter a username:" \
            --inputbox "Username:" 12 60)
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        fi
        dialog --title "Invalid Username" --msgbox "Invalid username." 10 60
    done
}

ui_set_password() {
    while true; do
        local p1 p2
        p1=$(dialog_input "User Password" "Enter password for $USERNAME:" \
            --passwordbox "Password:" 12 60)
        p2=$(dialog_input "Confirm Password" "Re-enter password:" \
            --passwordbox "Confirm:" 12 60)
        if [[ "$p1" == "$p2" ]]; then
            USER_PASSWORD="$p1"
            break
        fi
        dialog --title "Mismatch" --msgbox "Passwords do not match." 10 60
    done
}

ui_set_root_mode() {
    ROOT_MODE=$(dialog_input "Root Account Options" "Choose how to configure the root account:" \
        --menu "Root account mode:" 15 60 4 \
        setpw   "Set a root password" \
        disable "Disable root login (PermitRootLogin no)" \
        lock    "Lock root account (passwd -l)" \
        skip    "Skip root password (sudo-only)")
}

ui_set_root_password() {
    while true; do
        local p1 p2
        p1=$(dialog_input "Root Password" "Enter root password:" \
            --passwordbox "Password:" 12 60)
        p2=$(dialog_input "Confirm Root Password" "Re-enter password:" \
            --passwordbox "Confirm:" 12 60)
        if [[ "$p1" == "$p2" ]]; then
            ROOT_PASSWORD="$p1"
            break
        fi
        dialog --title "Mismatch" --msgbox "Root passwords do not match." 10 60
    done
}

ui_select_optimizations() {
    local raw
    raw=$(dialog_input "Post-Install Optimizations" "Select which optimizations to apply:" \
        --checklist "Choose optimizations (press SPACE to toggle):" 22 80 10 \
        zram     "Enable ZRAM swap (RAM-aware: boosts stability on 4GB, multitasking on 8/16GB)" ON \
        sysctl   "Kernel tuning for lower latency (desktop/cyberdeck)" ON \
        gpu      "Set GPU memory to 256MB (desktop/video)" ON \
        journald "Reduce log size + SD wear" ON \
        fstrim   "Enable weekly TRIM" ON \
        cpupower "Enable ondemand CPU governor" ON)
    if [ -n "$raw" ]; then
        read -ra OPTS <<< "$raw"
    else
        OPTS=()
    fi
}

ui_confirm() {
    if ! dialog --title "Confirm Installation" \
        --yes-label "Install" \
        --no-label "Cancel" \
        --yesno "Install Manjaro ARM ($EDITION) on $SDCARD?\n\nBoot mode: $BOOTMODE" 12 60; then
        exit 1
    fi
}

ui_progress() {
    dialog --title "$1" --infobox "$2" 8 60
    sleep 1
}

auto_unmount_device() {
    local dev="$1"
    local user="${SUDO_USER:-$USER}"
    msg "Checking for active mounts and processes on $dev"
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
        err "Processes are holding $dev open:"
        log ERROR "Holders on $dev: $holders"
        sed 's/^/    /' <<< "$holders"
        local pids
        pids=$(awk '{print $2}' <<< "$holders" | sort -u)
        info "Attempting graceful termination of processes: $pids"
        log INFO "Killing PIDs: $pids"
        for pid in $pids; do kill "$pid" 2>/dev/null || true; done
        sleep 1
        holders=$(lsof 2>/dev/null | grep -- "$dev" || true)
        if [[ -n "$holders" ]]; then
            err "Some processes are still holding $dev. Forcing kill."
            log ERROR "Forcing kill on remaining holders of $dev"
            pids=$(awk '{print $2}' <<< "$holders" | sort -u)
            for pid in $pids; do kill -9 "$pid" 2>/dev/null || true; done
        fi
    fi
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
    parted -s "$SDCARD" mklabel gpt
    parted -s "$SDCARD" mkpart primary fat32 1MiB 301MiB
    parted -s "$SDCARD" set 1 boot on
    parted -s "$SDCARD" mkpart primary ext4 301MiB 100%
    partprobe "$SDCARD"
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
}

mount_root_partition() {
    msg "Mounting root partition $ROOTPART"
    log INFO "Mounting root partition $ROOTPART at $TMPDIR/root"
    mkdir -p "$TMPDIR/root"
    mount "$ROOTPART" "$TMPDIR/root"
}

installer_get_armprofiles() {
    info "Getting package lists ready for $DEVICE $EDITION edition..."
    log INFO "Cloning arm-profiles"
    rm -rf "$TMPDIR/arm-profiles"
    mkdir -p "$TMPDIR"
    chmod 777 "$TMPDIR"
    git clone https://gitlab.manjaro.org/manjaro-arm/applications/arm-profiles.git \
        "$TMPDIR/arm-profiles/" 1>/dev/null 2>&1
}

download_generic_rootfs() {
    msg "Downloading generic $ARCH rootfs..."
    log INFO "Downloading generic rootfs for $ARCH"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR"
    rm -f "Manjaro-ARM-$ARCH-latest.tar.gz"*
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz"
}

extract_generic_rootfs() {
    msg "Extracting generic rootfs..."
    log INFO "Extracting generic rootfs into $TMPDIR/root"
    bsdtar -xpf "$TMPDIR/Manjaro-ARM-$ARCH-latest.tar.gz" -C "$TMPDIR/root"
    touch "$TMPDIR/root/MANJARO-ARM-IMAGE-BUILD"
    mkdir -p "$TMPDIR/root/etc/pacman.d"
    ln -sf ../usr/lib/os-release "$TMPDIR/root/etc/os-release"
    touch "$TMPDIR/root/etc/pacman.d/mirrorlist"
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
}

load_profile_packages() {
    local profiles="$TMPDIR/arm-profiles"
    local edition_profile device_profile
    case "$EDITION" in
        minimal) edition_profile="minimal" ;;
        xfce)    edition_profile="xfce" ;;
        gnome)   edition_profile="gnome" ;;
        server)  edition_profile="server" ;;
        *) err "Unknown edition: $EDITION"; log ERROR "Unknown edition: $EDITION"; exit 1 ;;
    esac
    device_profile="rpi4"
    PKG_SHARED=$(grep -v '^#' "$profiles/shared/Packages-Root" 2>/dev/null || true)
    PKG_EDITION=$(grep -v '^#' "$profiles/editions/$edition_profile/Packages-Root" 2>/dev/null || true)
    PKG_DEVICE=$(grep -v '^#' "$profiles/devices/$device_profile/Packages-Root" 2>/dev/null || true)
    srv_list="$profiles/editions/$edition_profile/services"
    log INFO "Loaded package lists for edition=$edition_profile device=$device_profile"
}

install_profile_packages() {
    msg "Installing packages for $EDITION on $DEVICE..."
    log INFO "Installing profile packages into rootfs"
    mkdir -p "$TMPDIR/pkg-cache"
    mkdir -p "$TMPDIR/root/var/cache/pacman/pkg"
    mount -o bind "$TMPDIR/pkg-cache" "$TMPDIR/root/var/cache/pacman/pkg"
    set -- base manjaro-system manjaro-release systemd systemd-libs \
        $PKG_SHARED $PKG_EDITION $PKG_DEVICE
    $NSPAWN "$TMPDIR/root" pacman -Syu "$@" --noconfirm
    msg "Enabling services..."
    $NSPAWN "$TMPDIR/root" systemctl enable getty.target haveged.service 1>/dev/null || true
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
    if [[ -f "$TMPDIR/root/usr/bin/xdg-user-dirs-update" ]]; then
        $NSPAWN "$TMPDIR/root" systemctl --global enable xdg-user-dirs-update.service 1>/dev/null 2>&1 || true
    fi
    umount "$TMPDIR/root/var/cache/pacman/pkg" 2>/dev/null || true
}

prepare_chroot() {
    msg "Preparing chroot environment"
    log INFO "Binding /proc, /sys, /dev, /run into chroot"
    mount -t proc /proc "$TMPDIR/root/proc"
    mount --rbind /sys "$TMPDIR/root/sys"
    mount --rbind /dev "$TMPDIR/root/dev"
    mount --rbind /run "$TMPDIR/root/run"
}

install_pi5_firmware() {
    msg "Installing Raspberry Pi 5 firmware"
    log INFO "Installing raspberrypi-bootloader packages"
    arch-chroot "$TMPDIR/root" bash -c "
        pacman -Sy --noconfirm raspberrypi-bootloader raspberrypi-bootloader-x
    "
}

install_pi5_kernel() {
    msg "Installing Raspberry Pi 5 kernel"
    log INFO "Installing linux-rpi5 kernel"
    arch-chroot "$TMPDIR/root" bash -c "
        pacman -Rdd --noconfirm linux-rpi4 || true
        pacman -Sy --noconfirm linux-rpi5 linux-rpi5-headers
    "
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
    if [[ -f "$TMPDIR/root/boot/kernel8.img" ]]; then
        mv "$TMPDIR/root/boot/"* "$TMPDIR/root/boot/firmware/" 2>/dev/null || true
    fi
    touch "$TMPDIR/root/boot/firmware/config.txt"
    touch "$TMPDIR/root/boot/firmware/cmdline.txt"
}

patch_config_txt() {
    msg "Patching config.txt"
    log INFO "Writing config.txt for Pi 5"
    cat <<EOF > "$TMPDIR/root/boot/firmware/config.txt"
arm_64bit=1
kernel=kernel8.img
enable_uart=1
dtparam=pciex1_gen=3
dtoverlay=vc4-kms-v3d
gpu_mem=256
EOF
}

patch_cmdline_txt() {
    msg "Patching cmdline.txt"
    log INFO "Writing cmdline.txt with root UUID"
    local uuid
    uuid=$(blkid -s UUID -o value "$ROOTPART")
    echo "root=UUID=$uuid rw rootwait console=ttyAMA0,115200 console=tty1" \
        > "$TMPDIR/root/boot/firmware/cmdline.txt"
}

generate_fstab() {
    msg "Generating fstab"
    log INFO "Generating fstab with UUIDs"
    local uuid_root uuid_boot
    uuid_root=$(blkid -s UUID -o value "$ROOTPART")
    uuid_boot=$(blkid -s UUID -o value "$BOOTPART")
    cat <<EOF > "$TMPDIR/root/etc/fstab"
UUID=$uuid_root   /               ext4    defaults,noatime  0 1
UUID=$uuid_boot   /boot/firmware  vfat    defaults,noatime  0 2
EOF
}

finalize_system() {
    msg "Finalizing system"
    log INFO "Enabling NetworkManager and sshd"
    arch-chroot "$TMPDIR/root" bash -c "
        systemctl enable NetworkManager || true
        systemctl enable sshd || true
    "
}

create_user_account() {
    msg "Creating user account '$USERNAME'"
    log INFO "Creating user $USERNAME and enabling sudo"
    arch-chroot "$TMPDIR/root" bash -c "
        useradd -m -G wheel,video,audio,storage,input,lp,network,render,uucp,plugdev,adm -s /bin/bash \"$USERNAME\"
        echo \"$USERNAME:$USER_PASSWORD\" | chpasswd
        sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    "
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
                if grep -q '^PermitRootLogin' /etc/ssh/sshd_config; then
                    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                else
                    printf '\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
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
            cat <<ZEOF >/etc/systemd/zram-generator.conf.d/override.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZEOF
            systemctl enable systemd-zram-setup@zram0.service || true
            ;;
        sysctl)
            echo ">>> Applying sysctl performance tuning"
            cat <<SEOEF >/etc/sysctl.d/99-pi5-performance.conf
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
SEOEF
            ;;
        gpu)
            echo ">>> Setting GPU memory split"
            sed -i '/^gpu_mem=/d' /boot/firmware/config.txt
            echo 'gpu_mem=256' >> /boot/firmware/config.txt
            ;;
        journald)
            echo ">>> Optimizing journald"
            mkdir -p /etc/systemd/journald.conf.d
            cat <<JEOF >/etc/systemd/journald.conf.d/99-optimized.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
Storage=auto
Compress=yes
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
}

finalize_install() {
    msg "Finalizing installation"
    log INFO "Unmounting chroot and partitions"
    umount -R "$TMPDIR/root/run" 2>/dev/null || true
    umount -R "$TMPDIR/root/dev" 2>/dev/null || true
    umount -R "$TMPDIR/root/sys" 2>/dev/null || true
    umount "$TMPDIR/root/proc" 2>/dev/null || true
    umount "$TMPDIR/root/boot/firmware" 2>/dev/null || true
    umount "$TMPDIR/root/boot" 2>/dev/null || true
    umount "$TMPDIR/root" 2>/dev/null || true
}

main() {
    mkdir -p "$TMPDIR" "$TMPDIR/tmp"
    log INFO "Starting Manjaro ARM Pi 5 installer"
    ui_select_edition
    ui_select_sdcard
    ui_select_bootmode
    ui_set_username
    ui_set_password
    ui_set_root_mode
    if [[ "$ROOT_MODE" == "setpw" ]]; then
        ui_set_root_password
    fi
    ui_confirm
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
    ui_progress "System" "Enabling services..."
    finalize_system
    ui_progress "Users" "Creating user account..."
    create_user_account
    ui_progress "Root" "Configuring root account..."
    apply_root_mode
    ui_select_optimizations
    ui_progress "Optimizing" "Applying selected optimizations..."
    if ((${#OPTS[@]} > 0)); then
        post_install_optimizations "${OPTS[@]}"
    fi
    ui_progress "Cleanup" "Unmounting and finalizing..."
    finalize_install
    log INFO "Installation complete"
    dialog --title "Done" --msgbox "Installation complete!\nYour SD card is ready for Raspberry Pi 5." 10 60
}

main "$@"
clear

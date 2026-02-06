#!/usr/bin/env bash
#
# Pi 5 Boot Partition Plugin
# Handles boot file population using multiple strategies
#

PLUGIN_NAME="pi5-boot"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("boot")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Multi-strategy boot file setup
plugin_run_boot() {
    log_info "Pi 5 Boot Plugin: Setting up boot partition"
    log_set_phase "boot-pi5"
    
    # Import required variables from parent script
    : "${TMPDIR:=/tmp/manjaro-installer}"
    
    # Strategy 1: Try to download and use pre-built boot files
    if _download_pi5_boot_image; then
        if [[ -d "${TMPDIR}/pi5-boot" ]] && [[ -f "${TMPDIR}/pi5-boot/kernel8.img" ]]; then
            log_info "Using downloaded Pi 5 boot files"
            
            # Copy everything
            if cp -rv "${TMPDIR}/pi5-boot/"* "${TMPDIR}/root/boot/" 2>&1 | tee -a "${TMPDIR}/install.log"; then
                # Verify it worked
                if [[ -f "${TMPDIR}/root/boot/kernel8.img" ]] && [[ -f "${TMPDIR}/root/boot/bcm2712-rpi-5-b.dtb" ]]; then
                    log_info "Boot files copied successfully from download"
                    return 0
                else
                    log_warn "Downloaded files incomplete, falling back to packages"
                fi
            else
                log_error "Failed to copy downloaded boot files"
            fi
        fi
    fi
    
    # Strategy 2: Use package-provided files
    log_info "Falling back to package-provided boot files"
    
    if _populate_boot_from_packages; then
        log_info "Boot files populated from packages"
        return 0
    else
        log_error "Failed to populate boot partition from packages"
        return 1
    fi
}

# Download Pi 5 boot image (internal function)
_download_pi5_boot_image() {
    local pi5_image_url="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/Manjaro-ARM-minimal-rpi5-latest.img.xz"
    local pi5_boot_tarball="https://github.com/manjaro-arm/rpi5-images/releases/latest/download/boot-rpi5.tar.gz"
    
    log_info "Attempting to download Pi 5 boot files"
    
    # Try tarball first (smaller)
    if wget -q --show-progress "${pi5_boot_tarball}" -O "${TMPDIR}/pi5-boot.tar.gz" 2>&1 | tee -a "${TMPDIR}/install.log"; then
        log_info "Downloaded boot tarball"
        mkdir -p "${TMPDIR}/pi5-boot"
        
        if tar -xzf "${TMPDIR}/pi5-boot.tar.gz" -C "${TMPDIR}/pi5-boot" 2>&1 | tee -a "${TMPDIR}/install.log"; then
            log_info "Extracted boot files from tarball"
            return 0
        else
            log_warn "Failed to extract boot tarball"
        fi
    else
        log_warn "Failed to download boot tarball, will try full image"
    fi
    
    # Try full image as fallback
    if wget -q --show-progress "${pi5_image_url}" -O "${TMPDIR}/pi5-image.img.xz" 2>&1 | tee -a "${TMPDIR}/install.log"; then
        log_info "Downloaded full Pi 5 image"
        
        if xz -d "${TMPDIR}/pi5-image.img.xz" 2>&1 | tee -a "${TMPDIR}/install.log"; then
            log_info "Decompressed image"
            
            if _extract_boot_from_image "${TMPDIR}/pi5-image.img"; then
                return 0
            fi
        fi
    fi
    
    log_error "Failed to download Pi 5 boot files"
    return 1
}

# Extract boot partition from image (internal function)
_extract_boot_from_image() {
    local image_file="$1"
    
    log_info "Extracting boot partition from image"
    
    # Get boot partition offset and size
    local boot_info
    boot_info=$(fdisk -l "${image_file}" | grep "^${image_file}1" | awk '{print $2, $3}')
    
    if [[ -z "${boot_info}" ]]; then
        log_error "Could not find boot partition in image"
        return 1
    fi
    
    local offset size
    read -r offset size <<< "${boot_info}"
    offset=$((offset * 512))
    size=$((size * 512))
    
    log_debug "Boot partition: offset=${offset}, size=${size}"
    
    mkdir -p "${TMPDIR}/pi5-boot-mount"
    
    if mount -o loop,offset="${offset}",sizelimit="${size}" "${image_file}" "${TMPDIR}/pi5-boot-mount" 2>&1 | tee -a "${TMPDIR}/install.log"; then
        mkdir -p "${TMPDIR}/pi5-boot"
        
        if cp -r "${TMPDIR}/pi5-boot-mount/"* "${TMPDIR}/pi5-boot/" 2>&1 | tee -a "${TMPDIR}/install.log"; then
            log_info "Boot files extracted from image"
            umount "${TMPDIR}/pi5-boot-mount" 2>/dev/null || true
            return 0
        fi
        
        umount "${TMPDIR}/pi5-boot-mount" 2>/dev/null || true
    fi
    
    log_error "Failed to extract boot partition from image"
    return 1
}

# Populate boot from packages (internal function)
_populate_boot_from_packages() {
    log_info "Installing Pi 5 bootloader packages"
    
    # Install bootloader packages if not already present
    if ! _install_pi5_boot_packages; then
        log_error "Failed to install boot packages"
        return 1
    fi
    
    log_info "Copying boot files from installed packages"
    
    # Copy firmware files
    local boot_files=(
        "/usr/lib/firmware/raspberrypi/bootloader-2712/latest/*.bin"
        "/usr/lib/firmware/raspberrypi/bootloader-2712/latest/*.dat"
        "/usr/lib/firmware/raspberrypi/bootloader-2712/latest/*.elf"
    )
    
    for pattern in "${boot_files[@]}"; do
        # shellcheck disable=SC2086
        cp -v ${pattern} "${TMPDIR}/root/boot/" 2>&1 | tee -a "${TMPDIR}/install.log" || true
    done
    
    # Copy kernel and initramfs
    cp -v /boot/Image* "${TMPDIR}/root/boot/kernel8.img" 2>&1 | tee -a "${TMPDIR}/install.log" || true
    cp -v /boot/initramfs* "${TMPDIR}/root/boot/" 2>&1 | tee -a "${TMPDIR}/install.log" || true
    
    # Copy DTBs
    mkdir -p "${TMPDIR}/root/boot/overlays"
    cp -rv /boot/dtbs/broadcom/*.dtb "${TMPDIR}/root/boot/" 2>&1 | tee -a "${TMPDIR}/install.log" || true
    cp -rv /boot/dtbs/overlays/*.dtbo "${TMPDIR}/root/boot/overlays/" 2>&1 | tee -a "${TMPDIR}/install.log" || true
    
    log_info "Boot files copied from packages"
    return 0
}

# Install Pi 5 boot packages (internal function)
_install_pi5_boot_packages() {
    # Use systemd-nspawn if available, otherwise direct pacman
    local nspawn="${NSPAWN:-systemd-nspawn -D}"
    
    ${nspawn} "${TMPDIR}/root" pacman -Sy --noconfirm \
        raspberrypi-bootloader \
        raspberrypi-firmware \
        linux-rpi5 \
        2>&1 | tee -a "${TMPDIR}/install.log"
    
    return "${PIPESTATUS[0]}"
}

#!/usr/bin/env bash
#
# HAL: Storage Management
# Handles SD/NVMe/USB storage detection and configuration
#

# Source logging if not already loaded
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Detect storage type
hal_storage_detect_type() {
    local device="${1:-$SDCARD}"
    
    if [[ -z "$device" ]]; then
        log_error "HAL Storage: No device specified"
        return 1
    fi
    
    log_info "HAL Storage: Detecting storage type for $device"
    
    local storage_type="unknown"
    
    # Check device type
    if [[ "$device" =~ mmcblk ]]; then
        # SD/eMMC device
        if [[ -f "/sys/block/$(basename "$device")/device/type" ]]; then
            local mmc_type
            mmc_type=$(cat "/sys/block/$(basename "$device")/device/type")
            case "$mmc_type" in
                SD)
                    storage_type="sdcard"
                    ;;
                MMC)
                    storage_type="emmc"
                    ;;
                *)
                    storage_type="mmc"
                    ;;
            esac
        else
            storage_type="sdcard"
        fi
    elif [[ "$device" =~ nvme ]]; then
        storage_type="nvme"
    elif [[ "$device" =~ sd[a-z] ]]; then
        # Could be USB or SATA
        if [[ -L "/sys/block/$(basename "$device")" ]]; then
            local device_path
            device_path=$(readlink -f "/sys/block/$(basename "$device")")
            if [[ "$device_path" =~ usb ]]; then
                storage_type="usb"
            else
                storage_type="sata"
            fi
        else
            storage_type="disk"
        fi
    fi
    
    export HAL_STORAGE_TYPE="$storage_type"
    log_info "HAL Storage: Type detected: $storage_type"
    echo "$storage_type"
    return 0
}

# Get storage capacity
hal_storage_get_capacity() {
    local device="${1:-$SDCARD}"
    
    if [[ -z "$device" ]]; then
        log_error "HAL Storage: No device specified"
        return 1
    fi
    
    log_info "HAL Storage: Getting capacity for $device"
    
    local block_device
    block_device=$(basename "$device")
    
    if [[ -f "/sys/block/${block_device}/size" ]]; then
        local blocks
        blocks=$(cat "/sys/block/${block_device}/size")
        local bytes=$((blocks * 512))
        local gb=$((bytes / 1024 / 1024 / 1024))
        
        export HAL_STORAGE_CAPACITY_GB="$gb"
        log_info "HAL Storage: Capacity: ${gb}GB"
        echo "${gb}GB"
        return 0
    fi
    
    log_warn "HAL Storage: Could not determine capacity"
    return 1
}

# Check if storage supports TRIM
hal_storage_supports_trim() {
    local device="${1:-$SDCARD}"
    
    if [[ -z "$device" ]]; then
        log_error "HAL Storage: No device specified"
        return 1
    fi
    
    local block_device
    block_device=$(basename "$device")
    
    log_info "HAL Storage: Checking TRIM support for $device"
    
    # NVMe and SSDs typically support TRIM
    if [[ "$device" =~ nvme ]]; then
        log_info "HAL Storage: NVMe device - TRIM supported"
        export HAL_STORAGE_TRIM_SUPPORTED=1
        return 0
    fi
    
    # Check discard_granularity
    if [[ -f "/sys/block/${block_device}/queue/discard_granularity" ]]; then
        local granularity
        granularity=$(cat "/sys/block/${block_device}/queue/discard_granularity")
        if [[ $granularity -gt 0 ]]; then
            log_info "HAL Storage: TRIM supported (discard_granularity=$granularity)"
            export HAL_STORAGE_TRIM_SUPPORTED=1
            return 0
        fi
    fi
    
    log_info "HAL Storage: TRIM not supported"
    export HAL_STORAGE_TRIM_SUPPORTED=0
    return 1
}

# Get optimal I/O scheduler
hal_storage_get_scheduler() {
    local storage_type="${1:-$HAL_STORAGE_TYPE}"
    
    log_info "HAL Storage: Determining optimal I/O scheduler for $storage_type"
    
    local scheduler="mq-deadline"  # Default
    
    case "$storage_type" in
        nvme)
            scheduler="none"  # NVMe performs best with no scheduler
            ;;
        sdcard|emmc|mmc)
            scheduler="mq-deadline"  # Good for flash storage
            ;;
        ssd|usb)
            scheduler="bfq"  # Better for SSDs and USB
            ;;
        *)
            scheduler="mq-deadline"  # Safe default
            ;;
    esac
    
    log_info "HAL Storage: Recommended scheduler: $scheduler"
    echo "$scheduler"
    return 0
}

# Configure storage optimizations in target system
hal_storage_configure_optimizations() {
    local mount_point="${MOUNT_POINT:-/mnt}"
    local storage_type="${1:-$HAL_STORAGE_TYPE}"
    
    log_info "HAL Storage: Configuring optimizations for $storage_type"
    
    # Create udev rules for storage optimization
    local udev_rules="${mount_point}/etc/udev/rules.d/60-storage-optimizations.rules"
    
    mkdir -p "$(dirname "$udev_rules")"
    
    cat > "$udev_rules" << EOF
# Storage optimizations (configured by HAL)
# Generated for storage type: ${storage_type}

# Set I/O scheduler based on device type
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="mmcblk[0-9]", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"

# Optimize read-ahead for flash storage
ACTION=="add|change", KERNEL=="mmcblk[0-9]", ATTR{bdi/read_ahead_kb}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="256"

# Reduce nr_requests for SD cards to prevent stalls
ACTION=="add|change", KERNEL=="mmcblk[0-9]", ATTR{queue/nr_requests}="128"
EOF
    
    log_info "HAL Storage: Created udev optimization rules"
    
    # Configure fstab options based on storage type
    local fstab="${mount_point}/etc/fstab"
    
    if [[ -f "$fstab" ]]; then
        log_info "HAL Storage: Optimizing fstab mount options"
        
        case "$storage_type" in
            nvme|ssd)
                # Add noatime,discard for SSDs
                sed -i 's/relatime/noatime,discard/' "$fstab" 2>/dev/null || true
                ;;
            sdcard|emmc)
                # Add noatime for SD cards (avoid discard due to performance)
                sed -i 's/relatime/noatime/' "$fstab" 2>/dev/null || true
                ;;
        esac
        
        log_info "HAL Storage: fstab optimizations applied"
    fi
    
    return 0
}

# List available storage devices
hal_storage_list_devices() {
    log_info "HAL Storage: Listing available storage devices"
    
    local devices=()
    
    # List block devices
    for device in /sys/block/*; do
        local dev_name
        dev_name=$(basename "$device")
        
        # Skip loop, ram, and other virtual devices
        if [[ "$dev_name" =~ ^(loop|ram|dm-) ]]; then
            continue
        fi
        
        local dev_path="/dev/${dev_name}"
        if [[ -b "$dev_path" ]]; then
            devices+=("$dev_path")
        fi
    done
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        log_warn "HAL Storage: No storage devices found"
        return 1
    fi
    
    log_info "HAL Storage: Found ${#devices[@]} device(s): ${devices[*]}"
    printf '%s\n' "${devices[@]}"
    return 0
}

# Export functions
export -f hal_storage_detect_type
export -f hal_storage_get_capacity
export -f hal_storage_supports_trim
export -f hal_storage_get_scheduler
export -f hal_storage_configure_optimizations
export -f hal_storage_list_devices

#!/usr/bin/env bash
#
# Raspberry Pi 5 Hardware Detection Plugin
# Detects and validates Pi 5 hardware components
#

PLUGIN_NAME="pi5-hw"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()
PLUGIN_PHASES=("detect")

# Source logging if not available
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Hardware detection results
declare -g HW_MODEL=""
declare -g HW_CPU=""
declare -g HW_MEMORY=""
declare -g HW_STORAGE=""

# Detection phase
plugin_run_detect() {
    log_info "Pi 5 Hardware Detection: Starting detection"
    log_set_phase "detect-hw"
    
    _detect_model
    _detect_cpu
    _detect_memory
    _detect_storage
    
    log_info "Hardware detection complete"
    return 0
}

# Detect Pi model
_detect_model() {
    log_info "Detecting Raspberry Pi model"
    
    # Check /proc/device-tree/model if available
    if [[ -f /proc/device-tree/model ]]; then
        HW_MODEL=$(tr -d '\0' < /proc/device-tree/model)
        log_info "Detected model: ${HW_MODEL}"
        
        if [[ "${HW_MODEL}" == *"Raspberry Pi 5"* ]]; then
            log_info "Confirmed: Raspberry Pi 5"
            return 0
        else
            log_warn "Not a Raspberry Pi 5: ${HW_MODEL}"
            return 1
        fi
    fi
    
    # Fallback to /proc/cpuinfo
    if grep -q "Raspberry Pi 5" /proc/cpuinfo 2>/dev/null; then
        HW_MODEL="Raspberry Pi 5"
        log_info "Detected via cpuinfo: ${HW_MODEL}"
        return 0
    fi
    
    log_warn "Could not determine Pi model"
    HW_MODEL="Unknown"
    return 1
}

# Detect CPU information
_detect_cpu() {
    log_info "Detecting CPU information"
    
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_count
        cpu_count=$(grep -c "^processor" /proc/cpuinfo)
        local cpu_model
        cpu_model=$(grep "^Model" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        
        HW_CPU="${cpu_count}x ${cpu_model:-ARM Cortex}"
        log_info "CPU: ${HW_CPU}"
        return 0
    fi
    
    HW_CPU="Unknown"
    return 1
}

# Detect memory
_detect_memory() {
    log_info "Detecting system memory"
    
    if [[ -f /proc/meminfo ]]; then
        local mem_kb
        mem_kb=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
        local mem_gb
        mem_gb=$((mem_kb / 1024 / 1024))
        
        HW_MEMORY="${mem_gb}GB"
        log_info "Memory: ${HW_MEMORY}"
        return 0
    fi
    
    HW_MEMORY="Unknown"
    return 1
}

# Detect storage devices
_detect_storage() {
    log_info "Detecting storage devices"
    
    local storage_list=()
    
    # Detect SD card
    if [[ -b /dev/mmcblk0 ]]; then
        local size
        size=$(lsblk -b -d -n -o SIZE /dev/mmcblk0 2>/dev/null)
        if [[ -n "${size}" ]]; then
            size=$((size / 1024 / 1024 / 1024))
            storage_list+=("SD:${size}GB")
        fi
    fi
    
    # Detect NVMe (via HAT)
    if [[ -b /dev/nvme0n1 ]]; then
        local size
        size=$(lsblk -b -d -n -o SIZE /dev/nvme0n1 2>/dev/null)
        if [[ -n "${size}" ]]; then
            size=$((size / 1024 / 1024 / 1024))
            storage_list+=("NVMe:${size}GB")
        fi
    fi
    
    # Detect USB storage
    for dev in /dev/sd[a-z]; do
        if [[ -b "${dev}" ]]; then
            local size
            size=$(lsblk -b -d -n -o SIZE "${dev}" 2>/dev/null)
            if [[ -n "${size}" ]]; then
                size=$((size / 1024 / 1024 / 1024))
                storage_list+=("USB:${size}GB")
            fi
        fi
    done
    
    if [[ ${#storage_list[@]} -gt 0 ]]; then
        HW_STORAGE="${storage_list[*]}"
        log_info "Storage: ${HW_STORAGE}"
        return 0
    fi
    
    HW_STORAGE="None detected"
    log_warn "No storage devices detected"
    return 1
}

# Get hardware summary
hw_summary() {
    cat <<EOF
Hardware Detection Summary:
===========================
Model:   ${HW_MODEL}
CPU:     ${HW_CPU}
Memory:  ${HW_MEMORY}
Storage: ${HW_STORAGE}
EOF
}

# Check if running on Pi 5
hw_is_pi5() {
    [[ "${HW_MODEL}" == *"Raspberry Pi 5"* ]]
}

# Export functions
export -f hw_summary
export -f hw_is_pi5

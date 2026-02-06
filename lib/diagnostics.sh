#!/bin/bash
# Diagnostics Library for manjaro-pi5-installer
# Provides hardware validation and system readiness checks

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh" 2>/dev/null || true

DIAGNOSTICS_OUTPUT_FORMAT="${DIAGNOSTICS_OUTPUT_FORMAT:-text}"  # text or json

# Check if running on Raspberry Pi 5
diagnostics_check_hardware() {
    local result='{
        "platform": "unknown",
        "model": "unknown",
        "compatible": false,
        "issues": []
    }'
    
    if [[ ! -f /proc/device-tree/model ]]; then
        result=$(echo "$result" | jq '.issues += ["Cannot read /proc/device-tree/model"]')
        echo "$result"
        return 1
    fi
    
    local model
    model=$(tr -d '\0' < /proc/device-tree/model)
    
    result=$(echo "$result" | jq --arg model "$model" '.model = $model')
    
    if [[ "$model" =~ Raspberry\ Pi\ 5 ]]; then
        result=$(echo "$result" | jq '.platform = "raspberry-pi-5" | .compatible = true')
        echo "$result"
        return 0
    else
        result=$(echo "$result" | jq '.issues += ["Not a Raspberry Pi 5 - detected: \($model)"]')
        echo "$result"
        return 1
    fi
}

# Check boot partition and firmware
diagnostics_check_boot() {
    local result='{
        "partition": "unknown",
        "mounted": false,
        "filesystem": "unknown",
        "firmware_files": [],
        "missing_files": [],
        "issues": []
    }'
    
    # Find boot partition
    local boot_partition boot_mount
    if [[ -d /boot/firmware ]]; then
        boot_mount="/boot/firmware"
    elif [[ -d /boot ]]; then
        boot_mount="/boot"
    else
        result=$(echo "$result" | jq '.issues += ["Cannot find boot partition mount"]')
        echo "$result"
        return 1
    fi
    
    boot_partition=$(findmnt -n -o SOURCE "$boot_mount" 2>/dev/null || echo "unknown")
    local fs_type
    fs_type=$(findmnt -n -o FSTYPE "$boot_mount" 2>/dev/null || echo "unknown")
    
    result=$(echo "$result" | jq \
        --arg part "$boot_partition" \
        --arg mount "$boot_mount" \
        --arg fs "$fs_type" \
        '.partition = $part | .mounted = true | .filesystem = $fs | .mount_point = $mount')
    
    # Check for required firmware files
    local required_files=("start4.elf" "fixup4.dat" "config.txt" "cmdline.txt")
    local firmware_files=()
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ -f "$boot_mount/$file" ]]; then
            firmware_files+=("$file")
        else
            missing_files+=("$file")
        fi
    done
    
    # Convert arrays to JSON
    local firmware_json missing_json
    firmware_json=$(printf '%s\n' "${firmware_files[@]}" | jq -R . | jq -s .)
    missing_json=$(printf '%s\n' "${missing_files[@]}" | jq -R . | jq -s .)
    
    result=$(echo "$result" | jq \
        --argjson firmware "$firmware_json" \
        --argjson missing "$missing_json" \
        '.firmware_files = $firmware | .missing_files = $missing')
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        result=$(echo "$result" | jq '.issues += ["Missing firmware files: \(.missing_files | join(", "))"]')
    fi
    
    echo "$result"
    [[ ${#missing_files[@]} -eq 0 ]]
}

# Check filesystem and storage
diagnostics_check_filesystem() {
    local result='{
        "root_device": "unknown",
        "root_filesystem": "unknown",
        "total_space": "unknown",
        "available_space": "unknown",
        "usage_percent": 0,
        "issues": []
    }'
    
    # Get root filesystem info
    local root_device root_fs total_space avail_space used_percent
    root_device=$(findmnt -n -o SOURCE / 2>/dev/null || echo "unknown")
    root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
    
    # Get space information
    if command -v df &>/dev/null; then
        local df_output
        df_output=$(df -h / | tail -1)
        total_space=$(echo "$df_output" | awk '{print $2}')
        avail_space=$(echo "$df_output" | awk '{print $4}')
        used_percent=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
    fi
    
    result=$(echo "$result" | jq \
        --arg device "$root_device" \
        --arg fs "$root_fs" \
        --arg total "$total_space" \
        --arg avail "$avail_space" \
        --arg percent "$used_percent" \
        '.root_device = $device | .root_filesystem = $fs | .total_space = $total | .available_space = $avail | .usage_percent = ($percent | tonumber)')
    
    # Check if space is sufficient (need at least 4GB available)
    if [[ -n "$avail_space" ]] && [[ "$avail_space" != "unknown" ]]; then
        local avail_gb
        avail_gb=$(echo "$avail_space" | sed 's/G.*//' | sed 's/M.*/0.1/')
        if (( $(echo "$avail_gb < 4" | bc -l 2>/dev/null || echo "0") )); then
            result=$(echo "$result" | jq '.issues += ["Insufficient disk space - need at least 4GB available"]')
        fi
    fi
    
    echo "$result"
}

# Check network connectivity
diagnostics_check_network() {
    local result='{
        "interfaces": [],
        "connectivity": false,
        "dns_resolution": false,
        "issues": []
    }'
    
    # Get network interfaces
    local interfaces=()
    while IFS= read -r iface; do
        if [[ -n "$iface" ]] && [[ "$iface" != "lo" ]]; then
            interfaces+=("$iface")
        fi
    done < <(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
    
    local interfaces_json
    interfaces_json=$(printf '%s\n' "${interfaces[@]}" | jq -R . | jq -s .)
    result=$(echo "$result" | jq --argjson ifaces "$interfaces_json" '.interfaces = $ifaces')
    
    # Test connectivity
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        result=$(echo "$result" | jq '.connectivity = true')
    else
        result=$(echo "$result" | jq '.issues += ["No internet connectivity"]')
    fi
    
    # Test DNS resolution
    if host github.com &>/dev/null 2>&1; then
        result=$(echo "$result" | jq '.dns_resolution = true')
    else
        result=$(echo "$result" | jq '.issues += ["DNS resolution failed"]')
    fi
    
    echo "$result"
}

# Check required commands
diagnostics_check_commands() {
    local result='{
        "required": [],
        "optional": [],
        "missing_required": [],
        "missing_optional": [],
        "issues": []
    }'
    
    local required_commands=("systemd-nspawn" "fdisk" "mkfs.ext4" "mkfs.vfat" "mount" "umount" "curl" "wget" "tar" "gzip")
    local optional_commands=("jq" "btrfs" "f2fs" "lsblk" "parted" "rsync")
    
    local missing_required=()
    local missing_optional=()
    local found_required=()
    local found_optional=()
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            found_required+=("$cmd")
        else
            missing_required+=("$cmd")
        fi
    done
    
    for cmd in "${optional_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            found_optional+=("$cmd")
        else
            missing_optional+=("$cmd")
        fi
    done
    
    # Convert to JSON
    local req_json opt_json miss_req_json miss_opt_json
    req_json=$(printf '%s\n' "${found_required[@]}" | jq -R . | jq -s .)
    opt_json=$(printf '%s\n' "${found_optional[@]}" | jq -R . | jq -s .)
    miss_req_json=$(printf '%s\n' "${missing_required[@]}" | jq -R . | jq -s .)
    miss_opt_json=$(printf '%s\n' "${missing_optional[@]}" | jq -R . | jq -s .)
    
    result=$(echo "$result" | jq \
        --argjson req "$req_json" \
        --argjson opt "$opt_json" \
        --argjson miss_req "$miss_req_json" \
        --argjson miss_opt "$miss_opt_json" \
        '.required = $req | .optional = $opt | .missing_required = $miss_req | .missing_optional = $miss_opt')
    
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        result=$(echo "$result" | jq '.issues += ["Missing required commands: \(.missing_required | join(", "))"]')
    fi
    
    echo "$result"
    [[ ${#missing_required[@]} -eq 0 ]]
}

# Validate profile compatibility
diagnostics_check_profile() {
    local profile="$1"
    local result='{
        "profile": null,
        "valid": false,
        "packages": [],
        "hardware_requirements": {},
        "missing_hardware": [],
        "issues": []
    }'
    
    if [[ ! -f "$profile" ]]; then
        result=$(echo "$result" | jq --arg p "$profile" '.issues += ["Profile file not found: \($p)"]')
        echo "$result"
        return 1
    fi
    
    # Parse profile JSON
    if ! jq empty "$profile" 2>/dev/null; then
        result=$(echo "$result" | jq '.issues += ["Invalid JSON in profile file"]')
        echo "$result"
        return 1
    fi
    
    local profile_name
    profile_name=$(jq -r '.name // "unknown"' "$profile")
    result=$(echo "$result" | jq --arg name "$profile_name" '.profile = $name | .valid = true')
    
    # Check hardware requirements (cyberpentester specific)
    if [[ "$profile_name" == "cyberpentester" ]] || [[ "$profile_name" == "cyberdeck" ]]; then
        # Check for WiFi adapter
        local wifi_count
        wifi_count=$(hal_usb_detect_wifi 2>/dev/null | jq 'length' || echo "0")
        
        if [[ "$wifi_count" -eq 0 ]]; then
            result=$(echo "$result" | jq '.missing_hardware += ["WiFi adapter (Alfa AWUS036ACH recommended)"]')
        fi
        
        # Add hardware requirements
        result=$(echo "$result" | jq '.hardware_requirements = {
            "wifi_adapter": "Required for wireless pentesting",
            "sdr_device": "Recommended for RF analysis",
            "ble_sniffer": "Recommended for Bluetooth analysis",
            "power_monitor": "Optional INA3221 for power monitoring"
        }')
    fi
    
    echo "$result"
}

# Run all diagnostics
diagnostics_run_all() {
    local hardware boot filesystem network commands
    
    hardware=$(diagnostics_check_hardware)
    boot=$(diagnostics_check_boot)
    filesystem=$(diagnostics_check_filesystem)
    network=$(diagnostics_check_network)
    commands=$(diagnostics_check_commands)
    
    # Combine all results
    local result
    result=$(jq -n \
        --argjson hw "$hardware" \
        --argjson boot "$boot" \
        --argjson fs "$filesystem" \
        --argjson net "$network" \
        --argjson cmds "$commands" \
        '{
            hardware: $hw,
            boot: $boot,
            filesystem: $fs,
            network: $net,
            commands: $cmds,
            timestamp: (now | strftime("%Y-%m-%d %H:%M:%S"))
        }')
    
    # Calculate overall status
    local all_compatible
    all_compatible=$(echo "$result" | jq '
        (.hardware.compatible and 
         (.boot.issues | length == 0) and 
         (.filesystem.issues | length == 0) and 
         (.commands.missing_required | length == 0))
    ')
    
    result=$(echo "$result" | jq --argjson status "$all_compatible" '.overall_status = (if $status then "ready" else "issues_found" end)')
    
    echo "$result"
}

# Format diagnostics output
diagnostics_format_output() {
    local json_data="$1"
    local format="${2:-$DIAGNOSTICS_OUTPUT_FORMAT}"
    
    if [[ "$format" == "json" ]]; then
        echo "$json_data" | jq .
        return
    fi
    
    # Text format
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Manjaro Pi 5 Installer - System Diagnostics"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    # Hardware
    echo "▶ Hardware Detection"
    local hw_compatible
    hw_compatible=$(echo "$json_data" | jq -r '.hardware.compatible')
    local hw_model
    hw_model=$(echo "$json_data" | jq -r '.hardware.model')
    
    if [[ "$hw_compatible" == "true" ]]; then
        echo "  ✓ Platform: $hw_model"
    else
        echo "  ✗ Platform: $hw_model (NOT COMPATIBLE)"
        echo "$json_data" | jq -r '.hardware.issues[]' | sed 's/^/    - /'
    fi
    echo
    
    # Boot
    echo "▶ Boot Partition"
    local boot_mounted
    boot_mounted=$(echo "$json_data" | jq -r '.boot.mounted')
    local boot_partition
    boot_partition=$(echo "$json_data" | jq -r '.boot.partition')
    
    if [[ "$boot_mounted" == "true" ]]; then
        echo "  ✓ Mounted: $boot_partition"
        local firmware_count missing_count
        firmware_count=$(echo "$json_data" | jq '.boot.firmware_files | length')
        missing_count=$(echo "$json_data" | jq '.boot.missing_files | length')
        echo "  ✓ Firmware files: $firmware_count found"
        if [[ "$missing_count" -gt 0 ]]; then
            echo "  ✗ Missing files:"
            echo "$json_data" | jq -r '.boot.missing_files[]' | sed 's/^/    - /'
        fi
    else
        echo "  ✗ Boot partition not found"
    fi
    echo
    
    # Filesystem
    echo "▶ Filesystem"
    local root_fs avail_space usage_percent
    root_fs=$(echo "$json_data" | jq -r '.filesystem.root_filesystem')
    avail_space=$(echo "$json_data" | jq -r '.filesystem.available_space')
    usage_percent=$(echo "$json_data" | jq -r '.filesystem.usage_percent')
    echo "  ✓ Type: $root_fs"
    echo "  ✓ Available: $avail_space ($usage_percent% used)"
    echo
    
    # Network
    echo "▶ Network"
    local connectivity dns_resolution
    connectivity=$(echo "$json_data" | jq -r '.network.connectivity')
    dns_resolution=$(echo "$json_data" | jq -r '.network.dns_resolution')
    
    if [[ "$connectivity" == "true" ]]; then
        echo "  ✓ Internet connectivity"
    else
        echo "  ✗ No internet connectivity"
    fi
    
    if [[ "$dns_resolution" == "true" ]]; then
        echo "  ✓ DNS resolution"
    else
        echo "  ✗ DNS resolution failed"
    fi
    echo
    
    # Commands
    echo "▶ Required Commands"
    local missing_req_count
    missing_req_count=$(echo "$json_data" | jq '.commands.missing_required | length')
    
    if [[ "$missing_req_count" -eq 0 ]]; then
        echo "  ✓ All required commands available"
    else
        echo "  ✗ Missing required commands:"
        echo "$json_data" | jq -r '.commands.missing_required[]' | sed 's/^/    - /'
    fi
    echo
    
    # Overall status
    echo "═══════════════════════════════════════════════════════════════"
    local overall_status
    overall_status=$(echo "$json_data" | jq -r '.overall_status')
    
    if [[ "$overall_status" == "ready" ]]; then
        echo "  ✓ System is READY for installation"
    else
        echo "  ✗ System has ISSUES - review above for details"
    fi
    echo "═══════════════════════════════════════════════════════════════"
}

# Main execution for standalone use
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    diagnostics_result=$(diagnostics_run_all)
    diagnostics_format_output "$diagnostics_result" "${1:-text}"
fi

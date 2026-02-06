#!/bin/bash
# HAL Module: USB Device Enumeration
# Detects and reports USB devices on the Raspberry Pi 5

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh" 2>/dev/null || true

# Enumerate USB devices
hal_usb_enumerate() {
    local devices=()
    
    if command -v lsusb &>/dev/null; then
        # Parse lsusb output
        while IFS= read -r line; do
            # Format: Bus 001 Device 002: ID 0bda:8179 Realtek Semiconductor Corp.
            if [[ "$line" =~ Bus\ ([0-9]+)\ Device\ ([0-9]+):\ ID\ ([0-9a-f]+):([0-9a-f]+)\ (.+)$ ]]; then
                local bus="${BASH_REMATCH[1]}"
                local device="${BASH_REMATCH[2]}"
                local vendor_id="${BASH_REMATCH[3]}"
                local product_id="${BASH_REMATCH[4]}"
                local description="${BASH_REMATCH[5]}"
                
                # Create JSON object
                local device_json
                device_json=$(jq -n \
                    --arg bus "$bus" \
                    --arg device "$device" \
                    --arg vendor_id "$vendor_id" \
                    --arg product_id "$product_id" \
                    --arg description "$description" \
                    '{
                        bus: ($bus | tonumber),
                        device: ($device | tonumber),
                        vendor_id: $vendor_id,
                        product_id: $product_id,
                        description: $description
                    }')
                devices+=("$device_json")
            fi
        done < <(lsusb 2>/dev/null)
    fi
    
    # Return JSON array
    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${devices[@]}" | jq -s .
    fi
}

# Detect WiFi adapters
hal_usb_detect_wifi() {
    local wifi_devices=()
    
    # Known WiFi adapter identifiers
    local -A wifi_chips=(
        ["0bda:8179"]="Realtek RTL8188EUS"
        ["0bda:818b"]="Realtek RTL8192EU"
        ["0bda:b812"]="Realtek RTL88x2BU"
        ["0cf3:9271"]="Atheros AR9271"
        ["148f:5370"]="Ralink RT5370"
        ["148f:5572"]="Ralink RT5572"
        ["0e8d:7612"]="MediaTek MT7612U"
        ["0e8d:7610"]="MediaTek MT7610U"
        ["050d:2103"]="Belkin Components F7D2102"
        ["0bda:8812"]="Realtek RTL8812AU (Alfa AWUS036ACH)"
    )
    
    # Get all USB devices
    local all_devices
    all_devices=$(hal_usb_enumerate)
    
    # Filter WiFi adapters
    while IFS= read -r device; do
        local vendor_id product_id description
        vendor_id=$(echo "$device" | jq -r '.vendor_id')
        product_id=$(echo "$device" | jq -r '.product_id')
        description=$(echo "$device" | jq -r '.description')
        
        local id="${vendor_id}:${product_id}"
        local chip="${wifi_chips[$id]:-Unknown}"
        
        # Check if it's a known WiFi adapter or description contains WiFi keywords
        if [[ -n "${wifi_chips[$id]}" ]] || [[ "$description" =~ [Ww]ireless|[Ww]i-?[Ff]i|802\.11|WLAN ]]; then
            local wifi_json
            wifi_json=$(echo "$device" | jq \
                --arg chip "$chip" \
                --arg monitor_capable "$(if [[ "$chip" =~ RTL8812AU|AR9271|RT5572|MT7612U ]]; then echo "true"; else echo "false"; fi)" \
                '. + {chip: $chip, monitor_capable: ($monitor_capable == "true")}')
            wifi_devices+=("$wifi_json")
        fi
    done < <(echo "$all_devices" | jq -c '.[]')
    
    # Return JSON array
    if [[ ${#wifi_devices[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${wifi_devices[@]}" | jq -s .
    fi
}

# Detect SDR devices
hal_usb_detect_sdr() {
    local sdr_devices=()
    
    # Known SDR identifiers
    local -A sdr_chips=(
        ["0bda:2838"]="RTL-SDR RTL2838"
        ["0bda:2832"]="RTL-SDR RTL2832U"
        ["1d50:604b"]="HackRF One"
        ["1fc9:000c"]="NXP Software Defined Radio"
        ["2500:0020"]="Airspy R2"
        ["2500:0023"]="Airspy Mini"
    )
    
    # Get all USB devices
    local all_devices
    all_devices=$(hal_usb_enumerate)
    
    # Filter SDR devices
    while IFS= read -r device; do
        local vendor_id product_id description
        vendor_id=$(echo "$device" | jq -r '.vendor_id')
        product_id=$(echo "$device" | jq -r '.product_id')
        description=$(echo "$device" | jq -r '.description')
        
        local id="${vendor_id}:${product_id}"
        local chip="${sdr_chips[$id]:-Unknown}"
        
        # Check if it's a known SDR device
        if [[ -n "${sdr_chips[$id]}" ]] || [[ "$description" =~ RTL-?SDR|Software.Defined.Radio|SDR ]]; then
            local sdr_json
            sdr_json=$(echo "$device" | jq \
                --arg chip "$chip" \
                --arg sample_rate "$(if [[ "$chip" =~ RTL ]]; then echo "2.4 MSPS"; elif [[ "$chip" =~ HackRF ]]; then echo "20 MSPS"; else echo "Unknown"; fi)" \
                '. + {chip: $chip, sample_rate: $sample_rate}')
            sdr_devices+=("$sdr_json")
        fi
    done < <(echo "$all_devices" | jq -c '.[]')
    
    # Return JSON array
    if [[ ${#sdr_devices[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${sdr_devices[@]}" | jq -s .
    fi
}

# Detect Bluetooth/BLE devices (nRF sniffers, etc.)
hal_usb_detect_ble() {
    local ble_devices=()
    
    # Known BLE sniffer identifiers
    local -A ble_chips=(
        ["1915:521f"]="Nordic Semiconductor nRF51822"
        ["1915:1234"]="Nordic Semiconductor nRF51422"
        ["1915:cafe"]="Nordic Semiconductor nRF52840"
        ["0a5c:21e8"]="Broadcom BCM20702A0"
    )
    
    # Get all USB devices
    local all_devices
    all_devices=$(hal_usb_enumerate)
    
    # Filter BLE devices
    while IFS= read -r device; do
        local vendor_id product_id description
        vendor_id=$(echo "$device" | jq -r '.vendor_id')
        product_id=$(echo "$device" | jq -r '.product_id')
        description=$(echo "$device" | jq -r '.description')
        
        local id="${vendor_id}:${product_id}"
        local chip="${ble_chips[$id]:-Unknown}"
        
        # Check if it's a known BLE device or Nordic/nRF in description
        if [[ -n "${ble_chips[$id]}" ]] || [[ "$description" =~ nRF|Nordic|Bluetooth.LE|BLE.Sniffer ]]; then
            local ble_json
            ble_json=$(echo "$device" | jq \
                --arg chip "$chip" \
                --arg sniffer_capable "$(if [[ "$chip" =~ nRF ]]; then echo "true"; else echo "false"; fi)" \
                '. + {chip: $chip, sniffer_capable: ($sniffer_capable == "true")}')
            ble_devices+=("$ble_json")
        fi
    done < <(echo "$all_devices" | jq -c '.[]')
    
    # Return JSON array
    if [[ ${#ble_devices[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${ble_devices[@]}" | jq -s .
    fi
}

# Get power information for USB devices (if available)
hal_usb_power_info() {
    local bus="$1"
    local device="$2"
    local power_info='{}'
    
    # Check sysfs for power information
    local syspath="/sys/bus/usb/devices/${bus}-${device}"
    if [[ -d "$syspath" ]]; then
        local current max_power speed
        current=$(cat "$syspath/bConfigurationValue" 2>/dev/null || echo "unknown")
        max_power=$(cat "$syspath/bMaxPower" 2>/dev/null || echo "unknown")
        speed=$(cat "$syspath/speed" 2>/dev/null || echo "unknown")
        
        power_info=$(jq -n \
            --arg current "$current" \
            --arg max_power "$max_power" \
            --arg speed "$speed" \
            '{
                configuration: $current,
                max_power: $max_power,
                speed: $speed
            }')
    fi
    
    echo "$power_info"
}

# Get complete USB report
hal_usb_report() {
    local all_devices wifi_devices sdr_devices ble_devices
    
    all_devices=$(hal_usb_enumerate)
    wifi_devices=$(hal_usb_detect_wifi)
    sdr_devices=$(hal_usb_detect_sdr)
    ble_devices=$(hal_usb_detect_ble)
    
    # Combine into report
    jq -n \
        --argjson all "$all_devices" \
        --argjson wifi "$wifi_devices" \
        --argjson sdr "$sdr_devices" \
        --argjson ble "$ble_devices" \
        '{
            all_devices: $all,
            wifi_adapters: $wifi,
            sdr_devices: $sdr,
            ble_devices: $ble,
            total: ($all | length),
            cyberpentester_hardware: {
                wifi_count: ($wifi | length),
                sdr_count: ($sdr | length),
                ble_count: ($ble | length)
            }
        }'
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hal_usb_report
fi

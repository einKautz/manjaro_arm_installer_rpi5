#!/bin/bash
# HAL Module: I2C Sensor Detection
# Detects I2C sensors on the Raspberry Pi 5

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh" 2>/dev/null || true

# Detect I2C buses
hal_sensor_detect_buses() {
    local buses=()
    
    if command -v i2cdetect &>/dev/null; then
        # Detect available I2C buses
        for bus in /dev/i2c-*; do
            if [[ -e "$bus" ]]; then
                buses+=("${bus##*/i2c-}")
            fi
        done
    fi
    
    # Return JSON array
    printf '%s\n' "${buses[@]}" | jq -R . | jq -s .
}

# Scan I2C bus for devices
hal_sensor_scan_bus() {
    local bus="$1"
    local devices=()
    
    if ! command -v i2cdetect &>/dev/null; then
        echo "[]"
        return
    fi
    
    # Scan bus (using quick write mode to avoid hanging)
    local output
    output=$(i2cdetect -y "$bus" 2>/dev/null || true)
    
    # Parse addresses (format: 0x40, 0x41, etc.)
    while read -r line; do
        # Extract hex addresses from output
        for addr in $line; do
            if [[ "$addr" =~ ^[0-9a-f]{2}$ ]]; then
                devices+=("0x$addr")
            fi
        done
    done <<< "$output"
    
    # Return unique addresses as JSON
    printf '%s\n' "${devices[@]}" | sort -u | jq -R . | jq -s .
}

# Detect INA3221 power monitor (address 0x40 or 0x41)
hal_sensor_detect_ina3221() {
    local result='{
        "detected": false,
        "address": null,
        "bus": null,
        "channels": 3
    }'
    
    if ! command -v i2cdetect &>/dev/null; then
        echo "$result"
        return
    fi
    
    # Check common I2C buses
    for bus in 1 3 4 5 6; do
        if [[ ! -e "/dev/i2c-$bus" ]]; then
            continue
        fi
        
        # Check common INA3221 addresses
        for addr in 0x40 0x41 0x42 0x43; do
            if i2cdetect -y "$bus" | grep -q "$(printf '%02x' $((addr)))"; then
                result=$(jq -n \
                    --arg bus "$bus" \
                    --arg addr "$(printf '0x%02x' $addr)" \
                    '{
                        detected: true,
                        address: $addr,
                        bus: ($bus | tonumber),
                        channels: 3
                    }')
                echo "$result"
                return
            fi
        done
    done
    
    echo "$result"
}

# Detect DS3231 RTC (address 0x68)
hal_sensor_detect_rtc() {
    local result='{
        "detected": false,
        "address": null,
        "bus": null,
        "type": "DS3231"
    }'
    
    if ! command -v i2cdetect &>/dev/null; then
        echo "$result"
        return
    fi
    
    # Check common I2C buses
    for bus in 1 3 4 5 6; do
        if [[ ! -e "/dev/i2c-$bus" ]]; then
            continue
        fi
        
        # DS3231 is at 0x68
        if i2cdetect -y "$bus" | grep -q "68"; then
            result=$(jq -n \
                --arg bus "$bus" \
                '{
                    detected: true,
                    address: "0x68",
                    bus: ($bus | tonumber),
                    type: "DS3231"
                }')
            echo "$result"
            return
        fi
    done
    
    echo "$result"
}

# Get complete sensor report
hal_sensor_report() {
    local buses devices ina3221 rtc
    
    buses=$(hal_sensor_detect_buses)
    ina3221=$(hal_sensor_detect_ina3221)
    rtc=$(hal_sensor_detect_rtc)
    
    # Scan all detected buses
    devices="{"
    local first=true
    while IFS= read -r bus; do
        if [[ -n "$bus" ]]; then
            local scan
            scan=$(hal_sensor_scan_bus "$bus")
            if [[ "$first" == true ]]; then
                first=false
            else
                devices+=","
            fi
            devices+="\"$bus\": $scan"
        fi
    done < <(echo "$buses" | jq -r '.[]')
    devices+="}"
    
    # Combine into report
    jq -n \
        --argjson buses "$buses" \
        --argjson devices "$devices" \
        --argjson ina3221 "$ina3221" \
        --argjson rtc "$rtc" \
        '{
            buses: $buses,
            devices: $devices,
            ina3221: $ina3221,
            rtc: $rtc
        }'
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hal_sensor_report
fi

#!/usr/bin/env bash
#
# Profile Loader
# Loads and validates installation profiles from JSON files
#

# Source logging if not already loaded
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/log.sh"
fi

# Profile registry
declare -gA PROFILE_REGISTRY=()
declare -gA PROFILE_DESCRIPTIONS=()
declare -gA PROFILE_FEATURES=()

# Load a profile from JSON file
profile_load() {
    local profile_name="$1"
    local profile_file="${SCRIPT_DIR}/../profiles/${profile_name}.json"
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile: Profile file not found: $profile_file"
        return 1
    fi
    
    log_info "Profile: Loading profile: $profile_name"
    
    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        log_error "Profile: jq is required but not installed"
        return 1
    fi
    
    # Validate JSON
    if ! jq empty "$profile_file" 2>/dev/null; then
        log_error "Profile: Invalid JSON in $profile_file"
        return 1
    fi
    
    # Store profile data
    PROFILE_REGISTRY["$profile_name"]="$profile_file"
    
    # Extract description
    local description
    description=$(jq -r '.description // "No description"' "$profile_file")
    PROFILE_DESCRIPTIONS["$profile_name"]="$description"
    
    # Extract features
    local features
    features=$(jq -r '.features | to_entries | map("\(.key)=\(.value)") | join(",")' "$profile_file")
    PROFILE_FEATURES["$profile_name"]="$features"
    
    log_info "Profile: Loaded $profile_name - $description"
    return 0
}

# Load all available profiles
profile_load_all() {
    local profile_dir="${SCRIPT_DIR}/../profiles"
    
    log_info "Profile: Loading all profiles from $profile_dir"
    
    if [[ ! -d "$profile_dir" ]]; then
        log_error "Profile: Profile directory not found: $profile_dir"
        return 1
    fi
    
    local count=0
    for profile_file in "$profile_dir"/*.json; do
        if [[ -f "$profile_file" ]]; then
            local profile_name
            profile_name=$(basename "$profile_file" .json)
            if profile_load "$profile_name"; then
                ((count++))
            fi
        fi
    done
    
    log_info "Profile: Loaded $count profile(s)"
    return 0
}

# Get profile data
profile_get() {
    local profile_name="$1"
    local key="$2"
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    local profile_file="${PROFILE_REGISTRY[$profile_name]}"
    
    if [[ -z "$key" ]]; then
        # Return entire profile
        cat "$profile_file"
    else
        # Return specific key
        jq -r ".${key} // empty" "$profile_file"
    fi
}

# Get profile packages
profile_get_packages() {
    local profile_name="$1"
    local package_type="${2:-all}"  # base, edition, all
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    local profile_file="${PROFILE_REGISTRY[$profile_name]}"
    
    case "$package_type" in
        base)
            jq -r '.base_packages[]' "$profile_file"
            ;;
        edition)
            jq -r '.edition_packages[]' "$profile_file"
            ;;
        all)
            {
                jq -r '.base_packages[]' "$profile_file"
                jq -r '.edition_packages[]' "$profile_file"
            }
            ;;
        *)
            log_error "Profile: Invalid package type: $package_type"
            return 1
            ;;
    esac
}

# Get profile services
profile_get_services() {
    local profile_name="$1"
    local action="${2:-enable}"  # enable, disable
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    local profile_file="${PROFILE_REGISTRY[$profile_name]}"
    
    jq -r ".services.${action}[]" "$profile_file" 2>/dev/null || true
}

# Get profile optimizations
profile_get_optimizations() {
    local profile_name="$1"
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    local profile_file="${PROFILE_REGISTRY[$profile_name]}"
    
    jq -r '.optimizations[]' "$profile_file" 2>/dev/null || true
}

# Get profile config value
profile_get_config() {
    local profile_name="$1"
    local config_key="$2"
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    local profile_file="${PROFILE_REGISTRY[$profile_name]}"
    
    jq -r ".config.${config_key} // empty" "$profile_file"
}

# Check if profile has feature
profile_has_feature() {
    local profile_name="$1"
    local feature="$2"
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    local profile_file="${PROFILE_REGISTRY[$profile_name]}"
    
    local has_feature
    has_feature=$(jq -r ".features.${feature} // false" "$profile_file")
    
    if [[ "$has_feature" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# List all loaded profiles
profile_list() {
    if [[ ${#PROFILE_REGISTRY[@]} -eq 0 ]]; then
        log_warn "Profile: No profiles loaded"
        return 1
    fi
    
    echo "Available Profiles:"
    echo "==================="
    for profile_name in "${!PROFILE_REGISTRY[@]}"; do
        local description="${PROFILE_DESCRIPTIONS[$profile_name]}"
        printf "%-15s %s\n" "$profile_name" "$description"
    done
}

# Apply profile to installation
profile_apply() {
    local profile_name="$1"
    
    if [[ -z "${PROFILE_REGISTRY[$profile_name]:-}" ]]; then
        log_error "Profile: Profile not loaded: $profile_name"
        return 1
    fi
    
    log_info "Profile: Applying profile: $profile_name"
    
    # Export profile variables
    export PROFILE_NAME="$profile_name"
    export EDITION="$profile_name"
    
    # Export display manager
    local dm
    dm=$(profile_get "$profile_name" "display_manager")
    if [[ "$dm" != "null" ]]; then
        export DISPLAY_MANAGER="$dm"
    fi
    
    # Export GPU memory
    local gpu_mem
    gpu_mem=$(profile_get_config "$profile_name" "gpu_mem")
    if [[ -n "$gpu_mem" ]]; then
        export GPU_MEM="$gpu_mem"
    fi
    
    # Export hardware features
    export ENABLE_I2C=$(profile_get_config "$profile_name" "enable_i2c")
    export ENABLE_SPI=$(profile_get_config "$profile_name" "enable_spi")
    export ENABLE_UART=$(profile_get_config "$profile_name" "enable_uart")
    export DISABLE_BT=$(profile_get_config "$profile_name" "disable_bt")
    
    log_info "Profile: Applied profile: $profile_name"
    return 0
}

# Export functions
export -f profile_load
export -f profile_load_all
export -f profile_get
export -f profile_get_packages
export -f profile_get_services
export -f profile_get_optimizations
export -f profile_get_config
export -f profile_has_feature
export -f profile_list
export -f profile_apply

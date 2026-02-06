#!/usr/bin/env bash
#
# Unified Logging System for Manjaro ARM Pi 5 Installer
# Part of Phase 3 Foundation
#

# Configuration
LOG_JSON="${LOG_JSON:-0}"  # Set to 1 to enable JSON output
LOG_FILE="${LOG_FILE:-/var/log/manjaro-installer/installer.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR
LOG_PHASE="${LOG_PHASE:-unknown}"  # Current installation phase

# ANSI color codes
declare -A LOG_COLORS=(
    [DEBUG]='\033[0;36m'    # Cyan
    [INFO]='\033[0;32m'     # Green
    [WARN]='\033[1;33m'     # Yellow
    [ERROR]='\033[0;31m'    # Red
    [NC]='\033[0m'          # No Color
)

# Log level priority (for filtering)
declare -A LOG_PRIORITY=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# Initialize logging system
log_init() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    
    # Create log directory if it doesn't exist
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            # Fallback to /tmp if we can't create /var/log
            LOG_FILE="/tmp/manjaro-installer/installer.log"
            log_dir="/tmp/manjaro-installer"
            mkdir -p "$log_dir" 2>/dev/null || true
        }
    fi
    
    # Touch log file to ensure it's writable
    touch "$LOG_FILE" 2>/dev/null || true
}

# Set current installation phase
log_set_phase() {
    LOG_PHASE="$1"
}

# Get timestamp in ISO 8601 format
log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Internal logging function
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(log_timestamp)"
    
    # Check if this log level should be output
    local current_priority="${LOG_PRIORITY[$LOG_LEVEL]}"
    local msg_priority="${LOG_PRIORITY[$level]}"
    
    if [[ $msg_priority -lt $current_priority ]]; then
        return 0
    fi
    
    # JSON output
    if [[ $LOG_JSON -eq 1 ]]; then
        local json_line
        # Escape quotes in message
        local escaped_msg="${message//\"/\\\"}"
        json_line=$(printf '{"ts":"%s","level":"%s","phase":"%s","msg":"%s"}' \
            "$timestamp" "$level" "$LOG_PHASE" "$escaped_msg")
        
        # Write to log file
        echo "$json_line" >> "$LOG_FILE" 2>/dev/null
        
        # Also output to stdout for immediate feedback
        echo "$json_line"
    else
        # Text output with color
        local color="${LOG_COLORS[$level]}"
        local nc="${LOG_COLORS[NC]}"
        local formatted_msg
        formatted_msg=$(printf "[%s] [%s] [%s] %s" "$timestamp" "$level" "$LOG_PHASE" "$message")
        
        # Write to log file (no color)
        echo "$formatted_msg" >> "$LOG_FILE" 2>/dev/null
        
        # Output to stdout with color
        echo -e "${color}${formatted_msg}${nc}"
    fi
}

# Public logging functions
log_debug() {
    _log DEBUG "$@"
}

log_info() {
    _log INFO "$@"
}

log_warn() {
    _log WARN "$@"
}

log_error() {
    _log ERROR "$@"
}

# Compatibility aliases for existing code
log() {
    local level="$1"
    shift
    case "$level" in
        DEBUG|INFO|WARN|ERROR)
            _log "$level" "$@"
            ;;
        *)
            # Default to INFO if level not recognized
            _log INFO "$level" "$@"
            ;;
    esac
}

msg() {
    log_info "$@"
}

info() {
    log_info "$@"
}

err() {
    log_error "$@"
}

# Log function entry/exit (useful for debugging)
log_function_enter() {
    log_debug ">>> Entering function: $1"
}

log_function_exit() {
    local func_name="$1"
    local exit_code="${2:-0}"
    if [[ $exit_code -eq 0 ]]; then
        log_debug "<<< Exiting function: $func_name (success)"
    else
        log_debug "<<< Exiting function: $func_name (exit code: $exit_code)"
    fi
}

# Export log file path for use in other scripts
export_log_path() {
    echo "$LOG_FILE"
}

# Initialize on source
log_init

# Export functions for use in other scripts
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log
export -f msg
export -f info
export -f err
export -f log_set_phase
export -f log_function_enter
export -f log_function_exit
export -f export_log_path

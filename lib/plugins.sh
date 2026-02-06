#!/usr/bin/env bash
#
# Plugin Loader System for Manjaro ARM Pi 5 Installer
# Phase 3 - Step 2: Plugin Architecture
#

# Source logging system if not already loaded
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/log.sh"
fi

# Plugin system state
declare -gA PLUGIN_REGISTRY=()           # Maps plugin name to file path
declare -gA PLUGIN_VERSIONS=()           # Maps plugin name to version
declare -gA PLUGIN_DEPENDENCIES=()       # Maps plugin name to dependency list
declare -gA PLUGIN_PHASES=()             # Maps plugin name to phase list
declare -gA PLUGIN_LOADED=()             # Tracks which plugins are loaded
declare -ga PLUGIN_EXECUTION_ORDER=()    # Ordered list for execution

# Plugin base directory
PLUGIN_BASE_DIR="${PLUGIN_BASE_DIR:-plugins}"

# Initialize plugin system
plugin_system_init() {
    log_set_phase "plugin-system"
    log_info "Initializing plugin system"
    log_debug "Plugin base directory: ${PLUGIN_BASE_DIR}"
    
    # Clear plugin state
    PLUGIN_REGISTRY=()
    PLUGIN_VERSIONS=()
    PLUGIN_DEPENDENCIES=()
    PLUGIN_PHASES=()
    PLUGIN_LOADED=()
    PLUGIN_EXECUTION_ORDER=()
}

# Discover all plugins in the plugin directory
plugin_discover() {
    log_info "Discovering plugins in ${PLUGIN_BASE_DIR}/"
    
    local plugin_count=0
    
    # Find all plugin-*.sh files
    while IFS= read -r -d '' plugin_file; do
        local plugin_name
        plugin_name=$(basename "${plugin_file}" .sh | sed 's/^plugin-//')
        
        log_debug "Found plugin file: ${plugin_file}"
        
        # Register the plugin
        PLUGIN_REGISTRY["${plugin_name}"]="${plugin_file}"
        ((plugin_count++))
    done < <(find "${PLUGIN_BASE_DIR}" -type f -name "plugin-*.sh" -print0 2>/dev/null)
    
    log_info "Discovered ${plugin_count} plugin(s)"
    
    if [[ ${plugin_count} -eq 0 ]]; then
        log_warn "No plugins found in ${PLUGIN_BASE_DIR}/"
        return 0
    fi
    
    return 0
}

# Load plugin metadata without executing it
plugin_load_metadata() {
    local plugin_name="$1"
    local plugin_file="${PLUGIN_REGISTRY[${plugin_name}]}"
    
    if [[ -z "${plugin_file}" ]]; then
        log_error "Plugin not found in registry: ${plugin_name}"
        return 1
    fi
    
    if [[ ! -f "${plugin_file}" ]]; then
        log_error "Plugin file not found: ${plugin_file}"
        return 1
    fi
    
    log_debug "Loading metadata for plugin: ${plugin_name}"
    
    # Source the plugin in a subshell to extract metadata
    local metadata
    metadata=$(bash -c "
        source '${plugin_file}' 2>/dev/null || exit 1
        echo \"NAME:\${PLUGIN_NAME:-}\"
        echo \"VERSION:\${PLUGIN_VERSION:-1.0}\"
        echo \"DEPENDS:\${PLUGIN_DEPENDS[*]:-}\"
        echo \"PHASES:\${PLUGIN_PHASES[*]:-}\"
    ") || {
        log_error "Failed to load plugin metadata: ${plugin_file}"
        return 1
    }
    
    # Parse metadata
    local name version depends phases
    while IFS=: read -r key value; do
        case "${key}" in
            NAME)
                name="${value}"
                ;;
            VERSION)
                version="${value}"
                ;;
            DEPENDS)
                depends="${value}"
                ;;
            PHASES)
                phases="${value}"
                ;;
        esac
    done <<< "${metadata}"
    
    # Validate plugin name matches
    if [[ -z "${name}" ]]; then
        log_error "Plugin missing PLUGIN_NAME: ${plugin_file}"
        return 1
    fi
    
    if [[ "${name}" != "${plugin_name}" ]]; then
        log_warn "Plugin name mismatch: file=${plugin_name}, declared=${name}"
    fi
    
    # Store metadata
    PLUGIN_VERSIONS["${plugin_name}"]="${version}"
    PLUGIN_DEPENDENCIES["${plugin_name}"]="${depends}"
    PLUGIN_PHASES["${plugin_name}"]="${phases}"
    
    log_debug "Plugin ${plugin_name}: version=${version}, depends=[${depends}], phases=[${phases}]"
    
    return 0
}

# Resolve plugin dependencies and determine execution order
plugin_resolve_dependencies() {
    log_info "Resolving plugin dependencies"
    
    local -A visited=()
    local -A in_progress=()
    PLUGIN_EXECUTION_ORDER=()
    
    # Topological sort using DFS - helper function
    _plugin_dfs_visit() {
        local node="$1"
        
        # Check for cycles
        if [[ -n "${in_progress[${node}]:-}" ]]; then
            log_error "Circular dependency detected involving: ${node}"
            return 1
        fi
        
        # Already visited
        if [[ -n "${visited[${node}]:-}" ]]; then
            return 0
        fi
        
        in_progress["${node}"]=1
        
        # Visit dependencies first
        local deps="${PLUGIN_DEPENDENCIES[${node}]:-}"
        if [[ -n "${deps}" ]]; then
            for dep in ${deps}; do
                # Check if dependency exists
                if [[ -z "${PLUGIN_REGISTRY[${dep}]:-}" ]]; then
                    log_error "Plugin ${node} depends on missing plugin: ${dep}"
                    return 1
                fi
                
                _plugin_dfs_visit "${dep}" || return 1
            done
        fi
        
        unset "in_progress[${node}]"
        visited["${node}"]=1
        PLUGIN_EXECUTION_ORDER+=("${node}")
        
        return 0
    }
    
    # Visit all plugins
    for plugin_name in "${!PLUGIN_REGISTRY[@]}"; do
        _plugin_dfs_visit "${plugin_name}" || return 1
    done
    
    log_info "Dependency resolution complete: ${#PLUGIN_EXECUTION_ORDER[@]} plugin(s) in execution order"
    log_debug "Execution order: ${PLUGIN_EXECUTION_ORDER[*]}"
    
    return 0
}

# Load a plugin (source it into current shell)
plugin_load() {
    local plugin_name="$1"
    local plugin_file="${PLUGIN_REGISTRY[${plugin_name}]}"
    
    if [[ -n "${PLUGIN_LOADED[${plugin_name}]:-}" ]]; then
        log_debug "Plugin already loaded: ${plugin_name}"
        return 0
    fi
    
    if [[ -z "${plugin_file}" ]] || [[ ! -f "${plugin_file}" ]]; then
        log_error "Cannot load plugin ${plugin_name}: file not found"
        return 1
    fi
    
    log_info "Loading plugin: ${plugin_name} (${PLUGIN_VERSIONS[${plugin_name}]:-unknown})"
    
    # Source the plugin
    # shellcheck source=/dev/null
    source "${plugin_file}" || {
        log_error "Failed to source plugin: ${plugin_file}"
        return 1
    }
    
    PLUGIN_LOADED["${plugin_name}"]=1
    log_debug "Plugin loaded successfully: ${plugin_name}"
    
    return 0
}

# Execute a specific phase across all plugins
plugin_run_phase() {
    local phase="$1"
    
    log_set_phase "plugin-${phase}"
    log_info "Executing plugin phase: ${phase}"
    
    local executed=0
    local failed=0
    
    # Execute plugins in dependency order
    for plugin_name in "${PLUGIN_EXECUTION_ORDER[@]}"; do
        local phases="${PLUGIN_PHASES[${plugin_name}]:-}"
        
        # Check if plugin supports this phase
        if [[ ! " ${phases} " =~ \ ${phase}\  ]]; then
            log_debug "Plugin ${plugin_name} does not support phase: ${phase}"
            continue
        fi
        
        # Ensure plugin is loaded
        if [[ -z "${PLUGIN_LOADED[${plugin_name}]:-}" ]]; then
            plugin_load "${plugin_name}" || {
                log_error "Failed to load plugin: ${plugin_name}"
                ((failed++))
                continue
            }
        fi
        
        # Execute phase function
        local phase_func="plugin_run_${phase//-/_}"
        
        if ! command -v "${phase_func}" &>/dev/null; then
            log_error "Plugin ${plugin_name} missing phase function: ${phase_func}"
            ((failed++))
            continue
        fi
        
        log_info "Executing ${plugin_name}.${phase_func}"
        
        if "${phase_func}"; then
            log_debug "Plugin ${plugin_name} phase ${phase} completed successfully"
            ((executed++))
        else
            log_error "Plugin ${plugin_name} phase ${phase} failed"
            ((failed++))
        fi
    done
    
    log_info "Phase ${phase} complete: ${executed} executed, ${failed} failed"
    
    if [[ ${failed} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# List all discovered plugins
plugin_list() {
    echo "Discovered Plugins:"
    echo "==================="
    
    for plugin_name in "${!PLUGIN_REGISTRY[@]}"; do
        local version="${PLUGIN_VERSIONS[${plugin_name}]:-unknown}"
        local deps="${PLUGIN_DEPENDENCIES[${plugin_name}]:-none}"
        local phases="${PLUGIN_PHASES[${plugin_name}]:-none}"
        local loaded="${PLUGIN_LOADED[${plugin_name}]:+[LOADED]}"
        
        printf "%-20s %s\n" "${plugin_name}" "${version} ${loaded}"
        printf "  %-18s %s\n" "Dependencies:" "${deps}"
        printf "  %-18s %s\n" "Phases:" "${phases}"
        echo ""
    done
}

# Initialize and discover plugins
plugin_init() {
    plugin_system_init
    plugin_discover || return 1
    
    # Load metadata for all plugins
    for plugin_name in "${!PLUGIN_REGISTRY[@]}"; do
        plugin_load_metadata "${plugin_name}" || {
            log_warn "Failed to load metadata for plugin: ${plugin_name}"
        }
    done
    
    # Resolve dependencies
    plugin_resolve_dependencies || return 1
    
    log_info "Plugin system initialized: ${#PLUGIN_EXECUTION_ORDER[@]} plugin(s) ready"
    
    return 0
}

# Export plugin functions
export -f plugin_system_init
export -f plugin_discover
export -f plugin_load_metadata
export -f plugin_resolve_dependencies
export -f plugin_load
export -f plugin_run_phase
export -f plugin_list
export -f plugin_init

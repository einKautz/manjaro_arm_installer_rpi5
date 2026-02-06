# Plugin System Documentation

## Overview

The Manjaro ARM Pi 5 Installer now features a modular plugin architecture that allows functionality to be organized into self-contained, reusable components.

## Plugin Structure

```
plugins/
├── boot/                    # Boot-related plugins
│   └── plugin-pi5-boot.sh   # Multi-strategy boot file population
├── network/                 # Network plugins
│   └── plugin-wifi.sh       # Wi-Fi configuration and management
├── hw/                      # Hardware detection plugins
│   └── plugin-pi5-hw.sh     # Pi 5 hardware detection
├── diagnostics/             # Diagnostic plugins
│   └── plugin-boot-diagnostics.sh  # Boot partition verification
└── post-install/            # Post-installation optimization plugins
    ├── plugin-zram.sh       # Compressed swap in RAM
    ├── plugin-sysctl.sh     # Kernel parameter tuning
    ├── plugin-fstrim.sh     # SSD TRIM timer
    └── plugin-cpupower.sh   # CPU frequency governor
```

## Available Plugins

### Boot Plugins

**pi5-boot** (v1.0)
- Multi-strategy boot file population
- Downloads boot files or uses packages
- Ensures kernel, DTBs, and firmware are present
- **Phase**: `boot`

### Network Plugins

**wifi** (v1.0)
- Wi-Fi network scanning and connection
- NetworkManager integration
- Configuration persistence to target system
- **Phases**: `network`, `config`
- **Exported Functions**: `wifi_scan`, `wifi_connect`, `wifi_test_internet`

### Hardware Plugins

**pi5-hw** (v1.0)
- Detects Raspberry Pi 5 hardware
- Identifies CPU, memory, storage
- Validates Pi 5 compatibility
- **Phase**: `detect`
- **Exported Functions**: `hw_summary`, `hw_is_pi5`

### Diagnostic Plugins

**boot-diagnostics** (v1.0)
- Comprehensive boot partition verification
- Checks kernel, DTB, firmware, overlays
- Identifies configuration issues
- **Phase**: `diagnostics`
- **Exported Functions**: `diagnostics_json`

### Post-Install Optimization Plugins

**zram** (v1.0)
- Enables compressed swap in RAM
- Improves performance on limited memory
- **Phase**: `post-install`

**sysctl** (v1.0)
- Kernel parameter tuning for Pi 5
- Optimizes VM settings
- **Phase**: `post-install`

**fstrim** (v1.0)
- Enables weekly TRIM for SSDs
- Improves SSD longevity
- **Phase**: `post-install`

**cpupower** (v1.0)
- Configures CPU frequency scaling
- Sets ondemand governor
- **Phase**: `post-install`

## Plugin Development

### Plugin Template

```bash
#!/usr/bin/env bash
#
# Plugin Description
#

PLUGIN_NAME="my-plugin"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=("other-plugin")  # Optional dependencies
PLUGIN_PHASES=("boot" "config")  # Phases this plugin supports

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Phase function (replace 'boot' with your phase name)
plugin_run_boot() {
    log_info "My Plugin: Executing boot phase"
    log_set_phase "my-plugin-boot"
    
    # Your plugin logic here
    
    return 0  # 0 = success, 1 = failure
}

# Export any helper functions
export -f my_helper_function
```

### Plugin Naming Convention

- Filename: `plugin-<name>.sh`
- Must be in a subdirectory of `plugins/`
- Plugin name matches filename without `plugin-` prefix

### Available Phases

- **detect** - Hardware detection and validation
- **boot** - Boot partition setup
- **network** - Network configuration
- **config** - System configuration
- **post-install** - Optimizations and final tweaks
- **diagnostics** - System verification and health checks

### Plugin Metadata

Required variables:
- `PLUGIN_NAME` - Unique identifier
- `PLUGIN_VERSION` - Semantic version
- `PLUGIN_DEPENDS` - Array of dependency plugin names
- `PLUGIN_PHASES` - Array of supported phases

### Phase Functions

Each phase must have a corresponding function:
- Phase `boot` → function `plugin_run_boot()`
- Phase `network` → function `plugin_run_network()`
- Phase `post-install` → function `plugin_run_post_install()`

Function names use underscores (`_`) for hyphens in phase names.

## Using the Plugin System

### Initialize Plugin System

```bash
source lib/log.sh
source lib/plugins.sh

# Initialize and discover plugins
plugin_init

# List discovered plugins
plugin_list
```

### Execute a Phase

```bash
# Run all plugins that support the 'boot' phase
plugin_run_phase "boot"

# Run post-install optimizations
plugin_run_phase "post-install"
```

### Load a Specific Plugin

```bash
# Load plugin by name
plugin_load "pi5-boot"

# Now you can call plugin functions directly
plugin_run_boot
```

## Plugin Dependencies

Plugins can declare dependencies:

```bash
PLUGIN_DEPENDS=("pi5-hw" "wifi")
```

The plugin system will:
- Verify all dependencies exist
- Load dependencies in correct order
- Detect circular dependencies
- Fail early if dependencies are missing

## Testing Plugins

Create tests in `test/plugins.bats`:

```bash
@test "my plugin can be loaded" {
    source plugins/my-category/plugin-my-plugin.sh
    [ "$PLUGIN_NAME" = "my-plugin" ]
}

@test "my plugin phase function exists" {
    source plugins/my-category/plugin-my-plugin.sh
    command -v plugin_run_boot
}
```

Run tests:
```bash
make test
```

## Debugging Plugins

Enable debug logging:

```bash
export LOG_LEVEL=DEBUG
plugin_init
plugin_run_phase "boot"
```

Check plugin execution order:

```bash
plugin_init
echo "${PLUGIN_EXECUTION_ORDER[@]}"
```

## Best Practices

1. **Use logging**: Always use `log_info`, `log_error`, etc.
2. **Set phase**: Call `log_set_phase` at start of phase function
3. **Handle errors**: Return non-zero on failure
4. **Export helpers**: Export any functions other scripts might use
5. **Check dependencies**: Verify required tools/files exist
6. **Document**: Add clear comments explaining what plugin does
7. **Test**: Write bats tests for your plugin
8. **Lint**: Ensure plugin passes shellcheck

## Plugin System Architecture

The plugin loader (`lib/plugins.sh`) provides:

- **Auto-discovery**: Finds all `plugin-*.sh` files
- **Metadata extraction**: Reads plugin name, version, dependencies, phases
- **Dependency resolution**: Topological sort with cycle detection
- **Phase execution**: Runs plugins in correct order for each phase
- **Error handling**: Captures and logs plugin failures
- **Isolation**: Plugins can't interfere with each other

## Integration with Main Installer

The main installer can be refactored to use plugins:

```bash
# Old monolithic approach
copy_pi5_boot_files
apply_optimizations

# New plugin-based approach
source lib/plugins.sh
plugin_init
plugin_run_phase "boot"
plugin_run_phase "post-install"
```

## Future Enhancements

Planned features:
- Plugin configuration files (JSON/YAML)
- Conditional plugin execution
- Plugin marketplace/repository
- GUI plugin manager
- Plugin update system

# Quick Reference: Plugin System

## Commands

### Development
```bash
make dev-shell      # Launch ARM development container
make test           # Run 48 bats tests
make lint           # Run shellcheck on all scripts
make check-deps     # Verify dependencies installed
make install-deps   # Install development tools
make clean          # Remove temporary files
make pre-commit     # Run lint + test before commit
```

### Plugin System
```bash
# Initialize plugin system
source lib/log.sh
source lib/plugins.sh
plugin_init

# List discovered plugins
plugin_list

# Load a specific plugin
plugin_load "plugin-name"

# Execute a phase
plugin_run_phase "phase-name"
```

## Available Phases

| Phase | Purpose | Plugins |
|-------|---------|---------|
| `detect` | Hardware detection | pi5-hw |
| `boot` | Boot file setup | pi5-boot |
| `network` | Network config | wifi |
| `config` | System config | wifi |
| `diagnostics` | Verification | boot-diagnostics |
| `post-install` | Optimizations | zram, sysctl, fstrim, cpupower |

## Plugin Template

```bash
#!/usr/bin/env bash
#
# Plugin: <description>
#

PLUGIN_NAME="my-plugin"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()                    # Array of dependencies
PLUGIN_PHASES=("boot")               # Supported phases

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

# Phase function
plugin_run_boot() {
    log_set_phase "my-plugin-boot"
    log_info "Executing boot phase"
    
    # Your code here
    
    return 0  # 0=success, 1=failure
}

# Export functions if needed
export -f my_helper_function
```

## Logging Functions

```bash
log_info "message"      # Info message (green)
log_warn "message"      # Warning (yellow)
log_error "message"     # Error (red)
log_debug "message"     # Debug (cyan, only if LOG_LEVEL=DEBUG)

log_set_phase "phase"   # Set current phase for context
```

### JSON Logging
```bash
export LOG_JSON=1
export LOG_DIR="/var/log/manjaro-installer"
# Logs to: /var/log/manjaro-installer/install_YYYYMMDD_HHMMSS.json
```

## Plugin Metadata

### Required Variables
- `PLUGIN_NAME` - Unique identifier
- `PLUGIN_VERSION` - Semantic version (e.g., "1.0")
- `PLUGIN_DEPENDS` - Array of dependency names
- `PLUGIN_PHASES` - Array of supported phases

### Phase Functions
- Phase `boot` → function `plugin_run_boot()`
- Phase `network` → function `plugin_run_network()`
- Phase `post-install` → function `plugin_run_post_install()`

*Note: Hyphens in phase names become underscores in function names*

## Plugin Discovery

Plugins are auto-discovered from:
```bash
plugins/
├── boot/plugin-*.sh
├── network/plugin-*.sh
├── hw/plugin-*.sh
├── diagnostics/plugin-*.sh
└── post-install/plugin-*.sh
```

**Naming Convention**: `plugin-<name>.sh`

## Testing

### Create Plugin Test
```bash
# In test/plugins.bats
@test "my plugin can be loaded" {
    source plugins/category/plugin-my-plugin.sh
    [ "$PLUGIN_NAME" = "my-plugin" ]
}

@test "my plugin phase function exists" {
    source plugins/category/plugin-my-plugin.sh
    command -v plugin_run_boot
}
```

### Run Tests
```bash
make test
# 48 tests, 0 failures
```

## Debugging

### Enable Debug Logging
```bash
export LOG_LEVEL=DEBUG
plugin_init
plugin_run_phase "boot"
```

### Check Plugin Order
```bash
plugin_init
echo "${PLUGIN_EXECUTION_ORDER[@]}"
```

### Validate Single Plugin
```bash
shellcheck plugins/category/plugin-name.sh
```

## Current Plugins

| Plugin | Version | Phases | Dependencies |
|--------|---------|--------|--------------|
| pi5-boot | 1.0 | boot | none |
| wifi | 1.0 | network, config | none |
| pi5-hw | 1.0 | detect | none |
| boot-diagnostics | 1.0 | diagnostics | none |
| zram | 1.0 | post-install | none |
| sysctl | 1.0 | post-install | none |
| fstrim | 1.0 | post-install | none |
| cpupower | 1.0 | post-install | none |

## Common Patterns

### Check Dependencies
```bash
plugin_run_boot() {
    if ! command -v nmcli &>/dev/null; then
        log_error "NetworkManager not found"
        return 1
    fi
    
    # ... rest of code
}
```

### Export Helper Functions
```bash
wifi_scan() {
    nmcli device wifi list
}
export -f wifi_scan

plugin_run_network() {
    wifi_scan  # Available in main installer
}
```

### Handle Errors
```bash
plugin_run_boot() {
    if ! some_operation; then
        log_error "Operation failed"
        return 1
    fi
    
    log_info "Operation successful"
    return 0
}
```

## Best Practices

1. ✅ **Use logging functions** - Always use `log_info`, `log_error`, etc.
2. ✅ **Set phase** - Call `log_set_phase` at start of phase function
3. ✅ **Return codes** - Return 0 for success, 1 for failure
4. ✅ **Export helpers** - Export functions that others might use
5. ✅ **Check deps** - Verify required tools/files exist
6. ✅ **Document** - Add clear comments
7. ✅ **Test** - Write bats tests for your plugin
8. ✅ **Lint** - Ensure plugin passes shellcheck

## Integration Example

```bash
#!/usr/bin/env bash
# Main installer script

set -euo pipefail

# Source libraries
source lib/log.sh
source lib/plugins.sh

main() {
    log_info "Starting Manjaro Pi 5 Installation"
    
    # Initialize plugin system
    plugin_init
    
    # Run installation phases
    plugin_run_phase "detect"
    plugin_run_phase "boot"
    plugin_run_phase "network"
    plugin_run_phase "config"
    plugin_run_phase "post-install"
    plugin_run_phase "diagnostics"
    
    log_info "Installation complete"
}

main "$@"
```

## Files Modified/Created

### Core Libraries
- [lib/log.sh](../lib/log.sh) - Unified logging system (170 lines)
- [lib/plugins.sh](../lib/plugins.sh) - Plugin loader (330 lines)

### Development Tools
- [Makefile](../Makefile) - Developer commands
- [.shellcheckrc](../.shellcheckrc) - Linting config

### Tests
- [test/installer.bats](../test/installer.bats) - 32 tests
- [test/plugins.bats](../test/plugins.bats) - 16 tests

### Plugins
- [plugins/boot/plugin-pi5-boot.sh](../plugins/boot/plugin-pi5-boot.sh)
- [plugins/network/plugin-wifi.sh](../plugins/network/plugin-wifi.sh)
- [plugins/hw/plugin-pi5-hw.sh](../plugins/hw/plugin-pi5-hw.sh)
- [plugins/diagnostics/plugin-boot-diagnostics.sh](../plugins/diagnostics/plugin-boot-diagnostics.sh)
- [plugins/post-install/plugin-zram.sh](../plugins/post-install/plugin-zram.sh)
- [plugins/post-install/plugin-sysctl.sh](../plugins/post-install/plugin-sysctl.sh)
- [plugins/post-install/plugin-fstrim.sh](../plugins/post-install/plugin-fstrim.sh)
- [plugins/post-install/plugin-cpupower.sh](../plugins/post-install/plugin-cpupower.sh)

### Documentation
- [plugins/README.md](../plugins/README.md) - Plugin development guide
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [PHASE3_PROGRESS.md](../PHASE3_PROGRESS.md) - Progress report

## Resources

- **Main Documentation**: [plugins/README.md](../plugins/README.md)
- **Architecture**: [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- **Progress Report**: [PHASE3_PROGRESS.md](../PHASE3_PROGRESS.md)
- **Roadmap**: [docs/Roadmap](Roadmap)

## Support

For issues or questions:
1. Check [plugins/README.md](../plugins/README.md) for detailed guide
2. Review [test/plugins.bats](../test/plugins.bats) for examples
3. Run `make lint` to check for syntax errors
4. Run `make test` to validate changes

---

*Quick Reference for Manjaro ARM Pi 5 Installer v3.0*

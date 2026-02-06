# Phase 3 Plugin Architecture

## Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│                  Manjaro Pi 5 Installer v3.0                │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
                  ┌─────────────────┐
                  │   lib/log.sh    │
                  │  Unified Logging│
                  └─────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │    lib/plugins.sh       │
              │   Plugin Loader         │
              │  - Auto-discovery       │
              │  - Dependency resolution│
              │  - Phase execution      │
              └───────────┬─────────────┘
                          │
                          ├─────► plugin_init()
                          │       └─► Discover 8 plugins
                          │
                          └─────► plugin_run_phase("phase")
                                  └─► Execute all plugins for phase
```

## Plugin Phases & Order

```
Installation Flow:
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  1. detect       ─►  [pi5-hw]                             │
│                      └─► Hardware detection               │
│                                                            │
│  2. boot         ─►  [pi5-boot]                           │
│                      └─► Boot file population             │
│                                                            │
│  3. network      ─►  [wifi]                               │
│                      └─► Wi-Fi configuration              │
│                                                            │
│  4. config       ─►  [wifi]                               │
│                      └─► Configuration persistence         │
│                                                            │
│  5. diagnostics  ─►  [boot-diagnostics]                   │
│                      └─► Boot partition verification      │
│                                                            │
│  6. post-install ─►  [zram]                               │
│                  ├─► [sysctl]                             │
│                  ├─► [fstrim]                             │
│                  └─► [cpupower]                           │
│                      └─► System optimizations             │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Plugin Directory Structure

```
plugins/
│
├── boot/                          # Boot-related plugins
│   └── plugin-pi5-boot.sh         # Multi-strategy boot file population
│       ├── Phase: boot
│       ├── Functions: plugin_run_boot()
│       └── Strategy: Download → Extract → Package fallback
│
├── network/                       # Network configuration plugins
│   └── plugin-wifi.sh             # Wi-Fi scanning and connection
│       ├── Phases: network, config
│       ├── Functions: wifi_scan(), wifi_connect(), wifi_test_internet()
│       └── Dependency: NetworkManager (nmcli)
│
├── hw/                            # Hardware detection plugins
│   └── plugin-pi5-hw.sh           # Raspberry Pi 5 detection
│       ├── Phase: detect
│       ├── Functions: hw_summary(), hw_is_pi5()
│       └── Detects: CPU, Memory, Storage (SD/NVMe/USB)
│
├── diagnostics/                   # System verification plugins
│   └── plugin-boot-diagnostics.sh # Boot partition integrity checks
│       ├── Phase: diagnostics
│       ├── Functions: diagnostics_json()
│       └── Checks: kernel, DTB, firmware, overlays, config
│
└── post-install/                  # Post-installation optimization
    ├── plugin-zram.sh             # Compressed swap in RAM
    │   ├── Phase: post-install
    │   └── Config: 50% of RAM, zstd compression
    │
    ├── plugin-sysctl.sh           # Kernel parameter tuning
    │   ├── Phase: post-install
    │   └── Optimizes: VM swappiness, cache pressure, dirty ratios
    │
    ├── plugin-fstrim.sh           # SSD TRIM scheduler
    │   ├── Phase: post-install
    │   └── Enables: Weekly TRIM timer for SSD longevity
    │
    └── plugin-cpupower.sh         # CPU frequency scaling
        ├── Phase: post-install
        └── Governor: ondemand (dynamic scaling)
```

## Plugin Metadata Schema

```bash
#!/usr/bin/env bash
#
# Plugin Template
#

# Required metadata
PLUGIN_NAME="example"              # Unique identifier
PLUGIN_VERSION="1.0"               # Semantic version
PLUGIN_DEPENDS=("other-plugin")    # Array of dependencies
PLUGIN_PHASES=("boot" "config")    # Supported phases

# Phase functions (one per phase)
plugin_run_boot() {
    log_set_phase "example-boot"
    log_info "Executing boot phase"
    # ... implementation ...
    return 0  # 0=success, 1=failure
}

plugin_run_config() {
    log_set_phase "example-config"
    log_info "Executing config phase"
    # ... implementation ...
    return 0
}

# Export helper functions
export -f helper_function
```

## Dependency Resolution

```
Dependency Graph:
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  All 8 plugins currently have no dependencies          │
│  (Independent execution)                               │
│                                                         │
│  Future example with dependencies:                     │
│                                                         │
│         [wifi]                                          │
│            │                                            │
│            └──depends on──► [network-manager]          │
│                                                         │
│         [cyberdeck-profile]                             │
│            ├──depends on──► [wifi]                     │
│            └──depends on──► [pi5-hw]                   │
│                                                         │
│  Plugin loader performs:                                │
│  1. Metadata extraction (without execution)            │
│  2. Dependency validation (all deps exist)             │
│  3. Topological sort (correct load order)              │
│  4. Cycle detection (prevent infinite loops)           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Logging System

```
Log Flow:
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  log_info("message")                                    │
│  log_warn("message")                                    │
│  log_error("message")                                   │
│  log_debug("message")                                   │
│            │                                            │
│            ├────► Console (colored)                     │
│            │      [2025-02-05 12:51:49] [INFO] ...     │
│            │                                            │
│            └────► JSON File (if LOG_JSON=1)            │
│                   /var/log/manjaro-installer/           │
│                   install_20250205_125149.json         │
│                   {                                     │
│                     "timestamp": "...",                 │
│                     "level": "INFO",                    │
│                     "phase": "boot",                    │
│                     "message": "..."                    │
│                   }                                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Testing Framework

```
Test Suite Structure:
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  test/                                                  │
│  ├── installer.bats (32 tests)                         │
│  │   ├── File existence checks                         │
│  │   ├── Bash syntax validation                        │
│  │   ├── Function existence checks                     │
│  │   ├── Documentation completeness                    │
│  │   └── Makefile target validation                    │
│  │                                                      │
│  └── plugins.bats (16 tests)                           │
│      ├── Plugin discovery                              │
│      ├── Metadata validation                           │
│      ├── Dependency handling                           │
│      ├── Phase execution                               │
│      ├── Error handling                                │
│      └── Variable isolation                            │
│                                                         │
│  Run:  make test                                        │
│  Result: 48 tests, 0 failures ✅                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Developer Workflow

```
Development Cycle:
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  1. make check-deps                                     │
│     └─► Verify shellcheck, bats, docker installed      │
│                                                         │
│  2. Create plugin in plugins/category/                  │
│     └─► Use template from plugins/README.md            │
│                                                         │
│  3. make lint                                           │
│     └─► Validate with shellcheck                       │
│                                                         │
│  4. Add tests to test/plugins.bats                      │
│     └─► Test plugin discovery, loading, execution      │
│                                                         │
│  5. make test                                           │
│     └─► Run full test suite (48+ tests)                │
│                                                         │
│  6. make dev-shell                                      │
│     └─► Test in ARM container (optional)               │
│                                                         │
│  7. Commit changes                                      │
│     └─► make pre-commit (lint + test)                  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Integration Example

```bash
# Old v2.6 approach (monolithic)
main() {
    check_root
    check_dependencies
    detect_hardware
    copy_pi5_boot_files        # 200 lines
    setup_network              # 150 lines
    apply_optimizations        # 100 lines
    verify_boot                # 100 lines
}

# New v3.0 approach (plugin-based)
main() {
    check_root
    check_dependencies
    
    # Initialize plugin system
    source lib/log.sh
    source lib/plugins.sh
    plugin_init
    
    # Execute installation phases
    plugin_run_phase "detect"       # Hardware detection
    plugin_run_phase "boot"         # Boot file setup
    plugin_run_phase "network"      # Network configuration
    plugin_run_phase "config"       # System configuration
    plugin_run_phase "post-install" # Optimizations
    plugin_run_phase "diagnostics"  # Verification
    
    log_info "Installation complete"
}

# Result: Main script reduced from 1724 → <500 lines
```

## Benefits Summary

```
┌─────────────────────────────────────────────────────────┐
│                     Benefits Achieved                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ✅ Modularity                                          │
│     • Self-contained plugins                            │
│     • Enable/disable features easily                    │
│     • Add new features without main script changes      │
│                                                         │
│  ✅ Testability                                         │
│     • 48 automated tests                                │
│     • Test individual components in isolation           │
│     • Continuous validation (make test)                 │
│                                                         │
│  ✅ Maintainability                                     │
│     • Clear separation of concerns                      │
│     • Organized by functionality                        │
│     • Comprehensive documentation                       │
│                                                         │
│  ✅ Extensibility                                       │
│     • Plugin template provided                          │
│     • Clear API for new plugins                         │
│     • Community can contribute easily                   │
│                                                         │
│  ✅ Quality                                             │
│     • Automated linting (shellcheck)                    │
│     • No syntax errors or warnings                      │
│     • Consistent code style                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

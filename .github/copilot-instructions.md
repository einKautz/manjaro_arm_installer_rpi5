# Manjaro ARM Pi 5 Installer - Copilot Instructions

## Project Overview

This is a Bash-based installer for Manjaro ARM on Raspberry Pi 5, featuring a modular plugin architecture. The project has evolved from a monolithic script to a well-organized, plugin-driven system.

**Key Stats:**
- Language: Bash (shell scripting)
- Architecture: Plugin-based modular design
- Target: Raspberry Pi 5 / ARM64 (aarch64)
- Main Script: `manjaro-pi5-installer-v3.0.sh`

## Project Structure

```
.
├── manjaro-pi5-installer-v3.0.sh  # Main installer (v3.0 - plugin-based)
├── lib/                           # Core libraries
│   ├── log.sh                     # Logging utilities
│   ├── plugins.sh                 # Plugin system loader
│   ├── profiles.sh                # Profile management
│   └── diagnostics.sh             # System diagnostics
├── plugins/                       # Modular plugins (see plugins/README.md)
│   ├── boot/                      # Boot configuration plugins
│   ├── network/                   # Network management plugins
│   ├── hw/                        # Hardware detection plugins
│   ├── diagnostics/               # Diagnostic plugins
│   ├── post-install/              # Post-installation optimizations
│   ├── config/                    # Configuration plugins
│   ├── security/                  # Security hardening plugins
│   └── workflow/                  # Workflow automation plugins
├── hal/                           # Hardware Abstraction Layer
├── profiles/                      # Edition-specific profiles
├── scripts/                       # Utility scripts
├── test/                          # Test suite (bats)
└── docs/                          # Documentation

```

## Shell Scripting Standards

### Bash Version
- **Target:** Bash 4.0+ (available on modern Linux systems)
- **Shebang:** Always use `#!/usr/bin/env bash` (not `#!/bin/sh`)
- **Bash Check:** Main scripts should verify bash is being used

### Error Handling
- **Always use:** `set -euo pipefail` at the start of scripts
  - `-e`: Exit on error
  - `-u`: Exit on undefined variable
  - `-o pipefail`: Exit on pipe failures
- **Explicit checks:** Use explicit error checking for critical operations
- **Return codes:** Functions return 0 for success, non-zero for failure

### Code Style
- **Indentation:** 4 spaces (no tabs)
- **Line length:** Prefer 80-100 characters, max 120
- **Variable naming:**
  - Global/exported: `UPPER_CASE`
  - Local variables: `lower_case`
  - Function names: `snake_case`
- **Quoting:**
  - Always quote variables: `"$variable"` (exception: when intentional word splitting)
  - Use `$()` for command substitution (not backticks)
- **Functions:**
  - Declare local variables with `local`
  - Use descriptive names
  - Add comments for non-obvious logic

### ShellCheck Compliance
- **All scripts must pass ShellCheck**
- Configuration: See `.shellcheckrc` for disabled checks
- Run: `make lint` to check all scripts
- **Acceptable to disable:** SC2086 (for intentional word splitting), SC2181 (when checking complex pipelines)
- **Document exceptions:** Add inline comments when disabling checks

## Plugin Architecture

### Plugin Structure
Plugins are self-contained, reusable components organized by functionality.

**Required Plugin Metadata:**
```bash
PLUGIN_NAME="my-plugin"           # Unique identifier (matches filename)
PLUGIN_VERSION="1.0"              # Semantic version
PLUGIN_DEPENDS=("dep1" "dep2")    # Dependencies (can be empty array)
PLUGIN_PHASES=("boot" "config")   # Supported phases
```

**Available Phases:**
- `detect` - Hardware detection and validation
- `boot` - Boot partition setup
- `network` - Network configuration
- `config` - System configuration
- `post-install` - Optimizations and final tweaks
- `diagnostics` - System verification and health checks

**Phase Function Naming:**
- Phase name → function name: `plugin_run_<phase>()`
- Example: Phase `boot` → `plugin_run_boot()`
- Use underscores for hyphens: `post-install` → `plugin_run_post_install()`

### Plugin Development Guidelines
1. **Location:** `plugins/<category>/plugin-<name>.sh`
2. **Logging:** Always source and use `lib/log.sh` functions
3. **Set Phase:** Call `log_set_phase "plugin-name-phase"` at function start
4. **Export Functions:** Export helper functions for use by other scripts
5. **Dependencies:** Declare all plugin dependencies
6. **Testing:** Add tests in `test/plugins.bats`
7. **Documentation:** Update `plugins/README.md` for new plugins

**Plugin Template:**
```bash
#!/usr/bin/env bash
#
# Plugin Description
#

PLUGIN_NAME="my-plugin"
PLUGIN_VERSION="1.0"
PLUGIN_DEPENDS=()  # Or list dependencies
PLUGIN_PHASES=("my-phase")

# Source logging
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi

plugin_run_my_phase() {
    log_info "My Plugin: Starting"
    log_set_phase "my-plugin-phase"
    
    # Plugin logic here
    
    return 0
}

# Export helpers if needed
export -f helper_function
```

## Logging System

**Available Functions:**
- `log_info "message"` - Informational messages
- `log_success "message"` - Success messages (green)
- `log_warning "message"` - Warnings (yellow)
- `log_error "message"` - Errors (red)
- `log_debug "message"` - Debug messages (only when LOG_LEVEL=DEBUG)
- `log_set_phase "phase-name"` - Set current phase for logging context

**Usage:**
- Always use logging functions instead of `echo`
- Set the phase at the start of plugin/phase functions
- Use appropriate log levels

## Testing

### Test Framework
- **Framework:** bats-core (Bash Automated Testing System)
- **Location:** `test/` directory
- **Run:** `make test`

### Test Files
- `test/plugins.bats` - Plugin system tests
- `test/lib.bats` - Library function tests
- Create new `.bats` files for new modules

### Test Guidelines
- Test each plugin individually
- Test plugin metadata (name, version, phases)
- Test exported functions exist and work
- Test error conditions and edge cases
- Use descriptive test names: `@test "plugin-name can be loaded"`

## Linting and Quality

### Commands
- `make lint` - Run ShellCheck on all scripts
- `make check-deps` - Verify required development tools

### Requirements
- All shell scripts must pass ShellCheck
- Follow the project's `.shellcheckrc` configuration
- No critical errors or warnings (info/style are advisory)

## Security Considerations

### Root Privileges
- Installer requires root (checks with `[[ $EUID -ne 0 ]]`)
- Document why root is needed
- Minimize privileged operations

### Input Validation
- Validate all user inputs
- Sanitize paths (prevent directory traversal)
- Check device paths before operations
- Verify checksums for downloads

### Sensitive Data
- Never commit passwords, API keys, or credentials
- Use environment variables for sensitive config
- Clear sensitive data from memory when done
- See `.secret-scan-ignore` for exceptions

## Hardware Abstraction Layer (HAL)

The `hal/` directory contains hardware-specific abstractions:
- `storage.sh` - Storage device operations
- `display.sh` - Display detection and configuration
- `usb.sh` - USB device handling
- `sensor.sh` - Sensor interfaces
- `overlay.sh` - Device Tree Overlay management

**When to use HAL:**
- For any hardware-specific operations
- To maintain portability across devices
- To abstract low-level hardware details

## Making Changes

### Minimal Changes Principle
- Make the smallest possible change to fix an issue
- Don't refactor unrelated code
- Don't modify working functionality unless necessary
- Preserve backward compatibility when possible

### Before Making Changes
1. Understand the plugin architecture
2. Check existing patterns in similar plugins
3. Review `plugins/README.md` for guidelines
4. Check `.shellcheckrc` for linting rules

### After Making Changes
1. Run `make lint` to ensure ShellCheck compliance
2. Run `make test` if tests exist for affected areas
3. Test manually if adding new functionality
4. Update relevant documentation (especially `plugins/README.md`)

## Common Patterns

### Sourcing Libraries
```bash
# In main scripts
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/plugins.sh"

# In plugins (with fallback)
if ! command -v log_info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
    source "${SCRIPT_DIR}/lib/log.sh"
fi
```

### Error Handling
```bash
# Check command success
if ! some_command; then
    log_error "Command failed"
    return 1
fi

# Check file exists
if [[ ! -f "$file" ]]; then
    log_error "File not found: $file"
    return 1
fi
```

### Plugin Execution
```bash
# Initialize plugin system
plugin_init

# Run a phase
plugin_run_phase "boot"

# Load specific plugin
plugin_load "pi5-boot"
```

## Documentation

### README Files
- Main: `README.md` (if exists)
- Plugins: `plugins/README.md`
- Update when adding new features/plugins

### Code Comments
- Explain **why**, not **what** (code shows what)
- Document complex logic or non-obvious decisions
- Add file headers with description and purpose
- Keep comments up-to-date with code changes

## Dependencies

### Required Tools
- `bash` (4.0+)
- `systemd-nspawn` (for chroot operations)
- `git` (for version control)

### Optional Development Tools
- `shellcheck` (linting)
- `bats-core` (testing)
- `make` (build automation)

Install dev dependencies: `make install-deps` (requires sudo)

## File Naming Conventions

- Shell scripts: `*.sh`
- Plugins: `plugin-<name>.sh` in `plugins/<category>/`
- Libraries: `<name>.sh` in `lib/`
- Tests: `*.bats` in `test/`
- HAL modules: `<device>.sh` in `hal/`
- Documentation: `*.md` or `*.txt`

## Git Workflow

- Write clear, descriptive commit messages
- Keep commits focused and atomic
- Reference issue numbers in commits when applicable
- Don't commit temporary files, logs, or build artifacts (see `.gitignore`)

## Prohibited Actions

- **Don't add new dependencies** without justification
- **Don't remove or disable tests** without understanding impact
- **Don't bypass ShellCheck** without documented reason
- **Don't hardcode paths** - use variables or detection
- **Don't use deprecated patterns** - follow established conventions
- **Don't commit secrets** - use `.secret-scan-ignore` if needed for testing

## Questions to Ask Before Coding

1. Does this follow the plugin architecture?
2. Is there an existing plugin/pattern I should use?
3. Does this pass ShellCheck with our config?
4. Are there tests I should update or create?
5. Is this the minimal change to solve the problem?
6. Does this maintain backward compatibility?
7. Have I documented new functionality?

## Resources

- Plugin Documentation: `plugins/README.md`
- ShellCheck Config: `.shellcheckrc`
- Makefile Targets: `make help`
- Test Suite: `test/` directory
- Recent Changes: Git log and `*_PROGRESS.md` files

---

**Philosophy:** This project values modularity, maintainability, and clarity. Write code that is easy to understand, test, and extend. When in doubt, follow existing patterns and ask for clarification.

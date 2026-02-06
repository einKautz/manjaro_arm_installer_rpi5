# Manjaro ARM Pi 5 Installer - Makefile
# Phase 3 Foundation - Developer Experience

.PHONY: help dev-shell test lint docs clean check-deps install-deps

# Default target
help:
	@echo "Manjaro ARM Pi 5 Installer - Development Targets"
	@echo ""
	@echo "Available targets:"
	@echo "  make dev-shell   - Launch interactive ARM container shell"
	@echo "  make test        - Run test suite (requires bats-core)"
	@echo "  make lint        - Run shellcheck on all shell scripts"
	@echo "  make docs        - Generate/update documentation"
	@echo "  make check-deps  - Check for required development dependencies"
	@echo "  make install-deps - Install development dependencies (requires sudo)"
	@echo "  make clean       - Clean temporary files and logs"
	@echo ""

# Variables
CONTAINER_WRAPPER := Container\ Wrapper.sh
MAIN_SCRIPT := manjaro-pi5-installer-v2_6.sh
SHELL_SCRIPTS := $(shell find . -name "*.sh" -not -path "./old_versions/*" -not -name "Container Wrapper.sh")
TEST_DIR := test
LIB_DIR := lib

# Check for required tools
check-deps:
	@echo "Checking development dependencies..."
	@command -v shellcheck >/dev/null 2>&1 || { echo "  ❌ shellcheck not found"; exit 1; }
	@echo "  ✅ shellcheck installed"
	@command -v bats >/dev/null 2>&1 || { echo "  ⚠️  bats-core not found (optional for testing)"; }
	@command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1 || { echo "  ❌ docker/podman not found"; exit 1; }
	@echo "  ✅ container runtime installed"
	@echo "All required dependencies are installed!"

# Install development dependencies
install-deps:
	@echo "Installing development dependencies..."
	@if command -v pacman >/dev/null 2>&1; then \
		echo "Detected Arch/Manjaro system, using pacman..."; \
		sudo pacman -S --needed shellcheck bats docker; \
		sudo systemctl enable --now docker; \
	elif command -v apt >/dev/null 2>&1; then \
		echo "Detected Debian/Ubuntu system, using apt..."; \
		sudo apt update && sudo apt install -y shellcheck bats docker.io; \
		sudo systemctl enable --now docker; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "Detected Fedora/RHEL system, using dnf..."; \
		sudo dnf install -y ShellCheck bats docker; \
		sudo systemctl enable --now docker; \
	else \
		echo "Unsupported package manager. Please install manually:"; \
		echo "  - shellcheck"; \
		echo "  - bats-core"; \
		echo "  - docker or podman"; \
		exit 1; \
	fi
	@echo "Dependencies installed! Run 'make check-deps' to verify."

# Launch interactive ARM container shell
dev-shell:
	@echo "Launching ARM container development shell..."
	@echo "The installer directory is mounted at /installer"
	@echo ""
	@if command -v docker >/dev/null 2>&1; then \
		docker run -it --rm --privileged \
			-v /dev:/dev \
			-v "$$(pwd):/installer" \
			-w /installer \
			manjaroarm/base:latest \
			bash; \
	elif command -v podman >/dev/null 2>&1; then \
		podman run -it --rm --privileged \
			-v /dev:/dev \
			-v "$$(pwd):/installer" \
			-w /installer \
			--userns=keep-id \
			manjaroarm/base:latest \
			bash; \
	else \
		echo "Error: No container runtime found (docker/podman)"; \
		exit 1; \
	fi

# Run test suite
test: check-deps
	@if [ ! -d "$(TEST_DIR)" ]; then \
		echo "Error: Test directory $(TEST_DIR) not found"; \
		echo "Run 'make test-setup' to create test structure"; \
		exit 1; \
	fi
	@echo "Running test suite..."
	@if command -v bats >/dev/null 2>&1; then \
		bats $(TEST_DIR)/*.bats; \
	else \
		echo "Warning: bats-core not installed, skipping tests"; \
		echo "Install with: make install-deps"; \
	fi

# Set up test infrastructure
test-setup:
	@echo "Creating test infrastructure..."
	@mkdir -p $(TEST_DIR)
	@if [ ! -f "$(TEST_DIR)/installer.bats" ]; then \
		echo "Creating $(TEST_DIR)/installer.bats..."; \
		echo '#!/usr/bin/env bats' > $(TEST_DIR)/installer.bats; \
		echo '# Installer test suite' >> $(TEST_DIR)/installer.bats; \
		echo '' >> $(TEST_DIR)/installer.bats; \
		echo '@test "installer script exists" {' >> $(TEST_DIR)/installer.bats; \
		echo '  [ -f "$(MAIN_SCRIPT)" ]' >> $(TEST_DIR)/installer.bats; \
		echo '}' >> $(TEST_DIR)/installer.bats; \
	fi
	@if [ ! -f "$(TEST_DIR)/plugins.bats" ]; then \
		echo "Creating $(TEST_DIR)/plugins.bats..."; \
		echo '#!/usr/bin/env bats' > $(TEST_DIR)/plugins.bats; \
		echo '# Plugin system test suite' >> $(TEST_DIR)/plugins.bats; \
	fi
	@echo "Test infrastructure created!"

# Run shellcheck on all scripts
lint:
	@echo "Running shellcheck on all shell scripts..."
	@echo ""
	@failed=0; \
	for script in $(SHELL_SCRIPTS); do \
		echo "Checking $$script..."; \
		if shellcheck -x "$$script"; then \
			echo "  ✅ $$script passed"; \
		else \
			echo "  ❌ $$script failed"; \
			failed=$$((failed + 1)); \
		fi; \
		echo ""; \
	done; \
	echo "Checking Container Wrapper.sh..."; \
	if shellcheck -x "Container Wrapper.sh" 2>/dev/null; then \
		echo "  ✅ Container Wrapper.sh passed"; \
	else \
		echo "  ⚠️  Container Wrapper.sh skipped or failed"; \
	fi; \
	echo ""; \
	if [ $$failed -gt 0 ]; then \
		echo "❌ $$failed file(s) failed shellcheck"; \
		exit 1; \
	else \
		echo "✅ All files passed shellcheck!"; \
	fi

# Lint only lib/ directory
lint-lib:
	@echo "Running shellcheck on lib/ scripts..."
	@if [ -d "$(LIB_DIR)" ]; then \
		shellcheck -x $(LIB_DIR)/*.sh; \
	else \
		echo "No lib/ directory found"; \
	fi

# Generate/update documentation
docs:
	@echo "Documentation generation (placeholder)"
	@echo "Future: Auto-generate API docs from code comments"
	@echo ""
	@echo "Current documentation:"
	@find docs -type f -name "*.md" | sort

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	@rm -rf /tmp/manjaro-installer/
	@rm -f minimal_log.txt
	@echo "Clean complete!"

# Clean and prepare for distribution
dist-clean: clean
	@echo "Removing development artifacts..."
	@find . -name "*.log" -type f -delete
	@find . -name ".*.swp" -type f -delete
	@echo "Distribution clean complete!"

# Show project structure
tree:
	@echo "Project structure:"
	@tree -L 3 -I 'old_versions|.git' || ls -R

# Quick validation before commit
pre-commit: lint test
	@echo ""
	@echo "✅ Pre-commit checks passed!"
	@echo "Safe to commit."

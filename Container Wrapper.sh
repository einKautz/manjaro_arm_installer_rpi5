#!/usr/bin/env bash
#
# Manjaro Pi 5 Installer - Container Wrapper
# Automatically runs the installer in a Manjaro ARM container to avoid GLIBC mismatches
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_SCRIPT="manjaro-pi5-installer-v2_5.sh"
CONTAINER_IMAGE="manjaroarm/base:latest"
ALTERNATIVE_IMAGE="arm64v8/archlinux:latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

msg() {
    echo -e "${GREEN}==>${NC} $*"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $*"
}

error() {
    echo -e "${RED}Error:${NC} $*" >&2
}

info() {
    echo -e "${BLUE}Info:${NC} $*"
}

check_requirements() {
    local missing=()
    
    # Check for Docker/Podman
    if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
        missing+=("docker or podman")
    fi
    
    # Check for QEMU user emulation (if on x86_64)
    if [[ "$(uname -m)" == "x86_64" ]]; then
        if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && \
           [[ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]]; then
            missing+=("qemu-user-static-binfmt")
        fi
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required packages: ${missing[*]}"
        echo ""
        echo "Install them with:"
        echo ""
        echo "  sudo pacman -S qemu-user-static-binfmt docker"
        echo "  sudo systemctl enable --now docker"
        echo ""
        echo "If using Podman instead of Docker:"
        echo "  sudo pacman -S qemu-user-static-binfmt podman"
        echo ""
        exit 1
    fi
}

check_installer_script() {
    if [[ ! -f "$SCRIPT_DIR/$INSTALLER_SCRIPT" ]]; then
        error "Installer script not found: $INSTALLER_SCRIPT"
        echo ""
        echo "Make sure you're running this from the same directory as:"
        echo "  $INSTALLER_SCRIPT"
        exit 1
    fi
}

detect_container_runtime() {
    if command -v docker &>/dev/null; then
        echo "docker"
    elif command -v podman &>/dev/null; then
        echo "podman"
    else
        error "No container runtime found"
        exit 1
    fi
}

pull_container_image() {
    local runtime="$1"
    local image="$2"
    
    msg "Checking for container image: $image"
    
    if $runtime image inspect "$image" &>/dev/null; then
        info "Image already exists locally"
        return 0
    fi
    
    msg "Pulling container image (this may take a few minutes)..."
    if ! $runtime pull "$image"; then
        warn "Failed to pull $image"
        return 1
    fi
    
    return 0
}

show_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   Manjaro ARM Pi 5 Installer - Container Wrapper v2.6            ║
║                                                                   ║
║   This wrapper runs the installer inside a Manjaro ARM           ║
║   container to avoid GLIBC/ABI incompatibility issues.           ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

run_installer_in_container() {
    local runtime="$1"
    local image="$2"
    
    msg "Starting Manjaro ARM container..."
    info "You will be dropped into the container shell"
    info "The installer script is located at: /installer/$INSTALLER_SCRIPT"
    echo ""
    
    # Build container command
    local container_cmd=(
        "$runtime" "run"
        "-it"
        "--rm"
        "--privileged"
        "-v" "/dev:/dev"
        "-v" "$SCRIPT_DIR:/installer"
    )
    
    # Add user mapping for podman
    if [[ "$runtime" == "podman" ]]; then
        container_cmd+=(
            "--userns=keep-id"
            "-v" "/run/user/$UID:/run/user/$UID"
        )
    fi
    
    container_cmd+=(
        "$image"
        "bash" "-c"
        "cd /installer && bash $INSTALLER_SCRIPT"
    )
    
    # Execute
    "${container_cmd[@]}"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo ""
        msg "Installer completed successfully!"
        info "You can now safely remove the SD card and boot your Pi 5"
    else
        echo ""
        error "Installer exited with code: $exit_code"
        warn "Check the logs at: /tmp/manjaro-installer/install.log"
    fi
    
    return $exit_code
}

show_manual_instructions() {
    cat << EOF

If you prefer to run the installer manually:

1. Start the container:

   ${container_runtime} run -it --rm --privileged \\
     -v /dev:/dev \\
     -v \$PWD:/installer \\
     $CONTAINER_IMAGE

2. Inside the container, run:

   cd /installer
   bash $INSTALLER_SCRIPT

EOF
}

main() {
    show_banner
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error "Do NOT run this wrapper script as root"
        echo ""
        echo "The wrapper will automatically request sudo when needed."
        echo "Run it as your regular user:"
        echo ""
        echo "  bash $(basename "$0")"
        exit 1
    fi
    
    msg "Checking requirements..."
    check_requirements
    
    msg "Checking for installer script..."
    check_installer_script
    
    msg "Detecting container runtime..."
    container_runtime=$(detect_container_runtime)
    info "Using: $container_runtime"
    
    # Try to pull primary image, fall back to alternative
    if ! pull_container_image "$container_runtime" "$CONTAINER_IMAGE"; then
        warn "Trying alternative image: $ALTERNATIVE_IMAGE"
        if ! pull_container_image "$container_runtime" "$ALTERNATIVE_IMAGE"; then
            error "Failed to pull any compatible ARM container image"
            exit 1
        fi
        CONTAINER_IMAGE="$ALTERNATIVE_IMAGE"
    fi
    
    echo ""
    info "About to run installer in container"
    info "Container runtime: $container_runtime"
    info "Container image: $CONTAINER_IMAGE"
    echo ""
    
    read -p "Press Enter to continue or Ctrl+C to cancel..."
    
    run_installer_in_container "$container_runtime" "$CONTAINER_IMAGE"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
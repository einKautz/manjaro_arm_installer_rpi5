#!/bin/bash
# Plugin: Offline Repositories
# Phase: cyberpentester-workflow

# shellcheck disable=SC2034
PLUGIN_NAME="Offline Repositories"
PLUGIN_DESCRIPTION="Configures offline repository mirroring for field operations"
PLUGIN_PHASE="cyberpentester-workflow"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Configuring offline repository support..."
    
    # Create mirror directory structure
    mkdir -p "$ROOT_MOUNT/mnt/storage/repos"
    mkdir -p "$ROOT_MOUNT/etc/pacman.d/repos"
    
    # Create offline repository sync script
    cat > "$ROOT_MOUNT/usr/local/bin/sync-offline-repos.sh" <<'EOF'
#!/bin/bash
# Sync package repositories for offline use

MIRROR_PATH="/mnt/storage/repos"
REPOS=("core" "extra" "community")

echo "Syncing repositories for offline use..."
echo "Target: $MIRROR_PATH"
echo "This will download ~50-100GB of packages"
echo ""

read -r -p "Continue? [y/N] " response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Aborted."
    exit 0
fi

# Install repository mirroring tools
if ! command -v wget &>/dev/null; then
    sudo pacman -S --noconfirm wget
fi

# Create mirror directories
for repo in "${REPOS[@]}"; do
    mkdir -p "$MIRROR_PATH/$repo/os/aarch64"
done

# Sync using rsync from official mirrors
for repo in "${REPOS[@]}"; do
    echo "Syncing $repo repository..."
    rsync -avz --delete \
        rsync://mirror.archlinuxarm.org/aarch64/$repo/ \
        "$MIRROR_PATH/$repo/os/aarch64/"
done

echo ""
echo "Repository sync complete!"
echo "To use offline repos, run: enable-offline-repos.sh"
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/sync-offline-repos.sh"
    
    # Create offline repo enabler
    cat > "$ROOT_MOUNT/usr/local/bin/enable-offline-repos.sh" <<'EOF'
#!/bin/bash
# Enable offline repository mode

MIRROR_PATH="/mnt/storage/repos"

if [[ ! -d "$MIRROR_PATH/core" ]]; then
    echo "Error: Offline repositories not found at $MIRROR_PATH"
    echo "Run sync-offline-repos.sh first"
    exit 1
fi

# Backup original mirrorlist
if [[ ! -f /etc/pacman.d/mirrorlist.online ]]; then
    sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.online
fi

# Create offline mirrorlist
sudo tee /etc/pacman.d/mirrorlist > /dev/null <<MIRRORLIST
# Offline repository mirror
Server = file://$MIRROR_PATH/\$repo/os/\$arch
MIRRORLIST

echo "Offline repositories enabled"
echo "Test with: sudo pacman -Sy"
echo "To restore online repos: disable-offline-repos.sh"
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/enable-offline-repos.sh"
    
    # Create offline repo disabler
    cat > "$ROOT_MOUNT/usr/local/bin/disable-offline-repos.sh" <<'EOF'
#!/bin/bash
# Disable offline repository mode

if [[ -f /etc/pacman.d/mirrorlist.online ]]; then
    sudo cp /etc/pacman.d/mirrorlist.online /etc/pacman.d/mirrorlist
    echo "Online repositories restored"
else
    echo "No backup mirrorlist found"
    exit 1
fi
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/disable-offline-repos.sh"
    
    log_info "Offline repository configuration complete"
    log_info "Sync repos with: sync-offline-repos.sh (requires ~50-100GB space)"
    log_info "Enable offline mode: enable-offline-repos.sh"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

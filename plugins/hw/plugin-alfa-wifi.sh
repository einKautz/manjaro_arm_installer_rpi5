#!/bin/bash
# Plugin: Alfa AWUS036ACH WiFi Adapter
# Phase: cyberpentester-hardware

# shellcheck disable=SC2034
PLUGIN_NAME="Alfa AWUS036ACH"
PLUGIN_DESCRIPTION="Configures Alfa AWUS036ACH (RTL8812AU) for monitor mode and packet injection"
PLUGIN_PHASE="cyberpentester-hardware"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    # Always return success - optional hardware
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Configuring Alfa AWUS036ACH WiFi adapter..."
    
    # Install wireless tools and drivers
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm aircrack-ng wireless_tools iw linux-rpi-headers; then
        log_error "Failed to install wireless packages"
        return 1
    fi
    
    # Install DKMS for driver management
    systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm dkms || true
    
    # Clone and build RTL8812AU driver (aircrack-ng version with monitor mode)
    log_info "Building RTL8812AU driver for monitor mode support..."
    
    # Create build script that will run on first boot
    cat > "$ROOT_MOUNT/usr/local/bin/build-rtl8812au-driver.sh" <<'EOF'
#!/bin/bash
# Build RTL8812AU driver on first boot

set -e

DRIVER_DIR="/usr/src/rtl8812au-aircrack-ng"

if [[ -d "$DRIVER_DIR" ]]; then
    echo "RTL8812AU driver already built"
    exit 0
fi

# Clone driver source
cd /usr/src
git clone https://github.com/aircrack-ng/rtl8812au.git rtl8812au-aircrack-ng
cd rtl8812au-aircrack-ng

# Build and install
make
make install

# Load module
modprobe 88XXau

echo "RTL8812AU driver built and loaded successfully"
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/build-rtl8812au-driver.sh"
    
    # Create systemd service to build driver on first boot
    cat > "$ROOT_MOUNT/etc/systemd/system/build-wifi-driver.service" <<'EOF'
[Unit]
Description=Build RTL8812AU WiFi Driver
After=network-online.target
ConditionPathExists=!/usr/src/rtl8812au-aircrack-ng

[Service]
Type=oneshot
ExecStart=/usr/local/bin/build-rtl8812au-driver.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable service
    systemd-nspawn -D "$ROOT_MOUNT" systemctl enable build-wifi-driver.service
    
    # Configure NetworkManager to ignore monitor mode interfaces
    mkdir -p "$ROOT_MOUNT/etc/NetworkManager/conf.d"
    cat > "$ROOT_MOUNT/etc/NetworkManager/conf.d/unmanaged-devices.conf" <<'EOF'
# Don't manage monitor mode interfaces
[keyfile]
unmanaged-devices=interface-name:wlan*mon;interface-name:mon*
EOF
    
    # Create monitor mode helper script (will be replaced by wifi-mode.sh)
    cat > "$ROOT_MOUNT/usr/local/share/wifi-adapter-notes.txt" <<'EOF'
Alfa AWUS036ACH Configuration Notes
====================================

Driver: RTL8812AU (aircrack-ng version)
Chipset: Realtek RTL8812AU
Bands: 2.4GHz / 5GHz
Monitor Mode: Supported
Packet Injection: Supported

Enable Monitor Mode:
  sudo ip link set wlan1 down
  sudo iw dev wlan1 set type monitor
  sudo ip link set wlan1 up

Or use the helper script:
  /usr/local/bin/wifi-mode.sh monitor wlan1

Scan networks:
  sudo airodump-ng wlan1

Test packet injection:
  sudo aireplay-ng --test wlan1

Note: Adapter may appear as wlan1 (wlan0 is usually built-in)
EOF
    
    log_info "Alfa AWUS036ACH configuration complete"
    log_info "Driver will be built automatically on first boot"
    log_info "Use /usr/local/bin/wifi-mode.sh to switch between managed and monitor mode"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

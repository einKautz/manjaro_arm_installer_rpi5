#!/bin/bash
# Plugin: RTL-SDR V4 Configuration
# Phase: cyberpentester-hardware

# shellcheck disable=SC2034
PLUGIN_NAME="RTL-SDR V4"
PLUGIN_DESCRIPTION="Configures RTL-SDR V4 for RF spectrum analysis"
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
    
    log_info "Configuring RTL-SDR V4 support..."
    
    # Install RTL-SDR packages
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm rtl-sdr gnuradio gqrx; then
        log_error "Failed to install RTL-SDR packages"
        return 1
    fi
    
    # Blacklist DVB-T driver to prevent interference
    cat > "$ROOT_MOUNT/etc/modprobe.d/rtl-sdr-blacklist.conf" <<'EOF'
# Blacklist DVB-T drivers that interfere with RTL-SDR
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF
    
    # Create udev rules for RTL-SDR
    cat > "$ROOT_MOUNT/etc/udev/rules.d/99-rtl-sdr.rules" <<'EOF'
# RTL-SDR devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666", GROUP="plugdev"

# HackRF One
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="604b", MODE="0666", GROUP="plugdev"

# Airspy
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="60a1", MODE="0666", GROUP="plugdev"
EOF
    
    # Create RTL-SDR configuration
    mkdir -p "$ROOT_MOUNT/etc/rtl-sdr"
    cat > "$ROOT_MOUNT/etc/rtl-sdr/rtl-sdr.conf" <<'EOF'
# RTL-SDR Configuration
# Sample rate: 2.4 MSPS (default)
# Frequency correction: 0 ppm (adjust if needed)
# Bias-T: disabled (RTL-SDR V4 supports bias-T via software)

# Enable bias-T for active antennas:
# rtl_biast -b 1
EOF
    
    # Install additional SDR tools
    systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm dump1090 multimon-ng kalibrate-rtl || true
    
    log_info "RTL-SDR V4 configuration complete"
    log_info "Test RTL-SDR: rtl_test -t"
    log_info "Scan spectrum: Use gqrx or /usr/local/bin/sdr-scan.py"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi

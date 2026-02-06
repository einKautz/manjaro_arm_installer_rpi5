#!/bin/bash
# WiFi Adapter Mode Switcher - Switch between managed and monitor mode

set -e

ADAPTER="${2:-wlan1}"
MODE="$1"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <managed|monitor> [adapter]"
    echo "Example: $0 monitor wlan1"
    exit 1
fi

case "$MODE" in
    monitor)
        echo "Switching $ADAPTER to monitor mode..."
        sudo ip link set "$ADAPTER" down
        sudo iw dev "$ADAPTER" set type monitor
        sudo ip link set "$ADAPTER" up
        echo "Monitor mode enabled on $ADAPTER"
        ;;
    managed)
        echo "Switching $ADAPTER to managed mode..."
        sudo ip link set "$ADAPTER" down
        sudo iw dev "$ADAPTER" set type managed
        sudo ip link set "$ADAPTER" up
        sudo systemctl restart NetworkManager
        echo "Managed mode enabled on $ADAPTER"
        ;;
    *)
        echo "Error: Invalid mode '$MODE'"
        echo "Use: monitor or managed"
        exit 1
        ;;
esac

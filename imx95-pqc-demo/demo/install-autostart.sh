#!/usr/bin/env bash
# Install and enable the boot-time demo units. Run ON THE BOARD as root.
#
#   sudo bash install-autostart.sh            # serial console (default)
#   sudo bash install-autostart.sh --display  # two-pane renderer on tty1
#   sudo bash install-autostart.sh --off      # disable, restore the getty
#
# The serial-console demo is the default because it needs nothing but the
# console cable; the two-pane renderer additionally needs a DisplayPort screen.
set -euo pipefail
UART_UNIT=/etc/systemd/system/wolfssl-demo-uart.service
DISPLAY_UNIT=/etc/systemd/system/wolfssl-demo.service
M7_UNIT=/etc/systemd/system/wolfssl-m7.service
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--off" ]; then
    systemctl disable --now wolfssl-demo-uart.service 2>/dev/null || true
    systemctl disable --now wolfssl-demo.service 2>/dev/null || true
    systemctl disable --now wolfssl-m7.service 2>/dev/null || true
    systemctl start getty@tty1.service 2>/dev/null || true
    sync
    echo "demo autostart disabled, getty on tty1 restored"
    exit 0
fi

install -m 0644 "$HERE/wolfssl-m7.service" "$M7_UNIT"
if [ "${1:-}" = "--display" ]; then
    install -m 0644 "$HERE/wolfssl-demo.service" "$DISPLAY_UNIT"
    UNIT="$DISPLAY_UNIT"
    systemctl disable wolfssl-demo-uart.service 2>/dev/null || true
else
    install -m 0644 "$HERE/wolfssl-demo-uart.service" "$UART_UNIT"
    UNIT="$UART_UNIT"
    systemctl disable wolfssl-demo.service 2>/dev/null || true
fi
systemctl daemon-reload
systemctl enable "$(basename "$UNIT")" wolfssl-m7.service
# The demo's replay beat is a hard power cut, so nothing may sit in the page
# cache: an unsynced unit file is simply gone after the next cycle.
sync
echo "installed and enabled: $UNIT and $M7_UNIT"
echo "the demo now starts on boot; power cycle is the whole replay"
echo "disable with: sudo bash $HERE/install-autostart.sh --off"

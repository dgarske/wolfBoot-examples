#!/usr/bin/env bash
# Install and enable the boot-time demo unit. Run ON THE BOARD as root.
#
#   sudo bash install-autostart.sh          # install + enable
#   sudo bash install-autostart.sh --off    # disable, restore the getty
set -euo pipefail
UNIT=/etc/systemd/system/wolfssl-demo.service
M7_UNIT=/etc/systemd/system/wolfssl-m7.service
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--off" ]; then
    systemctl disable --now wolfssl-demo.service 2>/dev/null || true
    systemctl disable --now wolfssl-m7.service 2>/dev/null || true
    systemctl start getty@tty1.service 2>/dev/null || true
    sync
    echo "demo autostart disabled, getty on tty1 restored"
    exit 0
fi

install -m 0644 "$HERE/wolfssl-demo.service" "$UNIT"
install -m 0644 "$HERE/wolfssl-m7.service" "$M7_UNIT"
systemctl daemon-reload
systemctl enable wolfssl-demo.service wolfssl-m7.service
# The demo's replay beat is a hard power cut, so nothing may sit in the page
# cache: an unsynced unit file is simply gone after the next cycle.
sync
echo "installed and enabled: $UNIT and $M7_UNIT"
echo "the demo now starts on boot; power cycle is the whole replay"
echo "disable with: sudo bash $HERE/install-autostart.sh --off"

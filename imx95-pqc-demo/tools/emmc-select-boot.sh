#!/usr/bin/env bash
# Choose which eMMC boot partition the i.MX95 boot ROM loads its AHAB container
# set from. This is the only step that changes how the board boots.
#
#   BOARD=user@host emmc-select-boot.sh 0    # boot0  (PARTITION_CONFIG 0x48)
#   BOARD=user@host emmc-select-boot.sh 1    # boot1  (PARTITION_CONFIG 0x50)
#
# Keep a known-good image in the partition you are not using: it is the way
# back if the other one fails to boot. The setting is stored in EXT_CSD and
# survives power loss, so power-cycle to apply it.
#
# mmc-utils numbers the boot partitions from 1, so boot0 is "1" and boot1 "2"
# in the underlying command.
set -euo pipefail

BOARD="${BOARD:?set BOARD=user@host}"
PART="${1:?usage: BOARD=user@host $0 <0|1>}"
case "$PART" in
    0) N=1; LABEL="boot0" ;;
    1) N=2; LABEL="boot1" ;;
    *) echo "partition must be 0 or 1" >&2; exit 1 ;;
esac

echo "selecting $LABEL"
echo "-- before --"
ssh "$BOARD" "sudo mmc extcsd read /dev/mmcblk0 2>/dev/null | grep -iA2 'PARTITION_CONFIG'" || true
ssh "$BOARD" "sudo mmc bootpart enable $N 1 /dev/mmcblk0"
echo "-- after --"
ssh "$BOARD" "sudo mmc extcsd read /dev/mmcblk0 2>/dev/null | grep -iA2 'PARTITION_CONFIG'" || true
echo
echo "Power-cycle the board to boot from $LABEL."

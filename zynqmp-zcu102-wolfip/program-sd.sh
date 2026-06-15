#!/usr/bin/env bash
#
# Program an SD card for the ZCU102 wolfBoot + wolfIP demo.
#
# Expects an MBR card laid out like zynqmp_sdcard.config (a stock PetaLinux
# ZCU102 SD card works):
#   p1  boot   FAT32, bootable   <- BOOT.BIN      (FSBL+PMUFW+BL31+wolfBoot)
#   p2  OFP_A  raw               <- signed app    (wolfBoot's primary image)
#   p3  OFP_B  raw               (update slot - written over the network at run time)
#   p4  rootfs                   (unused by this bare-metal demo)
#
# wolfBoot reads the *raw* OFP_A partition (WOLFBOOT_NO_PARTITIONS, BOOT_PART_A=1),
# so the signed image is dd'd to the start of p2 (this needs root). Copying
# BOOT.BIN into the FAT p1 does not.
#
# Usage:  SD=/dev/sdX ./program-sd.sh        (X = your card reader, NOT a board)
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/out"
VERSION="${VERSION:-1}"
SIGNED="$OUT/wolfip_app_v${VERSION}_signed.bin"
SD="${SD:?set SD=/dev/sdX (your SD card reader block device - double-check with lsblk!)}"

[ -f "$OUT/BOOT.BIN" ] || { echo "missing $OUT/BOOT.BIN - run ./build.sh first" >&2; exit 1; }
[ -f "$SIGNED" ]       || { echo "missing $SIGNED - run ./build.sh first" >&2; exit 1; }
[ -b "$SD" ]           || { echo "$SD is not a block device" >&2; exit 1; }

echo "Target $SD:"; lsblk -o NAME,SIZE,TYPE,LABEL,FSTYPE "$SD"
read -r -p "Write BOOT.BIN to ${SD}1 (FAT) and the signed app to ${SD}2 (raw)? [y/N] " a
[ "$a" = y ] || { echo "aborted"; exit 1; }

echo "== BOOT.BIN -> ${SD}1 (FAT boot partition) =="
MNT="$(mktemp -d)"
sudo mount "${SD}1" "$MNT"
sudo cp "$OUT/BOOT.BIN" "$MNT/BOOT.BIN"
sync; sudo umount "$MNT"; rmdir "$MNT"

echo "== signed app -> ${SD}2 (OFP_A, raw) =="
sudo dd if="$SIGNED" of="${SD}2" bs=1M conv=fsync status=progress

sync
echo "Done. Put the card in the ZCU102, set SW6=SD, and power on."

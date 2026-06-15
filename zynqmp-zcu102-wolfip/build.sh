#!/usr/bin/env bash
#
# Build the ZCU102 wolfBoot + wolfIP secure-boot demo end to end:
#   FSBL -> PMUFW -> BL31 (EL3) -> wolfBoot (EL2) -> signed wolfIP app (EL2).
#
# Produces out/BOOT.BIN (the bootloader chain) and out/wolfip_app_v<N>_signed.bin
# (the signed application image wolfBoot verifies + loads).
#
# Paths default to ~/GitHub/... ; override any with an env var. Needs the
# aarch64-none-elf toolchain and bootgen (Vitis) on PATH.
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WOLFBOOT="${WOLFBOOT:-$HOME/GitHub/wolfboot-alt3}"
WOLFIP="${WOLFIP:-$HOME/GitHub/wolfip-alt}"
FW="${FW:-$HOME/GitHub/soc-prebuilt-firmware/zcu102-zynqmp}"   # zynqmp_fsbl.elf, pmufw.elf, bl31.elf
CROSS="${CROSS_COMPILE:-aarch64-none-elf-}"
VERSION="${VERSION:-1}"
MAC5="${MAC5:-0x33}"
OUT="$HERE/out"
APPDIR="$WOLFIP/src/port/amd/boards/zcu102"
mkdir -p "$OUT"

echo "== 1/3  wolfBoot (ZynqMP SD, RSA4096/SHA3) =="
cp "$WOLFBOOT/config/examples/zynqmp_sdcard.config" "$WOLFBOOT/.config"
# Build inside $WOLFBOOT (its Makefile resolves the sign tool via $(PWD)).
# Reuse the existing signing key so a VERSION=2 update verifies against the
# same wolfBoot. The first build generates it; if a stale key with a
# different algorithm is present, run 'make keysclean' in wolfBoot once.
( cd "$WOLFBOOT" && make keytools >/dev/null \
    && make clean >/dev/null 2>&1 || true )
( cd "$WOLFBOOT" && make CROSS_COMPILE="$CROSS" wolfboot.elf )
cp "$WOLFBOOT/wolfboot.elf" "$OUT/"

echo "== 2/3  wolfIP app (EL2, DDR, OTA) + sign =="
# OTA=1 compiles wolfBoot's own SD/disk drivers ($WOLFBOOT/src/{sdhci,disk,gpt}.c)
# straight into the app so the running image can fetch a signed update over
# TFTP and stage it to OFP_B itself - no runtime hand-off from wolfBoot.
make -C "$APPDIR" clean >/dev/null 2>&1 || true
make -C "$APPDIR" CROSS_COMPILE="$CROSS" EL=2 LAYOUT=ddr OTA=1 WOLFBOOT="$WOLFBOOT" \
    CFLAGS_EXTRA="-DWOLFIP_MAC_5=$MAC5"
"${CROSS}objcopy" -O binary "$APPDIR/app.elf" "$OUT/wolfip_app.bin"
"$WOLFBOOT/tools/keytools/sign" --rsa4096 --sha3 \
    "$OUT/wolfip_app.bin" "$WOLFBOOT/wolfboot_signing_private_key.der" "$VERSION"

echo "== 3/3  BOOT.BIN (FSBL+PMUFW+BL31+wolfBoot) =="
sed -e "s|@FW@|$FW|g" -e "s|@WOLFBOOT@|$OUT|g" "$HERE/boot.bif.in" > "$OUT/boot.bif"
bootgen -arch zynqmp -image "$OUT/boot.bif" -w on -o "$OUT/BOOT.BIN"

echo
echo "Done. Artifacts in $OUT:"
ls -la "$OUT"/BOOT.BIN "$OUT"/wolfip_app_v${VERSION}_signed.bin
echo "Next: ./program-sd.sh  (then boot ZCU102 from SD, SW6=SD)"

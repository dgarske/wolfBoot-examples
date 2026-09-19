# Building the i.MX95 post-quantum boot demo

This builds a Toradex SMARC i.MX95 that boots with **wolfBoot in place of U-Boot SPL**, verifies Linux with ML-DSA-87 on the Cortex-A55, and runs a second wolfBoot on the Cortex-M7 that verifies a Zephyr image the same way.

Everything here is a direct command. Where a script is used it lives in a public repository and is named by its path in that repository.

## What you need

**Hardware.** A Toradex SMARC iMX95 module on its carrier, a USB serial cable on SMARC SER1, a microSD card, and a way to power-cycle the board. A USB-C cable to the recovery port is worth having before you start - see *Recovery* at the end.

**Repositories.**

```
git clone https://github.com/wolfSSL/wolfBoot
git clone https://github.com/wolfSSL/wolfBoot-examples
git clone https://github.com/nxp-imx/imx-mkimage
```

**Toolchains.** `aarch64-none-elf-` (or `aarch64-linux-gnu-`) for the A55, `arm-none-eabi-` for the M7. On Debian or Ubuntu: `apt install gcc-aarch64-linux-gnu gcc-arm-none-eabi`.

**From the running board, once.** You need the SoC's own boot images - the EdgeLock Enclave (ELE) firmware, the M33 System Manager, and the Optional Executable Image (OEI) that trains DDR. They are not redistributable and not rebuilt here; take them from the module as shipped:

```
ssh <board> "sudo dd if=/dev/mmcblk0boot0 bs=1M count=32" > boot0.bin
```

`boot0.bin` is your base image and your fallback. Keep it.

ARM Trusted Firmware (BL31) and OP-TEE are in there too, so you do not need to build or source them separately. Pull everything out of that one file:

```
python3 ../tools/ahab-extract.py boot0.bin -o vendor/
```

```
container 0 at 0x8000, 5 image(s)
  [1] 0x1FFC0000    321536 bytes  Cortex-M33 image (System Manager or OEI)
  [2] 0x1FFC0000    129024 bytes  Cortex-M33 image (System Manager or OEI)
  [3] 0x20480000    141312 bytes  A55 image in OCRAM (U-Boot SPL, or wolfBoot stage 1)
container 1 at 0xcf800, 3 image(s)
  [0] 0x8A200000     38912 bytes  ARM Trusted Firmware BL31 (secure monitor, EL3)
  [1] 0x90200000    968704 bytes  BL33 (U-Boot proper, or wolfBoot)
  [2] 0x8C000000    593920 bytes  OP-TEE (trusted OS, secure EL1)
```

That gives you `vendor/bl31.bin` and `vendor/tee.bin`, which is all you need from the vendor side. Images are named by load address, because those are fixed on this SoC. The two M33 images share a load address - the OEI runs and returns before the System Manager is loaded over it - so the second is written with an index suffix.

## 1. Build mkimage

```
cd imx-mkimage
make bin
export MKIMAGE=$PWD/mkimage_imx8
```

## 2. Build wolfBoot for the A55

wolfBoot runs twice on the A55: as **BL33**, where ARM Trusted Firmware hands it control and it verifies and boots Linux; and as **stage 1**, in the slot U-Boot SPL normally occupies.

```
cd wolfBoot
cp config/examples/imx95-a55.config .config
make                                      # BL33 -> wolfboot.bin
make -C stage1 DISK_EMMC=1 DISK_SDCARD=0 loader_stage1.bin
```

The first build also generates a signing key (`wolfboot_signing_private_key.der`) and compiles the matching public key into wolfBoot's keystore. **Copy that key somewhere outside the tree.** `make keysclean` regenerates it, and a keystore that no longer matches your signed images means the board stops booting with an authenticity error.

```
cp wolfboot_signing_private_key.der ~/keys/imx95-demo-signing-key.der
```

To reuse an existing key instead of generating one, import its public half before building. Note the level must be given in the environment - both key tools default to ML-DSA level 2 and will silently truncate a level 5 key:

```
python3 -c "d=open('/path/to/key.der','rb').read(); open('pub.der','wb').write(d[-2592:])"
ML_DSA_LEVEL=5 ./tools/keytools/keygen --ml_dsa -i pub.der --der
```

## 3. Sign the Linux FIT

The payload is a FIT image holding the kernel, device tree and initramfs. Build it however your distribution does - for Torizon it comes out of the BSP - then sign it with the same key wolfBoot was built with:

```
ML_DSA_LEVEL=5 IMAGE_HEADER_SIZE=12288 \
  wolfBoot/tools/keytools/sign --ml_dsa --sha256 \
      fitImage wolfBoot/wolfboot_signing_private_key.der 1
```

This writes `fitImage_v1_signed.bin`: the image with a 12288-byte wolfBoot header prepended. The `1` is the version; wolfBoot refuses to roll back to a lower one.

## 4. Assemble the boot image

The i.MX95 boot ROM reads a set of **AHAB** (Advanced High Assurance Boot) containers from the boot medium. There are two:

- **Container 0** at offset `0x8000` - ELE firmware, System Manager, OEI, and one A55 image loaded into OCRAM at `0x20480000`. That last slot is U-Boot SPL on a stock module, and is what wolfBoot takes over.
- **Container 1**, immediately after - BL31, BL33 and OP-TEE.

Nothing records where container 1 starts. It is the end of container 0 - the furthest of its header, its images and its signature block - rounded up to 1 KiB. On this module that lands at `0xcf800`.

Build container 1 with wolfBoot as BL33, splicing it into a copy of `boot0.bin`:

```
MKIMAGE=$MKIMAGE ../tools/ahab-pack-container2.sh \
    boot0.bin vendor/bl31.bin wolfBoot/wolfboot.bin vendor/tee.bin boot-wolfboot.bin
```

Then replace the SPL slot in container 0 with the stage 1:

```
python3 ../tools/ahab-replace-spl.py \
    boot-wolfboot.bin wolfBoot/stage1/loader_stage1.bin boot-final.bin
```

Each image entry carries a **SHA-384** over its payload, so that script recomputes the hash for the slot it replaces; the ROM rejects the container otherwise. It leaves container 0's other images and all of container 1 untouched, and because the SPL slot is followed by a zero-length end marker at a fixed offset, the container's size does not change and container 1 does not move.

Both containers this produces are byte-identical to the ones running on our demo board, which is the check that the path above is complete: everything came from that single `dd`, plus wolfBoot.

## 5. Write the SD card

wolfBoot BL33 reads the signed FIT from the carrier SD. Partition it once - three primary partitions, the first two being wolfBoot's A and B slots:

```
sudo sfdisk /dev/sdX <<'EOF'
label: dos
start=131072, size=131072, type=83
start=262144, size=262144, type=83
start=524288, size=262144, type=83
EOF
sudo dd if=fitImage_v1_signed.bin of=/dev/sdX2 bs=1M conv=fsync
```

wolfBoot numbers partitions from zero, so its "partition A" is the second MBR entry, `/dev/sdX2`.

## 6. Flash the board

The eMMC has two boot partitions and EXT_CSD selects which one the ROM reads. Write the one you are **not** currently booting from, so the other stays as a way back:

```
export BOARD=torizon@<board-ip>
../tools/emmc-write-boot.sh boot-final.bin 1
../tools/emmc-select-boot.sh 1
```

Power-cycle. Both scripts verify by reading back and neither embeds a password; use an ssh key and sudo on the target.

## 7. Build the Cortex-M7 side

```
cd wolfBoot
cp config/examples/imx95-m7.config .config
make
```

The M7 image is loaded by Linux `remoteproc` rather than by the ROM, so it is not part of the AHAB container set. Staging and start-up are covered by `../demo/m7-start.sh`, and the Zephyr application it verifies is built from `../m7/zephyr-app/`.

Two things bite when reloading M7 firmware. The core cannot be stopped once wolfBoot's `main()` is spinning - the kernel logs `Not in wfi` and `can't stop rproc: -4` - so a reload silently leaves the previous firmware running; power-cycle instead. And after copying firmware to the board, run `sync` before cutting power, or the write sits in page cache and the board comes up on the old image with a filename and size that look right.

## 8. Install the demo

```
scp -r ../demo <board>:~/demo
ssh <board> "~/demo/install-autostart.sh"
```

That installs systemd units which start the M7 and stream both cores' output to the console on every boot.

## Recovery

`boot0` is never written by any of the above, so it is always the way back. If an image in `boot1` fails to start, hold the recovery button (**B4**) and power the board on, with a USB-C cable from the recovery port to your host. The boot ROM's serial downloader takes over - it lives in ROM and needs nothing on the eMMC, so replacing SPL does not put recovery at risk. Then, from Toradex's Easy Installer package:

```
cd <tezi-package>/recovery
./uuu uuu-partconf.auto
```

That boots a recovery U-Boot entirely in RAM and sets the boot partition back to `boot0` without writing storage. Release the button and power-cycle.

The carrier's BOOT_SEL jumper does **not** need changing, and should be left alone: on this module SD boot is enabled by SoC fuses rather than by the strap, so BOOT_SEL cannot select it.

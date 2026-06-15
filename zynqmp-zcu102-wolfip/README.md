# wolfBoot + wolfIP on AMD/Xilinx ZynqMP (ZCU102)

Secure boot of a bare-metal **wolfIP** TCP/IP application with **wolfBoot** on the ZCU102, booting from SD card. wolfBoot verifies the application's signature before every boot and supports a signed firmware update that the running wolfIP app fetches over the network.

## Boot chain

```
BootROM -> FSBL -> PMUFW -> BL31 (ATF, EL3) -> wolfBoot (EL2) -> wolfIP app (EL2)
                                                   |
                                                   +-- verify RSA-4096 / SHA3 signature, then load
```

`BOOT.BIN` (on the FAT boot partition) carries FSBL + PMUFW + BL31 + wolfBoot. The wolfIP application is a **separate signed image** on the `OFP_A` SD partition; wolfBoot authenticates it and loads it to DDR `0x10000000` (matching the app's `LAYOUT=ddr` link address), then hands off at EL2.

The application is the wolfIP ZCU102 port from the `wolfip` repo, built `EL=2` (wolfBoot chain-loads at EL2) and `LAYOUT=ddr`. It runs DHCP + a UDP echo demo; see `../../../wolfip/src/port/amd/`.

## Build

```
./build.sh
```

This builds wolfBoot for the ZynqMP SD config (`zynqmp_sdcard.config`, RSA-4096 / SHA3, generating a fresh signing key), builds and signs the `EL=2 LAYOUT=ddr` wolfIP app, and assembles `out/BOOT.BIN`. Prerequisites: the `aarch64-none-elf` toolchain and `bootgen` (Vitis) on `PATH`, and a prebuilt FSBL/PMUFW/BL31 set (`FW=` env, default `~/GitHub/soc-prebuilt-firmware/zcu102-zynqmp`).

## Program the SD card

A stock PetaLinux ZCU102 SD card (MBR: boot / OFP_A / OFP_B / rootfs) works as-is.

```
SD=/dev/sdX ./program-sd.sh
```

Writes `BOOT.BIN` into the FAT boot partition and `dd`s the signed app to the raw `OFP_A` partition (needs root). Then put the card in the ZCU102, set boot-mode `SW6 = SD`, and power on.

## Run

On the serial console (PS-UART0, 115200 8N1) you should see FSBL -> wolfBoot (which prints the signature-verification result) -> the wolfIP banner, DHCP bind, and `Ready`. A modified or unsigned `OFP_A` image fails wolfBoot's check and is not booted.

## Signed firmware update (over the network)

The running wolfIP app fetches a newer signed image over **TFTP**, writes it to the `OFP_B` SD partition, and resets. Because the wolfBoot config is version-selecting (`WOLFBOOT_NO_PARTITIONS=1`, "boot the higher version"), no update flag is needed: wolfBoot verifies both `OFP_A` (v1) and `OFP_B` (v2) on the next boot, picks the higher version, and rolls back to `OFP_A` if `OFP_B` ever fails to verify.

The novel part is that the app re-uses **wolfBoot's own SD-host and disk drivers** (`$WOLFBOOT/src/sdhci.c`, `disk.c`, `gpt.c`) by compiling that same source straight into the application (the `OTA=1` path in the app `Makefile`), backed by a small platform shim (`boards/zcu102/sdhci_shim.c`) that supplies MMIO access, the timer, and SDMA cache maintenance from EL2. There is no runtime hand-off from wolfBoot - the app drives the SD controller itself.

Steps:

1. Build the higher-version update image:

   ```
   VERSION=2 ./build.sh
   ```

   This produces `out/wolfip_app_v2_signed.bin` (the same app, signed at version 2).

2. Serve it as `wolfip_update.bin` from a TFTP server on the same subnet as the board, e.g. with dnsmasq:

   ```
   sudo dnsmasq --no-daemon --enable-tftp --tftp-root=$PWD/out \
       --tftp-no-blocksize -i <iface>
   cp out/wolfip_app_v2_signed.bin out/wolfip_update.bin
   ```

3. Trigger the update from any host - send a UDP datagram beginning `UPDATE` to the app's echo port (7); the app fetches `wolfip_update.bin` over TFTP from the **sender's** IP:

   ```
   printf 'UPDATE' | nc -u -w1 <board-ip> 7
   ```

The serial console shows the TFTP fetch, the `disk_part_write` to `OFP_B`, and the reset; wolfBoot then prints a successful verify of the v2 image and boots it. A tampered or unsigned download simply fails wolfBoot's signature check on the next boot and the board stays on v1.

## Layout

| File | Purpose |
|------|---------|
| `build.sh` | Build wolfBoot + sign the app + assemble `BOOT.BIN` |
| `program-sd.sh` | Write `BOOT.BIN` + signed app to an SD card |
| `boot.bif.in` | bootgen template (FSBL/PMUFW/BL31/wolfBoot) |
| `out/` | Build output (`BOOT.BIN`, `wolfip_app_v<N>_signed.bin`, `wolfboot.elf`) |

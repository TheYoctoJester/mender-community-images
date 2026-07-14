# pi-gen Raspberry Pi A/B Mender demo (Pi 4 / Pi 5)

A Debian (trixie) **arm64** Raspberry Pi OS A/B Mender demo built with
[pi-gen](https://github.com/RPi-Distro/pi-gen), the official Raspberry Pi OS image
builder. It is the fourth "Debian-style" axis after `debos/`, `elbe/` and `isar/` —
and the only one targeting **real Raspberry Pi hardware**: a single arm64 image
boots both **Pi 4** and **Pi 5**, verified on the lab DUTs (dut1 = RPi4, dut2 = RPi5)
by a full Mender OTA, not qemu.

## A/B mechanism — tryboot (reused)

Unlike the debos/elbe/isar demos, there is no bootloader in the rootfs and no GRUB.
A/B is done with the Raspberry Pi firmware's native **tryboot** mechanism, adapted
from `meta-mender-raspberrypi-tryboot` in meta-mender-community (this copy streams
the payload and sources the boot FAT from the Raspberry Pi OS `/boot/firmware`):

- `autoboot.txt` on the tryboot partition selects the active boot partition
  (`tryboot_a_b=1`); a one-shot `reboot '0 tryboot'` boots the *other* slot for one
  boot only, giving power-loss/boot-failure rollback for free.
- The `rpi-tryboot-rootfs` Mender **update module** (POSIX shell) streams the
  payload straight onto the inactive rootfs partition in the Download state (no
  buffering on the small data partition), repopulates that slot's boot FAT from
  the new rootfs's `/boot/firmware` (the complete RPi boot set), rewrites
  `cmdline.txt root=` + `autoboot.txt`, reboots via tryboot, and commits on
  success.

## Layout (MBR, `/dev/mmcblk0`)

    p1 tryboot (FAT)  autoboot.txt
    p2 bootA   (FAT)  firmware + kernel/DTBs + cmdline.txt root=/dev/mmcblk0p5
    p3 bootB   (FAT)  same, root=/dev/mmcblk0p6
    p4 extended
    p5 rootA   (ext4) active rootfs
    p6 rootB   (ext4) inactive Mender slot
    p7 data    (ext4) persistent /data (Mender state)

`mender.conf` has no `RootfsPartA/B` (the module owns slot selection); Mender state
persists on `/data` (`data.mount` + the reused `mender-data-persist` bind-mount).

## Build

The image is built by pi-gen (`stage-mender` adds the Mender client + the tryboot
integration), then hand-assembled into the 7-partition tryboot disk:

    # in the build-pi-gen-builder container, as root, --privileged:
    cp -a floating/raspberrypi/stage-mender pi-gen/stage-mender
    cp floating/raspberrypi/config pi-gen/config
    (cd pi-gen && MENDER_TENANT_TOKEN=<token> ./build.sh)
    ./floating/raspberrypi/assemble-tryboot-image.sh pi-gen/deploy/*.img out.img
    ./floating/raspberrypi/make-artifact.sh out.img pigen-ab-v2 out.mender

`out.img` is flashed to the DUT SD (via USB-SD-MUX); `out.mender` (a `module-image`
of type `rpi-tryboot-rootfs`) is the OTA payload.

## device type

`raspberrypi-pigen` (one arm64 image for both boards; the artifact is built for it).

## Status

Verified end-to-end on physical hardware: full Mender OTA (artifact upload,
streamed install to the inactive slot, tryboot reboot, verify, commit) passed on
both the Raspberry Pi 4 (dut1) and the Raspberry Pi 5 (dut2) lab DUTs —
mender-integration-builds CI run #2551 (2026-07-14), deployment
`status=finished` / `success=1` on each board.

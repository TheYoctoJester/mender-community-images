# pi-gen Raspberry Pi A/B Mender demo (Pi 4 / Pi 5)

A Debian (trixie) **arm64** Raspberry Pi OS A/B Mender demo built with
[pi-gen](https://github.com/RPi-Distro/pi-gen), the official Raspberry Pi OS image
builder. It is the fourth "Debian-style" axis after `debos/`, `elbe/` and `isar/` —
and the only one targeting **real Raspberry Pi hardware**: a single arm64 image
boots both **Pi 4** and **Pi 5**, verified on the lab DUTs (dut1 = RPi4, dut2 = RPi5)
by a full Mender OTA, not qemu.

## A/B mechanism — tryboot (reused)

Unlike the debos/elbe/isar demos, there is no bootloader in the rootfs and no GRUB.
A/B is done with the Raspberry Pi firmware's native **tryboot** mechanism, reusing
`meta-mender-raspberrypi-tryboot` from meta-mender-community:

- `autoboot.txt` on the tryboot partition selects the active boot partition
  (`tryboot_a_b=1`); a one-shot `reboot '0 tryboot'` boots the *other* slot for one
  boot only, giving power-loss/boot-failure rollback for free.
- The reused `rpi-tryboot-rootfs` Mender **update module** (POSIX shell) writes the
  inactive rootfs, repopulates that slot's boot FAT (firmware base + new kernel/DTBs
  from the artifact rootfs `/boot`), rewrites `cmdline.txt root=` + `autoboot.txt`,
  reboots via tryboot, and commits on success.

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

In development (build + hardware OTA bring-up on dut1/dut2).

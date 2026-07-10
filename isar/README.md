# ISAR Debian A/B Mender demo (qemuarm64)

A Debian (trixie) arm64 A/B Mender demo for `qemuarm64`, built with
[ISAR](https://github.com/ilbers/isar) — the BitBake-based Debian image builder.
It is the third "Debian-style" axis alongside the `debos/` and `elbe/` demos, and
the only one that builds through BitBake/kas.

Unlike the debos and elbe demos, which drive Mender's A/B rootfs switch through
GRUB (`grub-mender-grubenv`), this demo reuses the **efibootmgr** integration from
`meta-mender-community` (`meta-mender-efibootmgr`): the UEFI firmware boots an
EFI-stub kernel directly — no GRUB, no U-Boot — and a custom Mender update module
switches slots by rewriting the UEFI boot variables (`BootNext` for the one-shot
trial boot, `BootOrder` on commit). The one-shot `BootNext` gives power-loss /
boot-failure rollback for free, with no bootcount.

The layer `meta-mender-isar/` carries:

- `conf/machine/qemuarm64-mender.conf` — arm64 machine (extends stock `qemuarm64`).
- `conf/distro/debian-trixie-mender.conf` — Debian trixie plus the Mender
  device-components apt repo, so `mender-client4` installs from apt.
- `recipes-core/mender-efibootmgr` — the reused `efibootmgr-rootfs` update module,
  the first-boot UEFI-entry provisioning service, and `mender-data-persist`
  (bind-mount `/data/mender` over `/var/lib/mender` so state survives the swap).
- `recipes-core/mender-config` — `mender.conf` (no `RootfsPartA/B`; the module owns
  slot selection), device identity and base networking, written from the postinst.
- `recipes-core/images/mender-image.bb` — the demo image.

## Boot chain

    QEMU -> AAVMF (UEFI) -> EFI-stub vmlinuz (+ initrd, selected by BootNext/BootOrder) -> Debian

## Conventions

- device type `qemuarm64-isar`; artifacts `isar-ab-v1` (baked) / `isar-ab-v2` (OTA).
- slirp MAC **a8**: `52:54:00:12:35:a8` (registry: a1 uki, a2 fwu, a3 swupdate,
  a4 ostree, a5 rauc, a6 debos, a7 elbe, a8 isar).
- GPT partition labels `ESP` / `rootA` / `rootB` / `data`, with fixed PARTUUIDs on
  the A/B rootfs slots.

## Build

In the `build-isar-builder` container (see mender-integration-builds), as the
non-root `builder` user:

    MENDER_TENANT_TOKEN=<token> kas build isar/floating/qemuarm64/kas-isar-ab.yml

The `.ext4` rootfs is the OTA payload (wrapped as a `module-image` artifact of type
`efibootmgr-rootfs`).

## Status

The image builds end-to-end (Debian trixie/arm64 rootfs with the Mender client and
the efibootmgr A/B integration). The bootable A/B disk and the qemu OTA round-trip
against hosted.mender.io are in progress.

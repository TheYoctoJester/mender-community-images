# ELBE-based Mender demo images

This tree holds [ELBE](https://elbe-rfs.org/) (Embedded Linux Build Environment,
Linutronix) recipes that build **Debian** images with a Mender A/B rootfs
integration — a build-system axis parallel to `../yocto/` (Yocto/kas),
`../mender-convert/` (image conversion) and `../debos/` (debos).

It is the sibling of the debos demo: the same UEFI/GRUB + `grub-mender-grubenv`
A/B integration and `mender-client4`, built with ELBE instead of debos.

## Layout

```
elbe/
  floating/
    qemuarm64/
      qemuarm64-elbe-ab.xml           # the ELBE recipe
      overlay/opt/mender-integration/ # scripts injected into the target rootfs
```

(`tagged/` — pinned revisions — is added once a recipe stabilises.)

## qemuarm64-elbe-ab

Debian **trixie** / arm64, UEFI (AAVMF/OVMF) + GRUB, A/B rootfs via
`grub-mender-grubenv`, Mender client (`mender-client4`) from the Mender APT
repository. GPT layout: ESP · rootfsA · rootfsB · data (`/var/lib/mender`,
persistent across the A/B switch). OTA payload is a standard `rootfs-image`
`.mender` artifact (ELBE extracts the rootfs partition via `extract_partition`).

The recipe injects its integration scripts into the target via ELBE's `archive`
(the overlay directory is packed in at build time with `elbe chg_archive`, so the
committed XML stays free of base64 and of the tenant token) and runs them in the
target chroot via `<finetuning><raw_cmd>`.

Build (from this directory):

```
# inject the overlay (scripts + tenant token) into a throwaway copy of the XML
cp qemuarm64-elbe-ab.xml build.xml
echo "<HOSTED_MENDER_TENANT_TOKEN>" > overlay/opt/mender-integration/tenant-token
elbe chg_archive build.xml overlay
# build (ELBE v15 has no buildchroot; the build runs in an initvm VM)
elbe initvm create --qemu --directory ./initvm --output ./out \
    --skip-build-sources --skip-build-bin build.xml
```

ELBE v15 builds only via an **initvm** (a QEMU VM). `--qemu` runs it libvirt-less.
With `/dev/kvm` it is KVM-accelerated; **without kvm it runs under TCG** (the CI
runners have none), which is slow — the initvm plus the arm64 target build under
double emulation take hours. Outputs land in `./out`: `disk.img` (flashable v1
disk) and `rootfs.img` (root partition, wrapped into the OTA `.mender`).

## QEMU slirp MAC registry

Concurrent qemu OTA demos need distinct MACs so hosted.mender.io keys them to
distinct device identities. Prefix `52:54:00:12:35`: `a1` uki · `a2` fwu ·
`a3` swupdate · `a4` ostree · `a5` rauc · `a6` debos · **`a7` elbe**.

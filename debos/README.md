# debos-based Mender demo images

This tree holds [debos](https://github.com/go-debos/debos) recipes that build
**Debian** images with a Mender A/B rootfs integration — a build-system axis
parallel to `../yocto/` (Yocto/kas) and `../mender-convert/` (image conversion).

Unlike `mender-convert`, which post-processes a pre-built image, these recipes
build the Debian rootfs *and* apply the A/B partitioning, GRUB integration and
Mender client install in a single debos run.

## Layout

```
debos/
  floating/            # tracks branch tips / latest revisions
    qemuarm64/
      qemuarm64-debos-ab.yaml     # the recipe
      scripts/                    # chroot helpers (system config, GRUB A/B)
```

(`tagged/` — pinned revisions — is added once a recipe stabilises.)

## qemuarm64-debos-ab

**Status: verified end-to-end** (in-job qemu OTA on hosted.mender.io,
CI run #2469, deployment finished with success=1).

Debian **trixie** / arm64, UEFI (AAVMF/OVMF) + GRUB, A/B rootfs via
`grub-mender-grubenv`, Mender client (`mender-client4`) from the Mender APT
repository. GPT layout: ESP · rootfsA · rootfsB · data (`/var/lib/mender`,
persistent across the A/B switch). OTA payload is a standard `rootfs-image`
`.mender` artifact.

Build locally (kvm available):

```
debos -t tenant_token:<HOSTED_MENDER_TENANT_TOKEN> \
    floating/qemuarm64/qemuarm64-debos-ab.yaml
```

In CI the runners have no `/dev/kvm`, so the build uses debos's software
fakemachine backend (`debos -b qemu`) under a privileged container; see
`mender-integration-builds/.forgejo/workflows/build-debos-demo.yml`.

Templated variables (`-t key:value`): `tenant_token`, `suite`, `device_type`,
`artifact_name`, `server_url`, `imagename`, `imagesize`.

Outputs (in the debos artifact dir): `debos-debian-ab-qemuarm64.img` (flashable
v1 disk) and `rootfs.ext4` (root partition, wrapped into the OTA `.mender`).

## QEMU slirp MAC registry

Concurrent qemu OTA demos need distinct MACs so hosted.mender.io keys them to
distinct device identities (see the wrynose demos). Prefix `52:54:00:12:35`:
`a1` uki · `a2` fwu · `a3` swupdate · `a4` ostree · `a5` rauc · **`a6` debos**.

# Arduino Uno Q — Debian (qcom-deb-images) + Mender A/B

**Status: in development** (build + hardware verification pending).

Debian **trixie** / arm64 for the Arduino Uno Q (Qualcomm QRB2210 / qcm2290),
built with upstream [qcom-deb-images](https://github.com/qualcomm-linux/qcom-deb-images)
at a pinned commit, with the Mender client (`mender-client4`, Mender APT
repository) and A/B rootfs updates via the platform's **native Qualcomm boot
slots** (`qbootctl` + ABL) — the same mechanism, and the same `qbootctl-rootfs`
update module, as the Yocto uno-q integration in
`meta-mender-community`/`meta-mender-qcom`. Only the `device_type` differs
(`uno-q-debian` vs Yocto's `uno-q`) so deployments can never cross OS families.

Pinned upstream commits (validated together):

| repo | commit |
|---|---|
| qualcomm-linux/qcom-deb-images | `8df854f60ce8a057fb3acba2cde938fe30bb73ab` |
| qualcomm-linux/qcom-ptool | `6c9922f220c884236303a94075eb7c62e0120af0` |

## How it works

Upstream qcom-deb-images produces a single-rootfs image (ESP + rootfs,
systemd-boot) and a QDL/EDL flash directory from qcom-ptool's stock partition
table. This integration keeps the upstream recipes **unmodified** and adds:

- **A second debos stage** (`uno-q-mender.yaml`) between the upstream rootfs
  and image recipes: Mender client, update module, persistent-state service,
  bless gate, and an initramfs-tools hook + `local-top` script (`abslot`) that
  selects `root=/dev/disk/by-partlabel/system_<slot>` from the qbootctl slot —
  including the ro-test-mount self-heal that switches back to the good slot if
  the active one is unmountable.
- **An A/B partition table** (`partitions-ab-append.conf` +
  `make-flash-ab.sh`): the stock `qrb2210-unoq/emmc-16GB` table with the single
  `rootfs` replaced by `system_a`/`system_b` (both provisioned from the same
  built rootfs at flash time), `dtbo_a`/`dtbo_b` (empty; qbootctl requires them
  to exist), and a grow-to-end `userdata` (`/data`, persistent Mender state).
  Generated with upstream's own `gen-ptool.sh` against a synthesized ptool
  platform (`emmc-16GB-ab`).
- **A build-independent fstab** rewritten into the extracted rootfs image
  (`disk-sdcard.img2`) with `debugfs`: the upstream UUID-based fstab breaks
  after an OTA (the device's ESP keeps its original UUID; a v2 build references
  its own). PARTLABEL-based entries only, no `/` entry.

Boot chain: PBL → XBL → ABL (slot select via GPT A/B bits) → U-Boot
(`boot_a/b`) → systemd-boot (shared ESP) → kernel + initrd → `abslot` picks
`system_a`/`system_b`.

Commit/rollback model (identical to the Yocto integration): the Debian
`qbootctl` package's bless service (`qbootctl -m` at `boot-complete.target`)
is gated by `/data/mender-ab-updating`, so during an update Mender owns the
commit (`ArtifactCommit` → `qbootctl -m`); an unbootable slot is caught by the
initramfs self-heal, and `ArtifactVerifyReboot` then fails the deployment.

## Build

```
export MENDER_TENANT_TOKEN=<hosted Mender tenant token>
./build-uno-q.sh <workdir> <qcom-deb-images checkout> <qcom-ptool checkout>
```

Needs debos (kvm-backed fakemachine if `/dev/kvm` exists, `qemu` fallback),
e2fsprogs, mtools, dosfstools, unzip, curl, mender-artifact. CI runs it in the
`build-qcom-deb` container (see
`mender-integration-builds/.forgejo/workflows/build-qcom-deb-demo.yml`).

Optional env: `DEVICE_TYPE`, `ARTIFACT_NAME`, `SERVER_URL`, `IMAGESIZE`,
`KEEP_ROOTFS=1` (reuse the stage-1 rootfs when iterating), and
`WIFI_SSID`/`WIFI_PSK` (lab builds only: bakes NetworkManager WiFi credentials
and unexpires the `debian` user for scripted ssh — never set in CI).

Outputs (in the workdir): `disk-sdcard.img2` (rootfs slot payload),
`disk-sdcard.img1` (ESP), `flash_uno-q_emmc-ab/` (EDL flash set),
`<artifact-name>.mender` (OTA artifact, module type `qbootctl-rootfs`).

## Flash (EDL)

With the board in EDL/9008 mode and the flash dir kept as a **sibling** of the
`disk-sdcard.img*` files (the rawprogram XML references `../disk-sdcard.img1/2`):

```
cd flash_uno-q_emmc-ab
qdl --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml
```

`patch0.xml` grows `userdata` to the real eMMC end. Do **not** flash
`disk-sdcard.img` directly — it is the intermediate build image (single-rootfs
layout, pre-fstab-fix).

## Device identity

The flash set programs a **fresh, empty `userdata` filesystem** on every EDL
flash, so the device always enrolls with a new Mender device key (unlike the
Yocto flash set, which preserves userdata). If the same physical board was
previously enrolled from another OS build, its old device record on the server
still holds the board's MAC identity — decommission it (or accept the new
auth set) after the first boot.

## Known limitations

- **The kernel + initrd live on the single shared ESP and are not part of the
  OTA payload.** An update only replaces the rootfs slot; keep v1/v2 builds on
  the same kernel version, and do not `apt upgrade` the kernel on the device
  (it would write the shared ESP and affect both slots).
- `disk-sdcard.img` (the full single-rootfs build image) is a build
  intermediate only.

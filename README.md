# mender-community-images

Build configurations for Mender-enabled images, covering both Yocto/kas and mender-convert workflows.

## Overview

This repository contains two parallel configuration trees with a shared `tagged/` vs `floating/` pinning convention:

- `yocto/` — kas build configurations for various boards with Mender OTA update support, organised by Yocto release (`kirkstone/`, `scarthgap/`, `wrynose/`).
- `mender-convert/` — mender-convert configuration fragments for converting upstream disk images (Raspberry Pi OS, Debian, etc.) into Mender-compatible images.

## Directory structure

```
yocto/
├── kirkstone/
│   ├── include/                   # Shared include files pinning layer commits
│   ├── tagged/                    # Board configs using pinned revisions
│   ├── floating/                  # Board configs tracking branch tips
│   ├── demos/                     # In-repo demo layers
│   └── validation/                # Validation-image wrappers (tagged/, floating/)
├── scarthgap/                     # Same structure as kirkstone/
│   ├── include/
│   ├── tagged/
│   │   └── tegra/{jetpack5,jetpack6}/
│   ├── floating/
│   │   ├── include/               # Floating variant of include/ (branch refs)
│   │   └── tegra/{jetpack5,jetpack6}/
│   ├── demos/
│   └── validation/
└── wrynose/                       # Floating only (no tagged yet)
    ├── floating/
    │   └── include/
    └── validation/
        └── floating/

mender-convert/
├── include/                       # Sourceable shell fragments (currently empty; .gitkeep)
├── tagged/                        # Configs copied from upstream at a pinned tag
│   ├── raspberrypi/*_config
│   └── qemu-x86-64/*_config
├── floating/                      # Same layout; copied from upstream master
│   ├── raspberrypi/*_config
│   └── qemu-x86-64/*_config
└── validation/
    ├── tagged/                    # (empty, reserved)
    └── floating/                  # (empty, reserved)
```

See [mender-convert/README.md](mender-convert/README.md) for mender-convert-specific conventions.

## Tagged vs floating

- **tagged/** — In `yocto/`, every repository pinned to a specific commit (usually aligned with an upstream Yocto or Mender release tag). Use these for reproducible builds. The exact pins live in `yocto/<release>/include/*.yml`. In `mender-convert/`, configs mirror upstream at the tag that the consuming workflow pins (currently `5.2.1`).
- **floating/** — In `yocto/`, repositories track branch tips; layer versions change as upstream advances. Includes live under `yocto/<release>/floating/include/`. In `mender-convert/`, configs mirror upstream `master`.

## Demos

`yocto/<release>/demos/` holds Yocto layers imported from `meta-mender-community/kas/demos/`. They are paired with a kas wrapper in `yocto/<release>/floating/` that includes the relevant board base config plus the demo layer via a self-reference to this repo. Current demos:

- **scarthgap** — `raspberrypi4-64-{app-updates,mender-explicit-wic,tpm,wifi}.yml`, `qemuarm64-{bootloader-validation,client-only,sulka}.yml`
- **kirkstone** — `qemuarm64-swupdate.yml`

Demos are covered by the monthly Forgejo `build-yocto-<release>-floating-extended` workflows in `mender-integration-builds`; they are not yet promoted to `tagged/`.

## Usage

### Prerequisites

```bash
pip install kas
```

### Building an image

From the repository root:

```bash
# Tagged (pinned) build
kas build yocto/scarthgap/tagged/raspberrypi4-64.yml

# Floating (branch-tip) build
kas build yocto/scarthgap/floating/raspberrypi4-64.yml

# Jetson Orin, JetPack 6
kas build yocto/scarthgap/tagged/tegra/jetpack6/jetson-agx-orin-devkit.yml

# Demo: TPM-based disk encryption on Raspberry Pi 4
kas build yocto/scarthgap/floating/raspberrypi4-64-tpm.yml

# Kirkstone QEMU
kas build yocto/kirkstone/tagged/qemuarm64.yml
```

### Combining with local overrides

```bash
kas build yocto/scarthgap/tagged/raspberrypi4-64.yml:my-local-config.yml
```

### Using a mender-convert configuration

```bash
# from a mender-convert checkout (pinned 5.2.1 for tagged, or master for floating)
./mender-convert --disk-image input/raspios-bookworm-arm64-lite.img \
  --config /path/to/mender-community-images/mender-convert/tagged/raspberrypi/raspberrypi4_bookworm_64bit_config \
  --overlay input/rootfs_overlay_hosted
```

The configs under `mender-convert/` are designed to be referenced by the `build-mender-convert` workflows in the `mender-integration-builds` repository via `build-configs.json`.

## Supported boards

The authoritative list is the contents of `yocto/<release>/{tagged,floating}/`. The groupings below are for discovery.

### Scarthgap

- **Raspberry Pi** — all 0/2/3/4/5 variants (32- and 64-bit, wifi, CM, CM3, ARMv8 generic).
- **BeagleBone** — Black, Black U-Boot, AI-64, BeaglePlay (TI).
- **QEMU** — `qemuarm64`, `qemux86-64`, `vexpress-qemu`, `vexpress-qemu-flash` (UBI).
- **NVIDIA Tegra** — JetPack 5 and 6 machines (AGX Orin Devkit, Orin Nano Devkit, Orin NX 16GB p3786, plus JP5-only AGX Xavier).
- **Rockchip** — `rock-4c-plus`, `rock-4c-plus-enc` (OP-TEE fTPM + LUKS variant).
- **NXP/Freescale (experimental)** — `olimex-imx8mp-evb`, `imx93-var-som` (Variscite).
- **RISC-V (experimental)** — `nezha-allwinner-d1`.
- **Intel** — `x86-virtual`.

### Kirkstone

- **Raspberry Pi** — `raspberrypi3-64`, `raspberrypi4-64`, `raspberrypi5`, `raspberrypi-armv8`.
- **BeagleBone** — Black, Black U-Boot.
- **QEMU** — `qemuarm64`, `qemux86-64`.

### Wrynose (floating only)

Initial port: the same `qemu{arm64,x86-64}`, RPi {3-64,4-64,5,ARMv8}, and BeagleBone {Black, U-Boot} as kirkstone.

## Layer pinning

Tagged include files under `yocto/<release>/include/` are the source of truth for layer revisions. They are bumped periodically to track upstream point releases (for example, yocto-5.0.17 / meta-mender scarthgap-v2026.04 / kirkstone-4.0.33 / meta-mender kirkstone-v2025.11 were the current pins at the time of the last bump). `git log yocto/<release>/include/` shows the history.

Floating builds do not pin layers; they take whatever is at branch tip when the build runs. The corresponding pins are still present in `yocto/<release>/floating/include/` but use `branch:` rather than `commit:`.

## CI

Per-release build matrices and schedules are defined in the sibling `mender-integration-builds` repository under `.forgejo/workflows/build-yocto-<release>-{tagged,floating}-{core,extended}.yml`, with registration in `.forgejo/configs/build-configs.json`.

## License

See [LICENSE](LICENSE).

# mender-community-images

Build configurations for Mender-enabled images, covering both Yocto/kas and mender-convert workflows.

## Overview

This repository contains two parallel configuration trees with a shared `tagged/` vs `floating/` pinning convention:

- `yocto/` — kas build configurations for various boards with Mender OTA update support, organised by Yocto release version.
- `mender-convert/` — mender-convert configuration fragments for converting upstream disk images (Raspberry Pi OS, Debian, etc.) into Mender-compatible images.

## Directory Structure

```
yocto/
└── scarthgap/
    ├── include/                    # Shared include files (tagged versions)
    │   ├── mender-base.yml         # Base Mender configuration
    │   ├── mender-full.yml         # Full Mender integration
    │   ├── mender-full-ubi.yml     # Mender with UBI support
    │   ├── arm.yml                 # meta-arm layer
    │   ├── nxp.yml                 # NXP/Freescale layers
    │   ├── qemu.yml                # QEMU support
    │   ├── raspberrypi.yml         # Raspberry Pi layers
    │   ├── rockchip.yml            # Rockchip layers
    │   ├── sulka.yml               # Sulka distro
    │   ├── tegra-base.yml          # NVIDIA Tegra base
    │   ├── tegra-jetpack5.yml      # JetPack 5.x support
    │   ├── tegra-jetpack6.yml      # JetPack 6.x support
    │   ├── ti.yml                  # Texas Instruments layers
    │   └── validation.yml          # Mender validation testing
    ├── tagged/                     # Pinned commit versions
    │   ├── raspberrypi*.yml        # Raspberry Pi variants
    │   ├── beagle*.yml             # BeagleBone variants
    │   ├── qemu*.yml               # QEMU machines
    │   ├── rock-4c-plus.yml        # Rockchip board
    │   ├── x86-virtual.yml         # x86 virtual machine
    │   └── tegra/
    │       ├── jetpack5/           # JetPack 5.x machines
    │       └── jetpack6/           # JetPack 6.x machines
    └── floating/                   # Branch-based versions
        ├── include/                # Floating include files
        └── (same structure as tagged/)

mender-convert/
├── include/                        # Sourceable shell fragments shared across configs
├── tagged/                         # Configs mirrored from upstream mender-convert at the pinned tag
│   ├── raspberrypi/*_config
│   └── qemu-x86-64/*_config
├── floating/                       # Same layout; mirrored from upstream master
└── validation/
    ├── tagged/                     # Validation-only variants, pinned
    └── floating/                   # Validation-only variants, master-tracking
```

## Tagged vs Floating

- **tagged/**: In `yocto/`, all layer repositories are pinned to specific commits — use this for reproducible kas builds. In `mender-convert/`, configs are copied from the upstream mender-convert tag that the consuming workflow pins (currently `5.2.1`).
- **floating/**: In `yocto/`, repositories track branch heads. In `mender-convert/`, configs mirror upstream `master` and may pick up upstream changes sooner.

See [mender-convert/README.md](mender-convert/README.md) for the mender-convert-specific conventions, including the shadowing rules.

## Usage

### Prerequisites

Install kas:
```bash
pip install kas
```

### Building an Image

From the repository root:

```bash
# Build Raspberry Pi 4 (64-bit) with tagged/pinned versions
kas build yocto/scarthgap/tagged/raspberrypi4-64.yml

# Build with floating versions (latest branch commits)
kas build yocto/scarthgap/floating/raspberrypi4-64.yml

# Build NVIDIA Jetson Orin with JetPack 6
kas build yocto/scarthgap/tagged/tegra/jetpack6/jetson-agx-orin-devkit.yml
```

### Using Configuration Overrides

You can combine configs with your own local overrides:

```bash
kas build yocto/scarthgap/tagged/raspberrypi4-64.yml:my-local-config.yml
```

### Using a mender-convert configuration

mender-convert consumes a single shell-fragment config. The configs under `mender-convert/` are designed to be referenced by the `build-mender-convert` workflows in the `mender-integration-builds` repository (via `build-configs.json`), but they can also be used directly against a local mender-convert checkout:

```bash
# from a mender-convert checkout
./mender-convert --disk-image input/raspios-bookworm-arm64-lite.img \
  --config /path/to/mender-community-images/mender-convert/tagged/raspberrypi/raspberrypi4_bookworm_64bit_config \
  --overlay input/rootfs_overlay_hosted
```

See [mender-convert/README.md](mender-convert/README.md) for the contribution flow.

## Supported Boards

### Raspberry Pi
- raspberrypi (original)
- raspberrypi0, raspberrypi0-wifi, raspberrypi0-2w, raspberrypi0-2w-64
- raspberrypi2, raspberrypi3, raspberrypi3-64
- raspberrypi4, raspberrypi4-64
- raspberrypi5
- raspberrypi-cm, raspberrypi-cm3
- raspberrypi-armv8

### BeagleBone
- beaglebone (beaglebone-yocto machine)
- beaglebone-uboot (with U-Boot support)
- beaglebone-ai64
- beagleplay-ti

### NVIDIA Tegra (JetPack 5.x)
- jetson-agx-orin-devkit
- jetson-agx-orin-devkit-64 (p3737-0000-p3701-0005)
- jetson-agx-xavier-devkit
- jetson-orin-nano-devkit
- jetson-orin-16gb-nx-p3786 (p3768-0000-p3767-0000)

### NVIDIA Tegra (JetPack 6.x)
- jetson-agx-orin-devkit
- jetson-agx-orin-devkit-64 (p3737-0000-p3701-0005)
- jetson-orin-nano-devkit
- jetson-orin-16gb-nx-p3786 (p3768-0000-p3767-0000)

### NXP/Freescale
- olimex-imx8mp-evb
- imx93-var-som (Variscite)

### QEMU
- qemuarm64
- qemux86-64
- vexpress-qemu
- vexpress-qemu-flash (UBI)

### Other
- rock-4c-plus (Rockchip)
- nezha-allwinner-d1 (RISC-V)
- x86-virtual (Intel)

## Repository References

The tagged configurations pin meta-mender-community to commit `9145b8e34bac23c82984ddcdd5468154ffe7af6d`
(scarthgap branch). The floating configurations track the `scarthgap` branch head.

## License

See LICENSE file.

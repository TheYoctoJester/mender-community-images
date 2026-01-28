# mender-community-images

Build configurations and scripts for Mender-enabled images.

## Overview

This repository contains kas build configurations for various boards with Mender OTA update support.
The configurations are organized by Yocto release version and pinning strategy.

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
```

## Tagged vs Floating

- **tagged/**: All repositories are pinned to specific commits. Use this for reproducible builds.
- **floating/**: Repositories track branch heads. Use this for development or to pick up latest fixes.

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

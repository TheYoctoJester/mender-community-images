#!/bin/bash
# Build the Mender OTA artifact for the pi-gen tryboot A/B demo (no loop devices).
#
# The payload is the rootA ext4 filesystem image (emitted by assemble-tryboot-image.sh),
# whose /boot holds the kernel/DTBs. On the device the reused rpi-tryboot-rootfs update
# module dd's it onto the inactive slot, repopulates that slot's boot FAT, and flips the
# RPi tryboot A/B selection.
set -euo pipefail

ROOTFS_EXT4="${1:?usage: make-artifact.sh <rootA.ext4> <artifact-name> <output.mender> [device-type]}"
ART_NAME="${2:?artifact name required}"
OUT="${3:?output .mender path required}"
DEVICE_TYPE="${4:-raspberrypi-pigen}"

mender-artifact write module-image \
    --type rpi-tryboot-rootfs \
    --device-type "$DEVICE_TYPE" \
    --artifact-name "$ART_NAME" \
    --file "$ROOTFS_EXT4" \
    --output-path "$OUT"

echo "wrote $OUT (type=rpi-tryboot-rootfs, name=$ART_NAME, device=$DEVICE_TYPE)"

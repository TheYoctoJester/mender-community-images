#!/bin/bash
# Build the Mender OTA artifact for the Uno Q qcom-deb-images A/B integration.
#
# The payload is the raw rootfs ext4 image (disk-sdcard.img2, extracted by the
# upstream image recipe and fstab-fixed by build-uno-q.sh). On the device the
# qbootctl-rootfs update module streams it onto the inactive system_<slot> and
# flips the Qualcomm boot slot — the same module type as the Yocto uno-q
# integration, so the artifact format is identical across both OS families
# (only the device_type differs).
set -euo pipefail

ROOTFS_IMG="${1:?usage: make-artifact.sh <disk-sdcard.img2> <artifact-name> <output.mender> [device-type]}"
ART_NAME="${2:?artifact name required}"
OUT="${3:?output .mender path required}"
DEVICE_TYPE="${4:-uno-q-debian}"

mender-artifact write module-image \
    --type qbootctl-rootfs \
    --device-type "$DEVICE_TYPE" \
    --artifact-name "$ART_NAME" \
    --file "$ROOTFS_IMG" \
    --output-path "$OUT"

echo "wrote $OUT (type=qbootctl-rootfs, name=$ART_NAME, device=$DEVICE_TYPE)"

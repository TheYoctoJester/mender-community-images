#!/bin/bash
# Generate the A/B EDL flash directory for the Arduino Uno Q.
#
# This deliberately replaces the upstream flash recipe
# (qualcomm-linux-debian-flash.yaml), for two reasons:
#  - the upstream recipe downloads and unpacks boot binaries for EVERY board it
#    knows (the download loop is not gated on target_boards);
#  - we need a modified partition table (A/B system slots) that upstream's
#    stock qcom-ptool platform does not carry.
# It reproduces only the imola (Uno Q) leg of that recipe, using the same
# pinned qcom-ptool and the same gen-ptool.sh, against a synthesized
# "emmc-16GB-ab" platform derived from the stock one exactly like the Yocto
# integration's qcom-partition-conf bbappend does.
#
# Flash (board in EDL/9008 mode; keep the flash dir a SIBLING of the two
# disk-sdcard.img* files — rawprogram references them as ../disk-sdcard.img1/2):
#   cd flash_uno-q_emmc-ab
#   qdl --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml
set -euo pipefail

WORK="${1:?usage: make-flash-ab.sh <workdir> <qcom-deb-images-dir> <qcom-ptool-dir> [buildid]}"
QCOM_DEB_IMAGES="${2:?qcom-deb-images checkout required}"
QCOM_PTOOL="${3:?qcom-ptool checkout required}"
BUILDID="${4:-unoq-ab}"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$WORK" && pwd)"
QCOM_DEB_IMAGES="$(cd "$QCOM_DEB_IMAGES" && pwd)"
QCOM_PTOOL="$(cd "$QCOM_PTOOL" && pwd)"

# Same pins as the upstream flash recipe at the qcom-deb-images commit this
# tree is validated against (see README.md).
QCOM_PTOOL_PIN="6c9922f220c884236303a94075eb7c62e0120af0"
BOOTBIN_URL="https://downloads.arduino.cc/debian-im/unoq-bootloader-emmc-linux-251020.zip"
BOOTBIN_SHA256="c606e95d0107f8c58d0dd9494e00624d1db7c4361cca20513bc78ef02ca28dd1"
BOARD_DTB="qcom/qrb2210-arduino-imola.dtb"
STOCK_PLATFORM="qrb2210-unoq/emmc-16GB"
AB_PLATFORM="qrb2210-unoq/emmc-16GB-ab"

for f in disk-sdcard.img1 disk-sdcard.img2 dtbs.tar.gz; do
    [ -f "$WORK/$f" ] || { echo "ERROR: $WORK/$f missing (run the image build first)" >&2; exit 1; }
done

ptool_head="$(git -C "$QCOM_PTOOL" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$ptool_head" != "$QCOM_PTOOL_PIN" ]; then
    echo "WARNING: qcom-ptool at $ptool_head, validated against $QCOM_PTOOL_PIN" >&2
fi

# --- synthesize the A/B platform in a working copy of qcom-ptool -------------
# (gen-ptool.sh resolves platforms relative to the ptool tree; keep the user's
# checkout pristine)
PTOOL_WORK="$WORK/ptool-ab"
rm -rf "$PTOOL_WORK"
mkdir -p "$PTOOL_WORK"
cp -a "$QCOM_PTOOL"/. "$PTOOL_WORK/"
rm -rf "$PTOOL_WORK/.git"
mkdir -p "$PTOOL_WORK/platforms/$AB_PLATFORM"
# drop the single rootfs partition, keep everything else (incl.
# --grow-last-partition on --disk), then append the A/B block
sed '/--name=rootfs /d' "$PTOOL_WORK/platforms/$STOCK_PLATFORM/partitions.conf" \
    > "$PTOOL_WORK/platforms/$AB_PLATFORM/partitions.conf"
grep -v '^#' "$HERE/partitions-ab-append.conf" | grep -v '^$' \
    >> "$PTOOL_WORK/platforms/$AB_PLATFORM/partitions.conf"

# --- boot binaries (Arduino-signed XBL/ABL/U-Boot etc.) ----------------------
DL="$WORK/downloads"
mkdir -p "$DL"
ZIP="$DL/qrb2210-arduino-imola_boot-binaries.zip"
if [ ! -f "$ZIP" ] || ! echo "$BOOTBIN_SHA256  $ZIP" | sha256sum -c --quiet -; then
    curl -fSL -o "$ZIP" "$BOOTBIN_URL"
    echo "$BOOTBIN_SHA256  $ZIP" | sha256sum -c --quiet -
fi
BOOTBIN="$WORK/boot-binaries"
rm -rf "$BOOTBIN"
mkdir -p "$BOOTBIN"
unzip -q "$ZIP" -d "$BOOTBIN"

# --- flash directory ---------------------------------------------------------
FLASH_DIR="$WORK/flash_uno-q_emmc-ab"
rm -rf "$FLASH_DIR"
mkdir -p "$FLASH_DIR"

# ptool XMLs (rawprogram/patch/gpt), generated into the flash dir; empty CDT,
# emmc disk type, combineddtb — the same arguments the upstream flash recipe
# uses for the imola board
(
    cd "$FLASH_DIR"
    "$QCOM_DEB_IMAGES/scripts/gen-ptool.sh" \
        "$PTOOL_WORK" "$AB_PLATFORM" "" "$BUILDID" emmc combineddtb
)

# remove BLANK_GPT, WIPE_PARTITIONS and wipe_rawprogram files (same rationale
# as upstream: qdl rawprogram*.xml must not wipe the device by accident)
rm -f "$FLASH_DIR"/rawprogram*_BLANK_GPT.xml \
      "$FLASH_DIR"/rawprogram*_WIPE_PARTITIONS.xml \
      "$FLASH_DIR"/wipe_rawprogram*.xml

# copy boot binaries with the upstream find filter (never partition files)
find "$BOOTBIN" \
    -not -name 'gpt_*' \
    -not -name 'patch*.xml' \
    -not -name 'rawprogram*.xml' \
    -not -name 'wipe*.xml' \
    -not -name 'zeros_*' \
    \( \
        -name LICENSE \
        -or -name Qualcomm-Technologies-Inc.-Proprietary \
        -or -name 'prog_*' \
        -or -name 'boot.img' \
        -or -name '*.bin' \
        -or -name '*.elf' \
        -or -name '*.melf' \
        -or -name '*.fv' \
        -or -name '*.mbn' \
    \) \
    -exec cp --preserve=mode,timestamps '{}' "$FLASH_DIR" \;

# dtb-combineddtb.bin: FAT with the board device tree as combined-dtb.dtb
# (mirrors the upstream flash recipe verbatim, including the 4096-byte FAT
# sector size)
DTB_BIN="$FLASH_DIR/dtb-combineddtb.bin"
rm -f "$DTB_BIN"
mkfs.vfat -S 4096 -C "$DTB_BIN" 4096
mkdir -p "$WORK/dtb-extract"
tar -C "$WORK/dtb-extract" -xf "$WORK/dtbs.tar.gz" "$BOARD_DTB"
mcopy -mp -i "$DTB_BIN" "$WORK/dtb-extract/$BOARD_DTB" ::/combined-dtb.dtb

# fresh, empty userdata filesystem: flashed into the userdata partition so a
# reflash never inherits a previous OS's Mender identity; grown to the real
# partition size on first boot (x-systemd.growfs)
truncate -s 64M "$FLASH_DIR/userdata.img"
mkfs.ext4 -q -F -L userdata "$FLASH_DIR/userdata.img"

# --- sanity checks -----------------------------------------------------------
for part in system_a system_b userdata dtbo_a boot_a efi; do
    grep -q "label=\"$part\"" "$FLASH_DIR"/rawprogram*.xml || {
        echo "ERROR: partition $part missing from generated rawprogram XMLs" >&2
        exit 1
    }
done
grep -q 'filename="../disk-sdcard.img2".*label="system_a"\|label="system_a".*filename="../disk-sdcard.img2"' \
    "$FLASH_DIR"/rawprogram*.xml || {
    echo "ERROR: system_a is not mapped to ../disk-sdcard.img2" >&2
    exit 1
}
[ -f "$FLASH_DIR/prog_firehose_ddr.elf" ] || {
    echo "ERROR: prog_firehose_ddr.elf missing from boot binaries" >&2
    exit 1
}
[ -f "$FLASH_DIR/boot.img" ] || {
    echo "ERROR: boot.img (U-Boot) missing from boot binaries" >&2
    exit 1
}

echo "flash dir ready: $FLASH_DIR"
echo "flash with: cd $FLASH_DIR && qdl --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml"

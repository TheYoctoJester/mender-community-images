#!/bin/bash
# Assemble a 7-partition tryboot A/B SD image from a pi-gen rootfs directory.
#
# No loop devices are used (the CI/build container's /dev has no udev, so
# /dev/loopNpM partition nodes can't be created): each partition filesystem is
# built as a plain file (mke2fs -d for ext4, mkfs.vfat + mcopy for FAT), the disk
# is partitioned with sfdisk, and each filesystem is dd'd to its partition offset.
#
# Input : the pi-gen rootfs DIR (with /boot/firmware holding the RPi boot files);
#         the Mender client + tryboot module are already installed in it.
# Output: <out.img> (flashable) and, if given, <rootA.ext4> (the OTA artifact payload).
#
# Layout (MBR /dev/mmcblk0): p1 tryboot(FAT) p2 bootA(FAT) p3 bootB(FAT) p4 extended
#         p5 rootA(ext4) p6 rootB(ext4) p7 data(ext4). Run as root in the container.
set -euo pipefail

ROOTFS_DIR="${1:?usage: assemble-tryboot-image.sh <rootfs-dir> <out.img> [rootA.ext4-out]}"
OUT_IMG="${2:?output image path required}"
ROOTA_OUT="${3:-}"

TRYBOOT_MB=16; BOOT_MB=128; DATA_MB=512; SLACK_MB=400
BOOTSRC="$ROOTFS_DIR/boot/firmware"
[ -d "$BOOTSRC" ] || { echo "ERROR: $BOOTSRC not found (expected RPi boot files)"; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

ROOT_MB=$(( $(du -s --block-size=1M "$ROOTFS_DIR" | cut -f1) + SLACK_MB ))
echo "== rootfs ~$(( ROOT_MB - SLACK_MB )) MB -> slot ${ROOT_MB} MB =="

echo "== building partition filesystems (no loop) =="
# p1 tryboot: autoboot.txt
truncate -s "${TRYBOOT_MB}M" "$work/p1"; mkfs.vfat -n tryboot "$work/p1" >/dev/null
cat > "$work/autoboot.txt" <<'EOF'
[all]
tryboot_a_b=1
boot_partition=2

[tryboot]
boot_partition=3
EOF
mcopy -i "$work/p1" "$work/autoboot.txt" ::autoboot.txt

# p2 bootA / p3 bootB: firmware + kernel/DTBs/config + per-slot cmdline root=
build_bootfat() {   # $1 outfile  $2 label  $3 root-dev
    truncate -s "${BOOT_MB}M" "$1"; mkfs.vfat -n "$2" "$1" >/dev/null
    local d="$work/bt"; rm -rf "$d"; cp -a "$BOOTSRC" "$d"
    [ -f "$d/cmdline.txt" ] && sed -i "s|root=[^ ]*|root=$3|" "$d/cmdline.txt" || \
        echo "console=serial0,115200 console=tty1 root=$3 rootfstype=ext4 fsck.repair=yes rootwait" > "$d/cmdline.txt"
    ( cd "$d" && mcopy -i "$1" -s -Q ./* ::/ )
}
build_bootfat "$work/p2" bootA /dev/mmcblk0p5
build_bootfat "$work/p3" bootB /dev/mmcblk0p6

# p5 rootA (populate from the rootfs dir, no mount), p6 rootB (copy), p7 data (empty)
mke2fs -q -t ext4 -L rootA -d "$ROOTFS_DIR" "$work/p5" "${ROOT_MB}M"
cp "$work/p5" "$work/p6"; e2label "$work/p6" rootB
mke2fs -q -t ext4 -L data "$work/p7" "${DATA_MB}M"

echo "== partitioning $OUT_IMG (MBR, parted) =="
# MiB layout; 1 MiB gaps before each logical partition for its EBR. parted reliably
# builds the extended + logical partitions (sfdisk script-mode did not here).
P1S=1;                         P1E=$((P1S+TRYBOOT_MB))
P2S=$P1E;                      P2E=$((P2S+BOOT_MB))
P3S=$P2E;                      P3E=$((P3S+BOOT_MB))
EXTS=$P3E
P5S=$((EXTS+1));               P5E=$((P5S+ROOT_MB))
P6S=$((P5E+1));                P6E=$((P6S+ROOT_MB))
P7S=$((P6E+1));                P7E=$((P7S+DATA_MB))
TOTAL_MB=$((P7E+1))
rm -f "$OUT_IMG"; truncate -s "${TOTAL_MB}M" "$OUT_IMG"
parted -s "$OUT_IMG" mklabel msdos
parted -s "$OUT_IMG" mkpart primary fat32 "${P1S}MiB" "${P1E}MiB"
parted -s "$OUT_IMG" mkpart primary fat32 "${P2S}MiB" "${P2E}MiB"
parted -s "$OUT_IMG" mkpart primary fat32 "${P3S}MiB" "${P3E}MiB"
parted -s "$OUT_IMG" mkpart extended "${EXTS}MiB" "100%"
parted -s "$OUT_IMG" mkpart logical ext4 "${P5S}MiB" "${P5E}MiB"
parted -s "$OUT_IMG" mkpart logical ext4 "${P6S}MiB" "${P6E}MiB"
parted -s "$OUT_IMG" mkpart logical ext4 "${P7S}MiB" "${P7E}MiB"
parted -s "$OUT_IMG" set 1 boot on

echo "== writing filesystems to partition offsets =="
for n in 1 2 3 5 6 7; do
    start=$(sfdisk -d "$OUT_IMG" | sed -n "s|^${OUT_IMG}${n} .*start=[[:space:]]*\([0-9]\+\).*|\1|p")
    [ -n "$start" ] || { echo "ERROR: no start for p${n}"; sfdisk -d "$OUT_IMG"; exit 1; }
    dd if="$work/p${n}" of="$OUT_IMG" bs=512 seek="$start" conv=notrunc,fsync status=none
    echo "  p${n} -> sector ${start}"
done

if [ -n "$ROOTA_OUT" ]; then cp "$work/p5" "$ROOTA_OUT"; echo "== rootA ext4 -> $ROOTA_OUT =="; fi
sync
echo "== done: $OUT_IMG (${TOTAL_MB} MB) =="

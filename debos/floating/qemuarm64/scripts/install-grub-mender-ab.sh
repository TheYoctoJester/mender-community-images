#!/bin/sh
# Install grub-mender-grubenv (GRUB A/B rootfs integration) into the target rootfs.
# Runs chrooted. Follows mender-convert's modules/grub.sh (standalone EFI path),
# adapted for debos: the GRUB EFI binary is built with grub-mkstandalone so no
# real block device / grub-probe is needed before the image is partitioned.
set -eu

# Pinned grub-mender-grubenv revision (same as mender-convert 5.2.x).
GRUBENV_REV="64e32b01d1bf54784d2a290ad0469c583e843864"
WORK="/tmp/grub-mender-grubenv"

rm -rf "$WORK"
mkdir -p "$WORK"
curl -fsSL "https://github.com/mendersoftware/grub-mender-grubenv/archive/${GRUBENV_REV}.tar.gz" \
    -o /tmp/grubenv.tar.gz
tar -xzf /tmp/grubenv.tar.gz -C "$WORK" --strip-components=1
cd "$WORK"

# Partition / kernel layout for this image (see qemuarm64-debos-ab.yaml):
#   /dev/vda2 = rootfsA, /dev/vda3 = rootfsB; kernel+initrd live in the rootfs /boot.
cat > mender_grubenv_defines <<EOF
mender_rootfsa_part=2
mender_rootfsb_part=3
mender_kernel_root_base=/dev/vda
kernel_imagetype=vmlinuz
initrd_imagetype=initrd.img
EOF

make
# grub.cfg -> (ESP)/EFI/BOOT/grub.cfg ; grubenv -> (ESP)/grub-mender-grubenv/... ;
# grub-mender-grubenv-print/-set -> /usr/bin (used by the Mender rootfs-image module).
make DESTDIR=/ BOOT_DIR=/boot/efi install-standalone-boot-files
make DESTDIR=/ install-tools

# Build the arm64 GRUB EFI binary the same way meta-mender/grub-mender-grubenv
# does (grub-efi/grub.inc): grub-mkimage with a RELATIVE prefix "/EFI/BOOT". EFI
# sets ${root} to the partition the binary loaded from (the ESP), so GRUB loads
# ${prefix}/grub.cfg = (ESP)/EFI/BOOT/grub.cfg and the mender scripts find their
# A/B env at (ESP)/grub-mender-grubenv/... . (grub-mkstandalone must NOT be used
# here: it bakes a (memdisk) prefix, leaving ${root}=(memdisk) so the env lookup
# fails.)
mkdir -p /boot/efi/EFI/BOOT
GRUB_MOD_DIR=/usr/lib/grub/arm64-efi
# Module set from grub.inc plus what the mender scripts need; filtered to those
# that actually ship (names vary by GRUB version).
WANT="boot linux ext2 fat serial part_msdos part_gpt normal efi_gop configfile search search_fs_file search_label loadenv test cat echo halt hashsum sleep reboot regexp gzio terminal terminfo video all_video"
MODS=""
for m in ${WANT}; do
    [ -f "${GRUB_MOD_DIR}/${m}.mod" ] && MODS="${MODS} ${m}"
done
grub-mkimage \
    -p /EFI/BOOT \
    -d "${GRUB_MOD_DIR}" \
    -O arm64-efi \
    -o /boot/efi/EFI/BOOT/BOOTAA64.EFI \
    ${MODS}

cd /
rm -rf "$WORK" /tmp/grubenv.tar.gz

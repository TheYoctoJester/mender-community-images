#!/bin/sh
# Install grub-mender-grubenv (GRUB A/B rootfs integration) into the target rootfs.
# Runs in the target chroot (ELBE finetuning). Same logic as the debos demo: the
# GRUB EFI binary is built with grub-mkimage using a RELATIVE prefix "/EFI/BOOT"
# so EFI sets ${root} to the ESP the binary loaded from, and grub-mender-grubenv
# finds its A/B env at (ESP)/grub-mender-grubenv/... .
set -eu

GRUBENV_REV="64e32b01d1bf54784d2a290ad0469c583e843864"
WORK="/tmp/grub-mender-grubenv"

rm -rf "$WORK"
mkdir -p "$WORK"
curl -fsSL "https://github.com/mendersoftware/grub-mender-grubenv/archive/${GRUBENV_REV}.tar.gz" \
    -o /tmp/grubenv.tar.gz
tar -xzf /tmp/grubenv.tar.gz -C "$WORK" --strip-components=1
cd "$WORK"

# Partition / kernel layout for this image (see qemuarm64-elbe-ab.xml):
#   /dev/vda2 = rootfsA, /dev/vda3 = rootfsB; kernel+initrd live in the rootfs /boot.
cat > mender_grubenv_defines <<EOF
mender_rootfsa_part=2
mender_rootfsb_part=3
mender_kernel_root_base=/dev/vda
kernel_imagetype=vmlinuz
initrd_imagetype=initrd.img
EOF

make
make DESTDIR=/ BOOT_DIR=/boot/efi install-standalone-boot-files
make DESTDIR=/ install-tools

mkdir -p /boot/efi/EFI/BOOT
GRUB_MOD_DIR=/usr/lib/grub/arm64-efi
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

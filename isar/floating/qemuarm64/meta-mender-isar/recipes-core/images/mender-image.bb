# ISAR Debian A/B Mender demo image (qemuarm64).
#
# A minbase-ish Debian trixie/arm64 rootfs with the Mender client (mender-client4,
# from the Mender device-components apt repo) and the efibootmgr A/B integration
# (custom Mender update module + first-boot UEFI provisioning + data persistence).
# The kernel (linux-image-arm64) is added automatically by the image class.
#
# Output: the .ext4 rootfs is the OTA payload (wrapped as a module-image artifact
# of type efibootmgr-rootfs). The bootable A/B .wic disk is added in the boot/OTA
# bring-up phase.
DESCRIPTION = "ISAR Debian A/B Mender demo image (qemuarm64, efibootmgr A/B)"
LICENSE = "gpl-2.0"
LIC_FILES_CHKSUM = "file://${LAYERDIR_core}/licenses/COPYING.GPLv2;md5=751419260aa954499f7abaabaa882bbe"

PV = "1.0"

inherit image

# From the Mender apt repo + Debian: the client, the UEFI slot-switch tool,
# initramfs tooling (Debian's arm64 kernel is modular and needs an initrd), and
# systemd-ukify + the EFI stub for building the first-boot UKI fallback.
IMAGE_PREINSTALL += " \
    mender-client4 \
    efibootmgr \
    initramfs-tools \
    ca-certificates \
    util-linux \
    systemd-boot-efi \
    systemd-resolved \
    systemd-timesyncd \
"
# systemd-resolved is a separate package on trixie; without it /etc/resolv.conf
# (-> stub-resolv.conf) is dangling and the client can't resolve hosted.mender.io.
# systemd-timesyncd keeps the clock sane for TLS. (Both are in the debos/elbe demos.)
# Note: only systemd-boot-efi is installed in the target (it ships the arm64 EFI
# stub, and installs cleanly). systemd-ukify is NOT installed on the target --
# its python3-pefile dep segfaults under qemu-user arm64 -- the UKI is built on
# the host instead (see mender_isar_stage_esp; ukify is in build-isar-builder).

# Debian's arm64 kernel is modular -> we need a real initrd in /boot.
ROOTFS_FEATURES:append = " generate-initrd"

# Our integration packages (built by this layer).
IMAGE_INSTALL += " \
    mender-efibootmgr \
    mender-config \
"

# ISAR minbase has no /etc/hostname (and ROOTFS_CLEAN_FILES removes it), but
# mender-setup's postinst runs `cat /etc/hostname` and fails without it -- and
# apt configures mender-setup (a mender-client4 dependency) immediately after
# unpack, before any package that could ship /etc/hostname. So write it into the
# rootfs just before the package-install step. ROOTFS_INSTALL_COMMAND runs in
# LIST ORDER (the [weight] flag is only for progress), and a plain += lands at the
# end (after install), so splice the step in right before rootfs_install_pkgs_install.
MENDER_ISAR_HOSTNAME ?= "qemuarm64-isar"
rootfs_install_mender_hostname() {
    echo "${MENDER_ISAR_HOSTNAME}" | sudo tee "${ROOTFSDIR}/etc/hostname" >/dev/null
}
python () {
    cmds = (d.getVar('ROOTFS_INSTALL_COMMAND') or '').split()
    if 'rootfs_install_mender_hostname' not in cmds and 'rootfs_install_pkgs_install' in cmds:
        cmds.insert(cmds.index('rootfs_install_pkgs_install'), 'rootfs_install_mender_hostname')
        d.setVar('ROOTFS_INSTALL_COMMAND', ' ' + ' '.join(cmds))
}

# Build the ESP tree in a separate staging dir (NOT inside ${IMAGE_ROOTFS}, which
# would bloat the ext4 OTA payload). The wks copies it into the FAT ESP via
# --rootfs-dir=${MENDER_ESP_DIR}:
#   EFI/BOOT/bootaa64.efi         - a UKI (kernel+initrd+cmdline baked, root=rootA)
#                                   booted by the firmware's removable-media
#                                   fallback on first boot (Debian's arm64 kernel
#                                   has no builtin CONFIG_CMDLINE, so bake it).
#   EFI/mender-{a,b}/linux.efi    - plain EFI-stub kernel per slot; the per-slot
#   EFI/mender-{a,b}/initrd.img      UEFI entries (created by the first-boot
#                                   service) pass root=/initrd= via load options.
# Runs after do_rootfs (kernel+initrd are deployed to DEPLOY_DIR_IMAGE by then --
# ISAR does not keep the initrd in the rootfs /boot) and before do_image (wic).
MENDER_ESP_DIR = "${WORKDIR}/mender-esp"
WICVARS:append = " MENDER_ESP_DIR"

do_mender_stage_esp() {
    sudo -s <<'EOSUDO'
    set -e
    R="${IMAGE_ROOTFS}"
    DEP="${DEPLOY_DIR_IMAGE}"
    ESP="${MENDER_ESP_DIR}"
    KERNEL=$(ls "$DEP"/*-vmlinux 2>/dev/null | head -1)
    INITRD=$(ls "$DEP"/*-initrd.img 2>/dev/null | head -1)
    STUB="$R/usr/lib/systemd/boot/efi/linuxaa64.efi.stub"
    [ -f "$KERNEL" ] || { echo "do_mender_stage_esp: no deployed kernel (*-vmlinux)"; exit 1; }
    [ -f "$INITRD" ] || { echo "do_mender_stage_esp: no deployed initrd (*-initrd.img)"; exit 1; }
    [ -f "$STUB" ]   || { echo "do_mender_stage_esp: no EFI stub $STUB"; exit 1; }
    rm -rf "$ESP"
    mkdir -p "$ESP/EFI/BOOT" "$ESP/EFI/mender-a" "$ESP/EFI/mender-b"
    # UKI built on the HOST (ukify from build-isar-builder): the target's own
    # systemd-ukify can't run (python3-pefile segfaults under qemu-user arm64).
    ukify build \
        --stub="$STUB" \
        --linux="$KERNEL" \
        --initrd="$INITRD" \
        --cmdline="root=PARTUUID=${MENDER_ISAR_ROOTA_UUID} rootwait rw console=ttyAMA0,115200" \
        --output="$ESP/EFI/BOOT/bootaa64.efi"
    cp "$KERNEL" "$ESP/EFI/mender-a/linux.efi"; cp "$INITRD" "$ESP/EFI/mender-a/initrd.img"
    cp "$KERNEL" "$ESP/EFI/mender-b/linux.efi"; cp "$INITRD" "$ESP/EFI/mender-b/initrd.img"
EOSUDO
}
addtask mender_stage_esp after do_rootfs before do_image
# Needs real sudo (to read the root-owned EFI stub in the rootfs) -- ISAR enables
# it in a task via the [network] = TASK_USE_SUDO flag.
do_mender_stage_esp[network] = "${TASK_USE_SUDO}"

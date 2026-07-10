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

# From the Mender apt repo + Debian: the client, the UEFI slot-switch tool, and
# initramfs tooling (Debian's arm64 kernel is modular and needs an initrd).
IMAGE_PREINSTALL += " \
    mender-client4 \
    efibootmgr \
    initramfs-tools \
    ca-certificates \
    util-linux \
"

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

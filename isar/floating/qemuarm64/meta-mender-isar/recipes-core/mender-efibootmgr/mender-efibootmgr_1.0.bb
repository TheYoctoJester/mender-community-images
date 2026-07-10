# Mender A/B via UEFI boot entries (efibootmgr) for ISAR-built Debian.
#
# Ships, verbatim from meta-mender-community (verified run #2450, arm64-retargeted):
#   - the 'efibootmgr-rootfs' Mender Update Module (/usr/share/mender/modules/v3)
#   - the one-shot first-boot service that registers the two per-slot UEFI entries
#   - mender-data-persist (bind-mount /data/mender over /var/lib/mender so Mender
#     state survives the A/B rootfs swap)
#
# The UEFI boot manager itself is the slot selector: the firmware launches an
# EFI-stub kernel directly (no GRUB/U-Boot), the module sets BootNext for the
# trial boot and rewrites BootOrder on commit.
DESCRIPTION = "Mender A/B efibootmgr update module + first-boot provisioning + data persistence"
MAINTAINER = "Josef Holzmayr <jester@theyoctojester.info>"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${LAYERDIR_core}/licenses/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit dpkg-raw

SRC_URI = " \
    file://efibootmgr-rootfs \
    file://mender-efibootmgr-bootentry.sh \
    file://mender-efibootmgr-bootentry.service \
    file://mender-data-persist.conf \
    file://var-lib-mender.mount \
"

DEBIAN_DEPENDS = "mender-client4, efibootmgr, util-linux, bash, coreutils"

MENDER_MODULES_DIR = "/usr/share/mender/modules/v3"

do_install() {
    # Update module.
    install -d ${D}${MENDER_MODULES_DIR}
    install -m 0755 ${WORKDIR}/efibootmgr-rootfs ${D}${MENDER_MODULES_DIR}/efibootmgr-rootfs

    # First-boot provisioning script + service.
    install -d ${D}/usr/bin
    install -m 0755 ${WORKDIR}/mender-efibootmgr-bootentry.sh ${D}/usr/bin/mender-efibootmgr-bootentry.sh
    install -d ${D}/lib/systemd/system
    install -m 0644 ${WORKDIR}/mender-efibootmgr-bootentry.service ${D}/lib/systemd/system/mender-efibootmgr-bootentry.service

    # Data persistence: tmpfiles seed + bind-mount unit.
    install -d ${D}/usr/lib/tmpfiles.d
    install -m 0644 ${WORKDIR}/mender-data-persist.conf ${D}/usr/lib/tmpfiles.d/mender-data-persist.conf
    install -m 0644 ${WORKDIR}/var-lib-mender.mount ${D}/lib/systemd/system/var-lib-mender.mount

    # Enable units statically (no running systemd in the build chroot). The
    # bootentry oneshot is WantedBy=multi-user.target; the bind-mount is
    # WantedBy=mender-authd.service and mender-updated.service.
    install -d ${D}/etc/systemd/system/multi-user.target.wants
    ln -sf /lib/systemd/system/mender-efibootmgr-bootentry.service \
        ${D}/etc/systemd/system/multi-user.target.wants/mender-efibootmgr-bootentry.service
    install -d ${D}/etc/systemd/system/mender-authd.service.wants
    install -d ${D}/etc/systemd/system/mender-updated.service.wants
    ln -sf /lib/systemd/system/var-lib-mender.mount \
        ${D}/etc/systemd/system/mender-authd.service.wants/var-lib-mender.mount
    ln -sf /lib/systemd/system/var-lib-mender.mount \
        ${D}/etc/systemd/system/mender-updated.service.wants/var-lib-mender.mount
}

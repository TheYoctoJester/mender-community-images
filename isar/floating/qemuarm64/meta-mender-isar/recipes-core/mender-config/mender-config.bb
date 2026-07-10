# Mender client configuration + device identity for the ISAR A/B demo.
#
# The efibootmgr-rootfs update module owns A/B slot selection, so mender.conf
# does NOT carry RootfsPartA/B (that is only for the stock rootfs-image module).
# mender.conf/device_type/artifact_info are written from the postinst (which runs
# after mender-setup is configured) rather than shipped as files, to avoid a dpkg
# conffile conflict with mender-setup's own /etc/mender/mender.conf. The tenant
# token comes from the MENDER_TENANT_TOKEN bitbake variable (via kas env:), and is
# templated into the postinst; never committed.
DESCRIPTION = "Mender client config, device identity and base networking for the ISAR A/B demo"
MAINTAINER = "Josef Holzmayr <jester@theyoctojester.info>"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${LAYERDIR_core}/licenses/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit dpkg-raw

SRC_URI = " \
    file://10-dhcp.network \
    file://postinst.tmpl \
"

# The postinst is templated so the server/token/identity bake in.
TEMPLATE_FILES = "postinst.tmpl"
TEMPLATE_VARS = "MENDER_SERVER_URL MENDER_TENANT_TOKEN MENDER_ARTIFACT_NAME MENDER_DEVICE_TYPE"

DEBIAN_DEPENDS = "mender-client4, systemd, passwd"

# Demo identity / server. Overridable from the environment via kas.
MENDER_SERVER_URL ?= "https://hosted.mender.io"
MENDER_DEVICE_TYPE ?= "qemuarm64-isar"
MENDER_ARTIFACT_NAME ?= "isar-ab-v1"
MENDER_TENANT_TOKEN ??= ""

do_install() {
    # Base networking (DHCP via systemd-networkd). Everything else is written by
    # the postinst to avoid conffile conflicts with the Mender client packages.
    install -d ${D}/etc/systemd/network
    install -m 0644 ${WORKDIR}/10-dhcp.network ${D}/etc/systemd/network/10-dhcp.network
}

SUMMARY = "networkctl matcher config for bringing up wlan*"

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
	file://wlan.network \
"

RDEPENDS:${PN} = "systemd wpa-supplicant"

do_install() {
	install -d 755 ${D}${sysconfdir}/systemd
	install -d 755 ${D}${sysconfdir}/systemd/network
	install -m 644 ${WORKDIR}/wlan.network ${D}${sysconfdir}/systemd/network/wlan.network
}

FILES_${PN} = " \
	${sysconfdir}/systemd/network/wlan.network \
"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

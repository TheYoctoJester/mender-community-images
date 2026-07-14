SUMMARY = "Demo WiFi credentials: wpa_supplicant network config plus systemd-networkd DHCP"
DESCRIPTION = "Bakes SSID/passkey for a wireless interface into the image: a \
wpa_supplicant config generated from DEMO_WIFI_SSID/DEMO_WIFI_PASSKEY, a \
systemd-networkd DHCP matcher for wlan interfaces, and the enablement of the \
wpa_supplicant@ template unit shipped (disabled) by the wpa-supplicant recipe. \
Demo/lab use only: the passkey is stored in plaintext in the image."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
	file://wpa_supplicant.conf.in \
	file://25-wlan.network \
"

DEMO_WIFI_SSID ?= "Demo_SSID"
DEMO_WIFI_PASSKEY ?= "Demo_Password"
DEMO_WIFI_INTERFACE ?= "wlan0"

RDEPENDS:${PN} = "wpa-supplicant systemd"

inherit features_check
REQUIRED_DISTRO_FEATURES = "systemd"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
	install -d ${D}${sysconfdir}/wpa_supplicant
	sed -e 's#[@]DEMO_WIFI_SSID[@]#${DEMO_WIFI_SSID}#' \
	    -e 's#[@]DEMO_WIFI_PASSKEY[@]#${DEMO_WIFI_PASSKEY}#' \
	    ${WORKDIR}/wpa_supplicant.conf.in \
	    > ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-${DEMO_WIFI_INTERFACE}.conf
	chmod 0600 ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-${DEMO_WIFI_INTERFACE}.conf

	install -d ${D}${sysconfdir}/systemd/network
	install -m 0644 ${WORKDIR}/25-wlan.network ${D}${sysconfdir}/systemd/network/

	# wpa-supplicant ships the template unit disabled; enable our instance the
	# same way `systemctl enable` would.
	install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants
	ln -s ${systemd_system_unitdir}/wpa_supplicant@.service \
	    ${D}${sysconfdir}/systemd/system/multi-user.target.wants/wpa_supplicant@${DEMO_WIFI_INTERFACE}.service
}

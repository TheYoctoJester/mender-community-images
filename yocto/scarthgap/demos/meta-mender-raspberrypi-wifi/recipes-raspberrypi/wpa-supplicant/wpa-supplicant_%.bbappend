FILESEXTRAPATHS:prepend:mender-systemd := "${THISDIR}/files:"

SRC_URI:append:mender-systemd = " file://wpa_supplicant-wlan0.conf"

FILES:${PN}:append:mender-systemd = " /data/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf"

DEMO_WIFI_SSID ?= "ssid"
DEMO_WIFI_PASSKEY ?= "password"

do_install:append:mender-systemd() {
  install -d ${D}${sysconfdir}/wpa_supplicant

  sed -i -e 's#[@]DEMO_WIFI_PASSKEY[@]#${DEMO_WIFI_PASSKEY}#' ${WORKDIR}/wpa_supplicant-wlan0.conf
  sed -i -e 's#[@]DEMO_WIFI_SSID[@]#${DEMO_WIFI_SSID}#' ${WORKDIR}/wpa_supplicant-wlan0.conf

  install -d ${D}/data
  install -d ${D}/data/wpa_supplicant
  install -m 0755 ${WORKDIR}/wpa_supplicant-wlan0.conf ${D}/data/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf
  ln -s /data/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf

  # Make sure the system directory for systemd exists.
  install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants/

  # Link the service file for autostart.
  ln -s ${systemd_unitdir}/system/wpa_supplicant-nl80211@.service \
  ${D}${sysconfdir}/systemd/system/multi-user.target.wants/wpa_supplicant-nl80211@wlan0.service
}

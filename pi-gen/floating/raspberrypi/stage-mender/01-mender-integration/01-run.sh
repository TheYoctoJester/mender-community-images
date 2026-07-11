#!/bin/bash -e
# Install the tryboot A/B Mender integration into the rootfs (host-side).
: "${MENDER_SERVER_URL:=https://hosted.mender.io}"
: "${MENDER_TENANT_TOKEN:=}"
: "${MENDER_DEVICE_TYPE:=raspberrypi-pigen}"
: "${MENDER_ARTIFACT_NAME:=pigen-ab-v1}"

R="${ROOTFS_DIR}"

# Reused, build-system-agnostic pieces from meta-mender-raspberrypi-tryboot +
# meta-mender-demos-common: the tryboot A/B update module, the data partition mount,
# and data-persistence (seed /data/mender + bind-mount it over /var/lib/mender).
install -d "$R/usr/share/mender/modules/v3"
install -m 0755 files/rpi-tryboot-rootfs "$R/usr/share/mender/modules/v3/rpi-tryboot-rootfs"
install -d "$R/lib/systemd/system"
install -m 0644 files/data.mount           "$R/lib/systemd/system/data.mount"
install -m 0644 files/var-lib-mender.mount "$R/lib/systemd/system/var-lib-mender.mount"
install -d "$R/usr/lib/tmpfiles.d"
install -m 0644 files/mender-data-persist.conf "$R/usr/lib/tmpfiles.d/mender-data-persist.conf"

# mender.conf (no RootfsPartA/B -- the tryboot module owns slot selection) + identity.
install -d "$R/etc/mender" "$R/var/lib/mender"
cat > "$R/etc/mender/mender.conf" <<EOF
{
  "ServerURL": "${MENDER_SERVER_URL}",
  "TenantToken": "${MENDER_TENANT_TOKEN}",
  "UpdatePollIntervalSeconds": 5,
  "InventoryPollIntervalSeconds": 5,
  "RetryPollIntervalSeconds": 30
}
EOF
echo "artifact_name=${MENDER_ARTIFACT_NAME}" > "$R/etc/mender/artifact_info"
echo "device_type=${MENDER_DEVICE_TYPE}"     > "$R/var/lib/mender/device_type"

# Enable the persistence units (mender-client4's own services are enabled by its
# Debian postinst). data.mount -> local-fs.target; var-lib-mender.mount -> mender.
install -d "$R/etc/systemd/system/local-fs.target.wants"
ln -sf /lib/systemd/system/data.mount \
    "$R/etc/systemd/system/local-fs.target.wants/data.mount"
install -d "$R/etc/systemd/system/mender-authd.service.wants" \
          "$R/etc/systemd/system/mender-updated.service.wants"
ln -sf /lib/systemd/system/var-lib-mender.mount \
    "$R/etc/systemd/system/mender-authd.service.wants/var-lib-mender.mount"
ln -sf /lib/systemd/system/var-lib-mender.mount \
    "$R/etc/systemd/system/mender-updated.service.wants/var-lib-mender.mount"

# Enable the UART serial console (RPi OS leaves it off by default) so the lab
# hardware harness can watch the boot, and drop pi-gen's first-boot resize (our
# tryboot A/B layout is fixed -- no root-partition grow). config.txt/cmdline.txt
# here seed both boot FATs in assemble-tryboot-image.sh (which sets root= per slot).
CFG="$R/boot/firmware/config.txt"
CMD="$R/boot/firmware/cmdline.txt"
if [ -f "$CFG" ]; then
    # enable_uart=1 + disable-bt: route serial0 to the stable PL011 (ttyAMA0) at
    # 115200 instead of the mini-UART (whose baud drifts and garbles the console
    # the lab harness watches).
    grep -q '^enable_uart=1'          "$CFG" || printf '\n# Serial console for the lab UART\nenable_uart=1\n' >> "$CFG"
    grep -q '^dtoverlay=disable-bt'   "$CFG" || echo 'dtoverlay=disable-bt' >> "$CFG"
fi
if [ -f "$CMD" ]; then sed -i 's/[[:space:]]\+resize[[:space:]]*$//; s/ init=[^ ]*//g' "$CMD"; fi

# Note: no boot-file staging needed -- the pi-gen rootfs /boot already holds the
# kernel + DTBs, which is what the tryboot update module overlays onto the inactive
# boot FAT (the firmware base -- config.txt, start*.elf, kernel_*.img -- comes from
# the active boot FAT the module copies first). The RPi boot FAT itself (config.txt,
# cmdline.txt, kernel_*.img) is populated from the pi-gen image in assemble-tryboot-image.sh.

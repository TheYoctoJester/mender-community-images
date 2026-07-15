#!/bin/bash
# Build the complete Arduino Uno Q Debian + Mender A/B deliverable set:
#
#   1. upstream rootfs recipe            -> rootfs.tar, dtbs.tar.gz
#   2. uno-q-mender.yaml (this tree)     -> rootfs.tar (Mender + A/B integration)
#   3. upstream image recipe             -> disk-sdcard.img, .img1 (ESP), .img2 (rootfs ext4)
#   3b. fstab fix on .img2               -> stable PARTLABEL-based fstab (see below)
#   4. make-flash-ab.sh                  -> flash_uno-q_emmc-ab/ (EDL/qdl set)
#   5. make-artifact.sh                  -> <artifact-name>.mender
#
# Requirements: debos (with fakemachine), e2fsprogs (debugfs/e2fsck), mtools,
# dosfstools, unzip, curl, git, mender-artifact. Run it inside the
# build-qcom-deb builder container or on a host with those installed.
#
# Environment:
#   MENDER_TENANT_TOKEN  (required) hosted Mender tenant token
#   DEVICE_TYPE          default uno-q-debian
#   ARTIFACT_NAME        default unoq-debian-v1
#   SERVER_URL           default https://hosted.mender.io
#   WIFI_SSID/WIFI_PSK   optional, lab builds only — bakes WiFi credentials and
#                        unexpires the debian user; never set in CI
#   DEBOS_BACKEND        kvm (default if /dev/kvm exists) or qemu
#   IMAGESIZE            default 5640MiB (=> rootfs partition ~5120MiB, the A/B
#                        slot size)
#   KEEP_ROOTFS=1        reuse the stage-1 rootfs from a previous run (cached
#                        as rootfs-base.tar) — iteration aid
set -euo pipefail

WORK="${1:?usage: build-uno-q.sh <workdir> <qcom-deb-images-dir> <qcom-ptool-dir>}"
QCOM_DEB_IMAGES="${2:?qcom-deb-images checkout required}"
QCOM_PTOOL="${3:?qcom-ptool checkout required}"

: "${MENDER_TENANT_TOKEN:?MENDER_TENANT_TOKEN is required}"
DEVICE_TYPE="${DEVICE_TYPE:-uno-q-debian}"
ARTIFACT_NAME="${ARTIFACT_NAME:-unoq-debian-v1}"
SERVER_URL="${SERVER_URL:-https://hosted.mender.io}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PSK="${WIFI_PSK:-}"
IMAGESIZE="${IMAGESIZE:-5640MiB}"
# A/B slot size from partitions-ab-append.conf (5242880KB); .img2 must fit
SLOT_BYTES=$((5242880 * 1024))

HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
QCOM_DEB_IMAGES="$(cd "$QCOM_DEB_IMAGES" && pwd)"
QCOM_PTOOL="$(cd "$QCOM_PTOOL" && pwd)"

if [ -z "${DEBOS_BACKEND:-}" ]; then
    if [ -e /dev/kvm ]; then DEBOS_BACKEND=kvm; else
        echo "WARNING: /dev/kvm not available, falling back to the (slow) qemu backend" >&2
        DEBOS_BACKEND=qemu
    fi
fi

# keep debos/fakemachine scratch off any inherited TMPDIR
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

DEBOS="debos --fakemachine-backend $DEBOS_BACKEND --memory 2GiB --scratchsize 12GiB --artifactdir $WORK"

echo "=== stage 1: upstream rootfs (Debian trixie arm64) ==="
if [ "${KEEP_ROOTFS:-0}" = "1" ] && [ -f "$WORK/rootfs-base.tar" ]; then
    echo "reusing cached rootfs-base.tar"
else
    $DEBOS "$QCOM_DEB_IMAGES/debos-recipes/qualcomm-linux-debian-rootfs.yaml"
    cp "$WORK/rootfs.tar" "$WORK/rootfs-base.tar"
fi
cp "$WORK/rootfs-base.tar" "$WORK/rootfs.tar"

echo "=== stage 2: Mender + qbootctl A/B integration ==="
MENDER_ARGS=(
    -t "tenant_token:$MENDER_TENANT_TOKEN"
    -t "device_type:$DEVICE_TYPE"
    -t "artifact_name:$ARTIFACT_NAME"
    -t "server_url:$SERVER_URL"
)
if [ -n "$WIFI_SSID" ]; then
    MENDER_ARGS+=( -t "wifi_ssid:$WIFI_SSID" -t "wifi_psk:$WIFI_PSK" )
fi
$DEBOS "${MENDER_ARGS[@]}" "$HERE/uno-q-mender.yaml"

echo "=== stage 3: upstream disk image (sdcard/eMMC variant) ==="
$DEBOS -t imagetype:sdcard -t "imagesize:$IMAGESIZE" \
    "$QCOM_DEB_IMAGES/debos-recipes/qualcomm-linux-debian-image.yaml"

img2_size=$(stat -c %s "$WORK/disk-sdcard.img2")
if [ "$img2_size" -gt "$SLOT_BYTES" ]; then
    echo "ERROR: disk-sdcard.img2 ($img2_size bytes) exceeds the A/B slot size ($SLOT_BYTES bytes)" >&2
    exit 1
fi
if [ "$img2_size" -lt $((SLOT_BYTES - 16 * 1024 * 1024)) ]; then
    echo "ERROR: disk-sdcard.img2 ($img2_size bytes) is unexpectedly small — image layout changed?" >&2
    exit 1
fi

echo "=== stage 3b: rewrite fstab in disk-sdcard.img2 for A/B ==="
# The upstream image recipe writes a UUID-based fstab (setup-fstab: true). The
# filesystem UUIDs change on every build, but an OTA only replaces the rootfs
# slot — the device's ESP keeps its original UUID forever, so a v2 rootfs
# referencing its own build's ESP UUID would fail to mount /boot/efi and drop
# to emergency mode (the exact failure mode the debos qemuarm64 demo hit).
# Replace it with a build-independent PARTLABEL-based fstab: no "/" entry (root
# comes from the initramfs abslot override), ESP by its GPT label from the
# ptool table, and the persistent /data. Edited offline with debugfs — no loop
# devices, and the same edited image feeds both the EDL flash and the .mender
# artifact.
cat > "$WORK/fstab-ab" <<'FSTAB'
# A/B (Mender/qbootctl): build-independent, PARTLABEL-based. No "/" entry —
# the initramfs abslot script selects and mounts the active system_<slot>.
PARTLABEL=efi /boot/efi vfat nosuid,nodev,noexec,relatime,nosymfollow,fmask=0177,dmask=0077,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro,nofail 0 2
PARTLABEL=userdata /data ext4 defaults,nofail,x-systemd.makefs,x-systemd.growfs 0 2
FSTAB
debugfs -w -f - "$WORK/disk-sdcard.img2" <<EOF
rm /etc/fstab
write $WORK/fstab-ab /etc/fstab
EOF
# validate the edited filesystem and the result
e2fsck -fp "$WORK/disk-sdcard.img2" || [ $? -le 1 ]
fstab_now="$(debugfs -R "cat /etc/fstab" "$WORK/disk-sdcard.img2" 2>/dev/null)"
echo "$fstab_now" | grep -q "PARTLABEL=userdata" || {
    echo "ERROR: fstab rewrite failed — userdata entry missing" >&2
    exit 1
}
echo "$fstab_now" | grep -q "UUID=" && {
    echo "ERROR: fstab rewrite failed — UUID entry still present" >&2
    exit 1
}

echo "=== stage 4: EDL flash directory ==="
"$HERE/make-flash-ab.sh" "$WORK" "$QCOM_DEB_IMAGES" "$QCOM_PTOOL" "$ARTIFACT_NAME"

echo "=== stage 5: Mender artifact ==="
"$HERE/make-artifact.sh" "$WORK/disk-sdcard.img2" "$ARTIFACT_NAME" \
    "$WORK/$ARTIFACT_NAME.mender" "$DEVICE_TYPE"

echo
echo "=== outputs in $WORK ==="
echo "  disk-sdcard.img2          rootfs ext4 (A/B slot payload, fstab-fixed)"
echo "  disk-sdcard.img1          ESP"
echo "  flash_uno-q_emmc-ab/      EDL flash set (qdl; keep as sibling of the imgs)"
echo "  $ARTIFACT_NAME.mender     OTA artifact (module qbootctl-rootfs)"
echo "  disk-sdcard.img           full build image — NOT for flashing (pre-fstab-fix)"

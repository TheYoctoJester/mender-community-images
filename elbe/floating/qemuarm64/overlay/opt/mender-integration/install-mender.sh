#!/bin/sh
# Install + configure the Mender client in the target rootfs (ELBE finetuning).
# Adds the Mender APT repo, installs mender-client4, and writes the client config
# (incl. RootfsPartA/B, which the rootfs-image update module requires). The tenant
# token is read from a file injected via the overlay at build time (removed with
# the rest of /opt/mender-integration in the finetuning cleanup).
set -eu

SUITE=trixie
SERVER_URL="https://hosted.mender.io"
DEVICE_TYPE="qemuarm64-elbe"
ARTIFACT_NAME="elbe-ab-v1"
TOKEN_FILE=/opt/mender-integration/tenant-token

arch="$(dpkg --print-architecture)"
curl -fsSL https://downloads.mender.io/repos/debian/gpg \
    -o /etc/apt/trusted.gpg.d/mender.asc
echo "deb [arch=${arch}] https://downloads.mender.io/repos/device-components debian/${SUITE}/stable main" \
    > /etc/apt/sources.list.d/mender.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mender-client4
systemctl enable mender-updated.service 2>/dev/null || true
systemctl enable mender-authd.service 2>/dev/null || true

TENANT_TOKEN="$(cat "${TOKEN_FILE}" 2>/dev/null || echo dummy)"
install -d -m 755 /etc/mender /var/lib/mender
cat > /etc/mender/mender.conf <<EOF
{
  "ServerURL": "${SERVER_URL}",
  "TenantToken": "${TENANT_TOKEN}",
  "RootfsPartA": "/dev/vda2",
  "RootfsPartB": "/dev/vda3",
  "UpdatePollIntervalSeconds": 5,
  "InventoryPollIntervalSeconds": 5,
  "RetryPollIntervalSeconds": 30
}
EOF
echo "device_type=${DEVICE_TYPE}" > /var/lib/mender/device_type
echo "artifact_name=${ARTIFACT_NAME}" > /etc/mender/artifact_info

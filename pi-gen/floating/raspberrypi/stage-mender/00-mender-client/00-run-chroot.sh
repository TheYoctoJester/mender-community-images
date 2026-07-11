#!/bin/bash -e
# Install the Mender client (mender-client4) from the Mender device-components apt
# repo, inside the target arm64 chroot (network via qemu-user).

curl -fsSL https://downloads.mender.io/repos/debian/gpg \
    -o /etc/apt/trusted.gpg.d/mender.asc

cat > /etc/apt/sources.list.d/mender.list <<EOF
deb [arch=arm64] https://downloads.mender.io/repos/device-components debian/trixie/stable main
EOF

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mender-client4

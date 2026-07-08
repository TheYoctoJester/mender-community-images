#!/bin/sh
# Base system configuration for the debos Debian A/B Mender demo (qemuarm64).
# Runs chrooted in the target rootfs.
set -eu

echo "debos-mender" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   debos-mender
EOF

# Demo login on the serial console for debugging; not required for the OTA test.
echo 'root:mender' | chpasswd

# Networking: systemd-networkd + DHCP on the virtio NIC (qemu slirp gives a lease
# and outbound NAT to hosted.mender.io).
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-dhcp.network <<EOF
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# grub-mender-grubenv boots (active-rootfs)/boot/vmlinuz + /boot/initrd.img.
# Debian keeps only versioned names in /boot, so create the stable symlinks.
kver="$(ls /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -n1)"
if [ -n "${kver:-}" ]; then
    ln -sf "vmlinuz-${kver}" /boot/vmlinuz
    ln -sf "initrd.img-${kver}" /boot/initrd.img
else
    echo "ERROR: no /boot/vmlinuz-* kernel found" >&2
    exit 1
fi

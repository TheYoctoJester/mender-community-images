#!/bin/sh
# System configuration for the ELBE Debian A/B Mender demo (qemuarm64).
# Runs in the target chroot (ELBE finetuning). Hostname / root password / serial
# console are set by ELBE (<hostname>/<passwd>/<console>); this only adds DHCP
# networking and the kernel/initrd symlinks grub-mender-grubenv expects.
set -eu

# Demo login on the serial console for debugging (not required for the OTA test).
echo 'root:mender' | chpasswd

# Networking: systemd-networkd + DHCP on the virtio NIC (qemu slirp -> outbound
# NAT to hosted.mender.io).
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-dhcp.network <<EOF
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service 2>/dev/null || true
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

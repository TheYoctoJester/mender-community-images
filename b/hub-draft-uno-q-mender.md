# A/B system updates on the Arduino Uno Q with Mender

The Arduino Uno Q pairs a Qualcomm Dragonwing QRB2210 running Linux with an STM32U585 microcontroller on a single board. That makes it an interesting target for robust OTA updates: the Qualcomm boot chain already ships a native A/B slot mechanism (ABL plus `qbootctl`), so instead of retrofitting Mender's classic dual-rootfs layout with U-Boot or GRUB integration, the Mender integration for this board reuses the platform's own slots and drives them from a custom Update Module. The integration lives upstream in `meta-mender-community` (layer `meta-mender-qcom`, branch `wrynose`).

This tutorial walks through the full cycle on real hardware: building the image with kas, WiFi credentials included, flashing the board over Qualcomm EDL with `qdl`, verifying the device against Hosted Mender, and finally deploying an A/B rootfs update.

## Step 0: Prerequisites

Before we start, make sure you have:

- An Arduino Uno Q, a USB-C data cable, and a jumper for the `JCTL` pins
- A Linux build host with [kas](https://kas.readthedocs.io) installed, plus the usual Yocto host packages, and roughly 100 GB of free disk space
- A [Hosted Mender](https://hosted.mender.io) account (the free trial is sufficient)
- The `qdl` flashing tool, built from source:

```
sudo apt install libxml2-dev libusb-1.0-0-dev
git clone https://github.com/linux-msm/qdl
cd qdl && make
```

For flashing without root privileges, add a udev rule for the Qualcomm EDL USB id:

```
# /etc/udev/rules.d/51-uno-q-edl.rules
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", ATTR{idProduct}=="9008", MODE="0666"
```

One host-side gotcha: the kernel `qcserial` module claims the EDL interface and breaks `qdl` with `failed to read sahara request from device`. If you hit that, blacklist it:

```
# /etc/modprobe.d/blacklist-uno-q-qcserial.conf
blacklist qcserial
blacklist qmi_wwan
```

## Step 1: Get the build configuration and add your site settings

The kas configuration for the board lives in the [mender-community-images](https://github.com/theyoctojester/mender-community-images) repository:

```
git clone https://github.com/theyoctojester/mender-community-images
cd mender-community-images
```

The committed configuration deliberately contains neither a server URL, nor a tenant token, nor network credentials — all of that is site-specific. Create a small overlay file `my-site.yml` in the repository root that carries yours:

```
header:
  version: 14

local_conf_header:
  my-site: |
    MENDER_SERVER_URL = "https://hosted.mender.io"
    MENDER_TENANT_TOKEN = "<your tenant token>"
    DEMO_WIFI_SSID = "<your ssid>"
    DEMO_WIFI_PASSKEY = "<your passphrase>"
```

You find the tenant token on Hosted Mender under *Organization and billing*. The `DEMO_WIFI_*` variables are consumed by the `meta-mender-wifi` demo layer, which the wifi variant of the board configuration pulls in — more on that in the next step.

## Step 2: Build

```
kas build yocto/wrynose/floating/uno-q-wifi.yml:my-site.yml
```

This composes the Qualcomm BSP (`meta-qcom` and `meta-qcom-3rdparty`, which provide the `uno-q` machine, kernel and boot firmware), `meta-mender-core` on the `wrynose` branch, and the `meta-mender-qcom` integration layer, then builds `core-image-base`. Expect a first build to take an hour or more; incremental builds are much faster.

The `-wifi` variant extends the plain `uno-q.yml` with the `meta-mender-wifi` demo layer. Its single `demo-wifi` package generates `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` from the `DEMO_WIFI_*` variables at build time, adds a systemd-networkd DHCP configuration for `wlan*`, and enables the `wpa_supplicant@wlan0` service — the board comes up on your network on first boot, and stays connected across A/B deployments because every artifact built from this configuration carries the credentials. That is also the caveat: the passphrase is stored in plaintext in the image and in every artifact, so treat both as lab-internal and do not redistribute them. If that is not acceptable for your setup, build with the plain `uno-q.yml` and see step 3 for the alternative.

Besides the rootfs, the interesting output is the `qcomflash` directory:

```
build/tmp/deploy/images/uno-q/core-image-base-uno-q.qcomflash/
```

It contains the complete eMMC provisioning set: the Firehose programmer (`prog_firehose_ddr.elf`), the partition table description (`rawprogram0.xml`, `patch0.xml`), the boot chain, and the rootfs. The GPT it describes is the A/B variant provided by the integration layer: `system_a` and `system_b` for the OS, `dtbo_a`/`dtbo_b` (required by `qbootctl`), and a `userdata` partition that ends up mounted at `/data` for persistent Mender state. Both system slots are provisioned from the same `rootfs.img`, and `patch0.xml` grows `userdata` to the real eMMC size at flash time.

## Step 3: Alternative — keep the credentials out of the build

Baking WLAN credentials is convenient, but there are setups where they must not appear in a build configuration at all: they end up in artifacts, build history, and CI logs. In that case, build with the plain `uno-q.yml` (no `DEMO_WIFI_*` in `my-site.yml` needed) and inject the credentials into the finished image, right before flashing. Since both slots are provisioned from the same `rootfs.img`, a single injection gives both slots connectivity. If you built the wifi variant in step 2, skip ahead to step 4.

The image already contains `wpa_supplicant` and `systemd-networkd`; all that is missing is a network block, a DHCP configuration, and enabling the service — the same three pieces the demo layer installs at build time. Loop-mount the rootfs from the `qcomflash` directory:

```
cd build/tmp/deploy/images/uno-q/core-image-base-uno-q.qcomflash
mkdir -p mnt
sudo mount -o loop rootfs.img mnt
```

Create the wpa_supplicant configuration for `wlan0`:

```
sudo mkdir -p mnt/etc/wpa_supplicant
wpa_passphrase "MY_SSID" "MY_PASSPHRASE" | \
    sudo tee mnt/etc/wpa_supplicant/wpa_supplicant-wlan0.conf > /dev/null
```

Configure DHCP on the interface:

```
sudo tee mnt/etc/systemd/network/25-wlan0.network > /dev/null <<'EOF'
[Match]
Name=wlan0

[Network]
DHCP=yes
EOF
```

Enable `wpa_supplicant@wlan0` the same way `systemctl enable` would, by creating the symlink manually:

```
sudo ln -s /usr/lib/systemd/system/wpa_supplicant@.service \
    mnt/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service
sudo umount mnt
```

A note if the mount fails: the image is created with a current e2fsprogs and uses the `orphan_file` ext4 feature. Older host kernels or e2fsprogs releases do not know it. In that case, `debugfs -w` from e2fsprogs 1.47 or newer can perform the same three modifications (`mkdir`, `write`, `symlink`) without mounting at all — the build itself ships a suitable binary under `build/tmp/sysroots-components/x86_64/e2fsprogs-native/sbin/`.

One property of this injection approach to be aware of: the credentials live only in the flashed image. The first A/B deployment replaces the rootfs with one built from the artifact, and the injected files are gone — after that, the device needs another provisioning mechanism, or artifacts that carry their own connectivity setup. That trade-off is exactly why the baked approach from step 2 is the default for this tutorial's lab scenario.

## Step 4: Flash over EDL with qdl

The QRB2210 is flashed through Qualcomm's Emergency Download mode (EDL). To enter it: disconnect the board from power, set a jumper across the `JCTL` pins, and connect the USB-C cable. The board enumerates as a Qualcomm loader device:

```
lsusb | grep 05c6
Bus 001 Device 026: ID 05c6:9008 Qualcomm, Inc. Gobi Wireless Modem (QDL mode)
```

Flash the complete set from inside the `qcomflash` directory:

```
cd build/tmp/deploy/images/uno-q/core-image-base-uno-q.qcomflash
qdl --debug --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml
```

This writes all partitions and applies the GPT patches — around 25 seconds on USB high-speed. When `qdl` finishes, remove the `JCTL` jumper and re-plug the board; it now boots the freshly flashed system.

Two things worth knowing here. First, if a `qdl` run fails and you retry, always power-cycle into a *fresh* EDL session first — a half-used EDL session keeps failing with sahara errors. Second, `rawprogram0.xml` deliberately does not write any content to `userdata`, so reflashing preserves `/data`: a device that was already accepted on the Mender server keeps its identity and reappears without a new authorization request.

## Step 5: Verify against Hosted Mender

On first boot the device joins the WLAN, syncs its clock (the board has no RTC, and the TLS connection to the server only succeeds after `systemd-timesyncd` has done its job — give it a minute), and requests authorization. On Hosted Mender, the device shows up under *Devices* as pending, identified by its `wlan0` MAC address. Accept it.

Shortly after, the inventory fills in: `device_type: uno-q`, the kernel version, and the IP address on `wlan0`. The reported `artifact_name` is `unknown` at this point — expected, and worth understanding: this integration installs only the Mender client, not Mender's image-based artifact bookkeeping, so a system that was flashed rather than deployed has no artifact name to report. It gets one with the first successful deployment.

Since the image includes `mender-connect`, the *Remote Terminal* works too, which is handy to confirm the slot state:

```
# qbootctl -c
Current slot: _a
# cat /proc/cmdline | grep -o "root=[^ ]*"
root=PARTLABEL=system_a
```

A fresh flash always boots slot A.

## Step 6: Deploy an A/B update

Now for the actual point of the exercise. Make a change worth deploying — add a package to the image — and give the new state a name, both in `my-site.yml`:

```
    IMAGE_INSTALL:append = " htop"
    MENDER_ARTIFACT_NAME = "uno-q-v2"
```

Rebuild:

```
kas build yocto/wrynose/floating/uno-q-wifi.yml:my-site.yml
```

The build directly emits the deployable artifact — the uno-q configuration enables `meta-mender-qcom`'s artifact image type, which wraps the new rootfs for the `qbootctl-rootfs` update module:

```
build/tmp/deploy/images/uno-q/core-image-base-uno-q.mender
```

If you ever need to craft one by hand — say, for a rootfs that came out of a different build — the equivalent is `mender-artifact write module-image -T qbootctl-rootfs -n <name> -t uno-q -f <rootfs>.ext4` with the tool from [downloads.mender.io](https://docs.mender.io/downloads) or from `bitbake mender-artifact-native`.

Upload the `.mender` file on Hosted Mender under *Releases* and create a deployment targeting the device. The update module then does the slot dance: it streams the payload to the inactive slot (`system_b`), marks it active via `qbootctl`, and reboots. The slot-aware initramfs mounts the new slot, Mender verifies it is indeed running from the expected slot, and commits the update — only then is the new slot blessed as bootable. The deployment reports *Success*, and the device now shows `artifact_name: uno-q-v2` running from `PARTLABEL=system_b`.

If anything goes wrong — the payload does not boot, or verification fails — the mechanism rolls back: the initramfs detects the unbootable slot, switches back to the previous one, and the deployment ends in *Failure* with the device untouched on its known-good slot. It is worth provoking this once with a deliberately broken artifact just to watch it happen; confidence in the rollback path is the reason to use A/B updates in the first place.

## Conclusion

We built a Mender-enabled image for the Arduino Uno Q with WiFi credentials provisioned by the `meta-mender-wifi` demo layer (or injected post-build where they must stay out of the build), flashed it over EDL with `qdl`, and ran a complete A/B rootfs update including the commit handshake against Hosted Mender. The same Update-Module approach extends to the other updatable part of this board — the STM32U585 firmware, which the integration flashes over an internal SWD link — but that is a topic for a separate article.

---

*Version compatibility: Tested with the Yocto Project wrynose series, meta-mender-community `wrynose` (layer `meta-mender-qcom`), Mender client 5.1, and qdl against an Arduino Uno Q (QRB2210, 16 GB eMMC).*

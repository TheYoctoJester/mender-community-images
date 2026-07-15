# Board description

The Arduino Uno Q pairs a Qualcomm Dragonwing QRB2210 running Linux with an STM32U585 microcontroller on a single board. For OTA updates this is an interesting platform: the Qualcomm boot chain ships a native A/B slot mechanism (ABL plus `qbootctl`), so instead of retrofitting Mender's classic dual-rootfs layout with U-Boot or GRUB integration, the Mender integration reuses the platform's own slots and drives them from a custom Update Module (`qbootctl-rootfs`). The integration lives upstream in `meta-mender-community` (layer `meta-mender-qcom`, branch `wrynose`). A second update type covers the STM32U585 firmware over the board's internal SWD link (`zephyr-mcu` Update Module, built via the `mcu` multiconfig) — that part is not covered in this post; see the layer README.

TODO: Upload a board picture here.

* **Vendor URL:** [Arduino UNO Q](https://docs.arduino.cc/hardware/uno-q/)
* **Wiki:** [UNO Q user manual](https://docs.arduino.cc/tutorials/uno-q/user-manual/)
* **SoC / SoM:** Qualcomm Dragonwing QRB2210 (plus an STM32U585 Cortex-M33 coprocessor)
* **Yocto `MACHINE`:** `uno-q`
* **Config in `mender-community-images`:** `yocto/wrynose/floating/uno-q.yml` (variant with baked WiFi credentials: `uno-q-wifi.yml`; MCU firmware build: `uno-q-mcu-firmware.yml`)

# Test results

The Yocto Project releases in the table below have been tested by the Mender community. Please update it if you have tested this integration on other [Yocto Project releases](https://wiki.yoctoproject.org/wiki/Releases?target=_blank):

| Yocto Project | Build | Runtime |
|----|----|----|
| wrynose (6.0) | :test_works: | :test_works: |

**Build** means the Yocto Project build using this Mender integration completes without errors and produces images. **Runtime** means Mender has been verified to work on the board. This board does not use Mender's GRUB or U-Boot rootfs integration: it reuses the native Qualcomm A/B boot slots driven by the `qbootctl-rootfs` Update Module. Runtime was verified on hardware against Hosted Mender — full deployment with commit handshake, and rollback of a deliberately broken artifact.

The integration layer's `LAYERSERIES_COMPAT` is `wrynose`; older releases have not been tested and are not expected to work without adaptation.

# Getting started

The sections below cover the full cycle on real hardware: building the image (WiFi credentials included), flashing the board over Qualcomm EDL with `qdl`, verifying the device against Hosted Mender, and deploying an A/B rootfs update.

## Prerequisites

* A supported Linux distribution with the Yocto Project host dependencies installed, as described in the [Yocto Project reference manual](https://docs.yoctoproject.org/ref-manual/system-requirements.html#supported-linux-distributions), and roughly 100 GB of free disk space.
* [kas](https://kas.readthedocs.io/?target=_blank) installed and on your `PATH` (`pip install kas`), plus `git`.
* An Arduino Uno Q, a USB-C data cable, and a jumper for the EDL pins on the `JCTL` header.
* A [Hosted Mender](https://hosted.mender.io) account (the free trial is sufficient), or your own Mender server.
* The `qdl` flashing tool — packaged in recent Debian and Ubuntu releases (`apt install qdl`), or built from source with Meson:

```
sudo apt install libxml2-dev libusb-1.0-0-dev libzip-dev meson ninja-build help2man
git clone https://github.com/linux-msm/qdl
cd qdl && meson setup build && meson compile -C build
```

The binary ends up in `build/`.

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

## Configuring the build

### Get the build configurations

```
git clone https://github.com/theyoctojester/mender-community-images
cd mender-community-images
```

Board configurations live under `yocto/<release>/{tagged,floating}/<TARGET>.yml`; `wrynose` currently ships floating configurations only (a `tagged/` tier will be added once upstream cuts `wrynose` branches for all referenced layers). This board's configurations are `yocto/wrynose/floating/uno-q.yml` and the `uno-q-wifi.yml` variant used below.

### Configure the Mender server and site settings

The committed configuration deliberately contains neither a server URL, nor a tenant token, nor real network credentials (the wifi variant carries obvious `Demo_SSID` placeholders only) — all of that is site-specific. A build without them is only suitable for [standalone deployments](https://docs.mender.io/artifact-creation/standalone-deployment?target=_blank). Create a small overlay file `my-site.yml` in the repository root that carries yours:

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

You find the tenant token on Hosted Mender under *Organization and billing* (for a regional instance, set `MENDER_SERVER_URL` accordingly — see [Regions](https://docs.mender.io/overview/hosted-mender-regions?target=_blank)). The `DEMO_WIFI_*` variables are consumed by the `meta-mender-wifi` demo layer, which the wifi variant of the board configuration pulls in — more on that in the next section.

Keep the section name `my-site`: kas writes `local_conf_header` sections into the generated `local.conf` in alphabetical order, not in the order the configuration files are listed, so an override only takes effect if its section sorts *after the sections whose values it overrides*. `my-site` sorts after `demo-wifi` and `mender-client`, which is exactly what is needed here; when in doubt, a `zz-` prefix settles the question.

### Building the image

```
kas build yocto/wrynose/floating/uno-q-wifi.yml:my-site.yml
```

This composes the Qualcomm BSP (`meta-qcom` and `meta-qcom-3rdparty`, which provide the `uno-q` machine, kernel and boot firmware), `meta-mender-core` on the `wrynose` branch, and the `meta-mender-qcom` integration layer, then builds `core-image-base` (this board's image target — not the community default `core-image-minimal`). Expect a first build to take an hour or more; incremental builds are much faster.

Be aware that the composition follows meta-qcom's CI defaults, and those include `allow-root-login` with an *empty root password*. That is convenient on the lab bench and indefensible anywhere else — harden the image before it leaves yours.

The `-wifi` variant extends the plain `uno-q.yml` with the `meta-mender-wifi` demo layer. Its single `demo-wifi` package generates `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` from the `DEMO_WIFI_*` variables at build time, adds a systemd-networkd DHCP configuration for `wlan*`, and enables the `wpa_supplicant@wlan0` service — the board comes up on your network on first boot, and stays connected across A/B deployments because every artifact built from this configuration carries the credentials. That is also the caveat: the passphrase is stored in plaintext in the image and in every artifact, so treat both as lab-internal and do not redistribute them. If that is not acceptable for your setup, build with the plain `uno-q.yml` and inject the credentials post-build instead (see below).

### Using the build output

After a successful build, the outputs are in `build/tmp/deploy/images/uno-q/`. Two of them matter here.

The `qcomflash` directory is what provisions the board (there is no dd-able disk image on this platform — see the flashing section):

```
build/tmp/deploy/images/uno-q/core-image-base-uno-q.qcomflash/
```

It contains the complete eMMC provisioning set: the Firehose programmer (`prog_firehose_ddr.elf`), the partition table description (`rawprogram0.xml`, `patch0.xml`), the boot chain — whose kernel image embeds a slot-aware initramfs that reads the active slot and mounts `system_<slot>` accordingly — and the rootfs. The GPT it describes is the A/B variant provided by the integration layer: `system_a`/`system_b` for the OS and `boot_a`/`boot_b` for the kernel, `dtbo_a`/`dtbo_b` (both `boot` and `dtbo` are hard-required by `qbootctl`'s slot switching), and a `userdata` partition that ends up mounted at `/data` for persistent Mender state — the device identity and the in-flight update bookkeeping that must survive the rootfs swap. Both system slots are provisioned from the same `rootfs.img` (and both boot slots from the same `boot.img`), and `patch0.xml` grows the `userdata` GPT entry to the real eMMC size at flash time; the filesystem in it is created and grown at first boot.

The second output is the deployable [Mender Artifact](https://docs.mender.io/overview/artifact?target=_blank) — the configuration enables `meta-mender-qcom`'s artifact image type, which wraps the rootfs for the `qbootctl-rootfs` update module:

```
build/tmp/deploy/images/uno-q/core-image-base-uno-q.mender
```

If you ever need to craft one by hand — say, for a rootfs that came out of a different build — the equivalent is `mender-artifact write module-image -T qbootctl-rootfs -n <name> -t uno-q -f <rootfs>.ext4 -o <name>.mender` with the tool from [Mender's downloads page](https://docs.mender.io/downloads) or from `bitbake mender-artifact-native`.

## Alternative: keep the WiFi credentials out of the build

Baking WLAN credentials is convenient, but there are setups where they must not appear in a build configuration at all: they end up in artifacts, build history, and CI logs. In that case, build with the plain `uno-q.yml` (no `DEMO_WIFI_*` in `my-site.yml` needed) and inject the credentials into the finished image, right before flashing. Since both slots are provisioned from the same `rootfs.img`, a single injection gives both slots connectivity. If you built the wifi variant, skip ahead to the flashing section.

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

(For a hidden SSID, add `scan_ssid=1` inside the `network` block — `wpa_passphrase` does not emit it.)

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

One property of this injection approach to be aware of: the credentials live only in the flashed image. The first A/B deployment replaces the rootfs with one built from the artifact, and the injected files are gone — after that, the device needs another provisioning mechanism, or artifacts that carry their own connectivity setup. That trade-off is exactly why the baked approach is the default here.

## Flashing over EDL with qdl

The QRB2210 is flashed through Qualcomm's Emergency Download mode (EDL). To enter it: disconnect the board from power, short `USB_BOOT` to `GND` on the `JCTL` header — those are the two pins furthest from the USB-C connector — and connect the USB-C cable. Short exactly those two: the rest of the header carries the 1.8 V debug UART and PMIC control lines. The board enumerates as a Qualcomm loader device:

```
lsusb | grep 05c6
Bus 001 Device 026: ID 05c6:9008 Qualcomm, Inc. Gobi Wireless Modem (QDL mode)
```

Flash the complete set from inside the `qcomflash` directory:

```
cd build/tmp/deploy/images/uno-q/core-image-base-uno-q.qcomflash
qdl --debug --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml
```

This writes all partitions and applies the GPT patches — around 25 seconds on USB high-speed. When `qdl` finishes, remove the jumper and re-plug the board; it now boots the freshly flashed system.

Two things worth knowing here. First, if a `qdl` run fails and you retry, always power-cycle into a *fresh* EDL session first — a half-used EDL session keeps failing with sahara errors. Second, `rawprogram0.xml` deliberately does not write any content to `userdata`, so as long as the partition layout is unchanged, reflashing preserves `/data`: a device that was already accepted on the Mender server keeps its identity and reappears without a new authorization request. (A reflash rewrites the GPT — `/data` survives because the new table places `userdata` at the identical sectors. Change the layout and that guarantee is gone.)

## Verifying the device

On first boot the device joins the WLAN, syncs its clock (the board has no RTC, and the TLS connection to the server only succeeds after `systemd-timesyncd` has done its job — give it a minute), and requests authorization. On Hosted Mender, the device shows up under *Devices* as pending, identified by its `wlan0` MAC address. Accept it.

Shortly after, the inventory fills in: `device_type: uno-q`, the kernel version, and the IP address on `wlan0`. The reported `artifact_name` is `unknown` at this point — expected, and worth understanding: this integration installs only the Mender client (plus `mender-connect`), not Mender's image-based artifact bookkeeping, so a system that was flashed rather than deployed has no artifact name to report. It gets one with the first successful deployment.

Since the image includes `mender-connect`, the *Remote Terminal* works too, which is handy to confirm the slot state:

```
# qbootctl -c 2>/dev/null
Current slot: _a
# mount | grep " / "
/dev/mmcblk0p75 on / type ext4 (rw,relatime)
# ls -l /dev/disk/by-partlabel/system_a
lrwxrwxrwx 1 root root 16 Jan  1  1970 /dev/disk/by-partlabel/system_a -> ../../mmcblk0p75
```

Without the `2>/dev/null`, up to three harmless warnings precede the output: `qbootctl` first looks for a `slot_suffix` kernel argument this platform does not pass, then falls back to the GPT active bit — and right after a fresh flash it warns about that too, because no slot has been marked active yet. That is also the honest answer to which slot a fresh flash boots: slot A, not because the flashed GPT marks it active (it marks nothing; no slot carries any A/B attribute after provisioning), but because slot A is the fallback every component agrees on. And one thing *not* to use as a slot check: `root=` in `/proc/cmdline`. It always shows `PARTLABEL=system_a` — that is the baked fallback, and the slot-aware initramfs overrides the actual root mount, not the kernel command line. `qbootctl -c` or the mounted device are the truth.

## Deploying an A/B update

Now for the actual point of the exercise. Make a change worth deploying — add a package to the image — and give the new state a name, both in `my-site.yml`:

```
    IMAGE_INSTALL:append = " htop"
    MENDER_ARTIFACT_NAME = "uno-q-v2"
```

Rebuild:

```
kas build yocto/wrynose/floating/uno-q-wifi.yml:my-site.yml
```

Upload the resulting `.mender` file on Hosted Mender under *Releases* and create a deployment targeting the device. The update module then does the slot dance: while downloading, it streams the payload straight to the inactive slot (`system_b`, on this first update); at install it marks that slot active via `qbootctl` — deactivating the old slot without touching its *successful* mark, which is what keeps the fallback safe — and lets Mender reboot; a failed download therefore never touches the slot state. After the reboot the slot-aware initramfs selects the new slot as root, Mender verifies the active slot is the one it installed, and commits it with `qbootctl -m`, marking the slot *successful* — the slot was bootable since install; the commit is what stops the boot chain's fallback logic from discarding it. The deployment reports *Success*, and the device now shows `artifact_name: uno-q-v2` running from `system_b` (verify with `qbootctl -c` or the mounted root device, as above — not `/proc/cmdline`).

If anything goes wrong, several safety nets stack up. A payload without a mountable filesystem is caught by the initramfs: it test-mounts the active slot, and on failure switches back to the previous slot *and commits it* — without that commit the boot chain would bounce straight back into the bad slot — then reboots. A slot that boots but fails Mender's verification is rolled back by the client itself. And a slot that mounts but never finishes booting is simply never marked successful, which per the BSP documentation makes the boot firmware itself fall back once its retry budget is spent — the one net of the three this integration's testing has not provoked on hardware. In every case the deployment ends in *Failure*, with the running system and `/data` untouched on the known-good slot (the inactive slot, of course, still holds the bad payload until the next deployment overwrites it). It is worth provoking the first case once with a deliberately broken artifact just to watch it happen; confidence in the rollback path is the reason to use A/B updates in the first place.

# References

* [Mender documentation](https://docs.mender.io/) — explains how Mender works; this board post is a complement to it.
* [`meta-mender-qcom` layer README](https://github.com/mendersoftware/meta-mender-community/tree/wrynose/meta-mender-qcom) — the integration described here, including the STM32U585 MCU update path.
* [`mender-community-images`](https://github.com/theyoctojester/mender-community-images) — the build configurations used above.
* [`meta-mender-community`](https://github.com/mendersoftware/meta-mender-community) — the Mender community integration layers.
* [Using kas to reproduce your Yocto builds](https://hub.mender.io/t/using-kas-to-reproduce-your-yocto-builds/6020) — kas introduction on Mender Hub.
* [Arduino: flash a Linux image on the UNO Q](https://docs.arduino.cc/tutorials/uno-q/update-image/) — the vendor's EDL flashing guide (JCTL/EDL pins).
* [`qdl`](https://github.com/linux-msm/qdl) — the EDL flashing tool.

# Known issues

* The image follows meta-qcom's CI defaults, including root login with an empty password — harden before deploying anywhere that matters.
* `qbootctl -c` prints up to three harmless warnings on this platform (no `slot_suffix` kernel argument, and no active bit right after provisioning); `root=` in `/proc/cmdline` always shows the baked `system_a` fallback and must not be used as a slot check.
* `/data` (device identity, Mender state) survives reflashing only while the partition layout is unchanged.
* The firmware-level rollback path (slot never marked successful → boot-firmware retry fallback) is documented by the BSP but has not been provoked on hardware as part of this integration's testing.

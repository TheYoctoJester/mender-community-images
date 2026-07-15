# Board description

The Arduino Uno Q pairs a Qualcomm Dragonwing QRB2210 running Linux with an STM32U585 microcontroller on a single board. The [main-system post](https://hub.mender.io/t/arduino-uno-q-main-system-yocto/8321) covers OTA updates for the Linux side through the platform's native A/B slots. This post covers the second update type: deploying Zephyr-based firmware to the STM32U585 companion MCU through Mender. The QRB2210 programs the STM32 over an internal SWD link (no external probe, no cables), which the `zephyr-mcu` Update Module drives with OpenOCD. The integration lives in the same upstream layer, `meta-mender-qcom` in `meta-mender-community` (branch `wrynose`).

![Arduino Uno Q, image source: arduino.cc|666x500](upload://3LotxDcvW7S1Be0iay0zgawjFTy.jpeg)

* **Vendor URL:** [Arduino UNO Q](https://docs.arduino.cc/hardware/uno-q/)
* **Wiki:** [UNO Q user manual](https://docs.arduino.cc/tutorials/uno-q/user-manual/)
* **MCU:** STM32U585 (Arm Cortex-M33)
* **Zephyr board:** `arduino_uno_q` (upstream since Zephyr 4.3)
* **Yocto `MACHINE`:** `arduino-uno-q`, built as the `mcu` multiconfig
* **Config in `mender-community-images`:** `yocto/wrynose/floating/uno-q-mcu-firmware.yml`

# Test results

The Yocto Project releases in the table below have been tested by the Mender community. Please update it if you have tested this integration on other [Yocto Project releases](https://wiki.yoctoproject.org/wiki/Releases?target=_blank):

| Yocto Project | Build | Runtime |
|----|----|----|
| wrynose (6.0) | :test_works: | :test_works: |

**Build** means the firmware builds without errors through the `mcu` multiconfig. **Runtime** means the resulting artifact has been deployed through Hosted Mender and verified on the board: the module flashed the firmware over the internal SWD link, the read-back verification passed, and a deliberately corrupt artifact was rejected and rolled back to the previous firmware.

# Getting started

The sections below cover building the Zephyr demo firmware, packaging it as a Mender Artifact, deploying it through Hosted Mender, verifying the result over SWD, and provoking a rollback.

## Prerequisites

* A provisioned Arduino Uno Q from the [main-system post](https://hub.mender.io/t/arduino-uno-q-main-system-yocto/8321): the board runs the `uno-q` image, is accepted on your Mender server, and that image already ships everything the device needs (OpenOCD with the `linuxgpiod` driver and the `zephyr-mcu` Update Module, via the `qcom-mcu` section of `uno-q.yml`).
* The same build host setup as the main post: Yocto host dependencies, [kas](https://kas.readthedocs.io/?target=_blank), `git`.
* No jumper, no `qdl`, no physical access: everything in this post happens through Mender over the network, and the flashing itself over the board-internal SWD link.

## Building the firmware

```
kas build yocto/wrynose/floating/uno-q-mcu-firmware.yml
```

This configuration extends the plain `uno-q.yml` with `meta-zephyr` (branch `wrynose`) and `meta-python`, and enables a second build configuration next to the Linux image: `BBMULTICONFIG = "mcu"`. The `mcu` multiconfig (shipped by the integration layer) sets `MACHINE = "arduino-uno-q"`, a Cortex-M33 machine building against newlib, and gives itself a separate `TMPDIR` (`tmp-mcu`), because the aarch64 and Cortex-M33 configurations would otherwise collide in the shared native tool workdirs. The build targets are the Linux image plus `mc:mcu:zephyr-unoq-blink`.

`zephyr-unoq-blink` is the demo firmware: a Zephyr application for the upstream `arduino_uno_q` board that blinks one of the user-programmable RGB LEDs (`led0` maps to the green channel of LED 3) and embeds a version marker in its read-only data, so the running firmware can be identified over SWD:

```
__attribute__((used, section(".rodata.fw_version")))
const char fw_version[] = "UNOQMCU:" FW_VERSION;
```

Two variables parameterize it, both overridable from your configuration overlay: `FW_VERSION` (default `unoq-mcu-v1`) and `BLINK_PERIOD_MS` (default `500`). The firmware lands in the multiconfig's own deploy directory:

```
build/tmp-mcu/deploy/images/arduino-uno-q/zephyr-unoq-blink-arduino-uno-q.hex
```

A quick sanity check that your version made it in:

```
strings build/tmp-mcu/deploy/images/arduino-uno-q/zephyr-unoq-blink-arduino-uno-q.bin | grep UNOQMCU
UNOQMCU:unoq-mcu-v1
```

## Creating the artifact

Unlike the rootfs, the MCU firmware is not wrapped automatically; package it with `mender-artifact` (from [Mender's downloads page](https://docs.mender.io/downloads) or from `bitbake mender-artifact-native`):

```
mender-artifact write module-image -T zephyr-mcu -n unoq-mcu-v1 -t uno-q \
    -f build/tmp-mcu/deploy/images/arduino-uno-q/zephyr-unoq-blink-arduino-uno-q.hex \
    -o unoq-mcu-v1.mender
```

The update type `zephyr-mcu` selects the Update Module on the device; the device type stays `uno-q`, so both rootfs and MCU artifacts target the same device. Current `mender-artifact` versions print a deprecation warning for `-t`; the successor flag is `--compatible-types uno-q`.

## Deploying through Mender

Upload the `.mender` file on Hosted Mender under *Releases* and create a deployment targeting the device. On the board, the `zephyr-mcu` module then does the following. It streams the payload to its work directory. On the first firmware deployment it also sets the STM32 boot option bytes (`nSWBOOT0=0`, `nBOOT0=1`) so the MCU boots from main flash regardless of the physical BOOT0 pin; this is checked and applied idempotently, so later deployments skip it. It then dumps the current 256 KiB of MCU flash to `/data/mcu-fw/previous.bin` as the rollback image, and programs the new firmware with `openocd program … verify reset` over the internal SWD link, which OpenOCD bit-bangs via `linuxgpiod` (TLMM `gpiochip1`, SWDIO on line 25, SWCLK on line 26). The health gate is the SWD read-back verification: only a "Verified OK" from OpenOCD lets the install step succeed.

The module answers `NeedsArtifactReboot: No`. Only the MCU resets into the new firmware; the Linux host stays up, and the deployment completes without a device reboot. The deployment reports *Success* shortly after the flashing finishes.

## Verifying

If you changed `BLINK_PERIOD_MS`, the LED gives instant visual feedback. For a rigorous check, read the version marker back over the same SWD link, on the device (Remote Terminal or ssh):

```
# openocd -f /usr/share/unoq-mcu/openocd_gpiod.cfg -c init -c halt \
    -c "dump_image /tmp/mcu-head.bin 0x08000000 0x10000" -c resume -c shutdown
# strings /tmp/mcu-head.bin | grep UNOQMCU
UNOQMCU:unoq-mcu-v1
```

The Mender bookkeeping is worth a look too:

```
# mender-update show-provides
rootfs-image.zephyr-mcu.version=unoq-mcu-v1
artifact_name=unoq-mcu-v1
```

Note that `artifact_name` reflects the most recent deployment of *any* type, so after an MCU deployment it names the MCU artifact even though the rootfs is unchanged. The per-type provides keys (`rootfs-image.qbootctl-rootfs.version` for the rootfs, `rootfs-image.zephyr-mcu.version` for the MCU) are the reliable per-part trackers.

For a second round, bump both knobs in your overlay (`my-site.yml` from the main post):

```
    FW_VERSION = "unoq-mcu-v2"
    BLINK_PERIOD_MS = "100"
```

Rebuild with the overlay in the chain, package as `unoq-mcu-v2`, deploy:

```
kas build yocto/wrynose/floating/uno-q-mcu-firmware.yml:my-site.yml
```

The LED visibly changes pace and the marker reads `UNOQMCU:unoq-mcu-v2`.

## Rollback

The rollback path deserves to be seen once. Create a deliberately broken payload by truncating the hex file, and package it:

```
head -c 10240 build/tmp-mcu/deploy/images/arduino-uno-q/zephyr-unoq-blink-arduino-uno-q.hex > broken.hex
mender-artifact write module-image -T zephyr-mcu -n unoq-mcu-bad -t uno-q \
    -f broken.hex -o unoq-mcu-bad.mender
```

Deploy it. OpenOCD parses the whole image before touching flash, so the truncated hex is rejected outright and nothing is written; the install step fails, and the module's rollback re-programs `/data/mcu-fw/previous.bin`. The deployment ends in *Failure*, and the marker still reads the previous version. Failures later in the process are covered as well: OpenOCD only resets the MCU after a successful read-back verification, so on a genuine mid-write failure the MCU stays halted until the rollback has restored the backup.

# References

* [Arduino UNO Q main system (Yocto)](https://hub.mender.io/t/arduino-uno-q-main-system-yocto/8321): the companion post this one builds on.
* [`meta-mender-qcom` layer README](https://github.com/mendersoftware/meta-mender-community/tree/wrynose/meta-mender-qcom): the integration, including the `zephyr-mcu` module internals.
* [Mender Update Modules](https://docs.mender.io/artifacts/update-modules): how non-rootfs update types work.
* [`mender-community-images`](https://github.com/theyoctojester/mender-community-images): the build configurations used above.
* [meta-zephyr](https://git.yoctoproject.org/meta-zephyr/): Zephyr integration for the Yocto Project.
* [Zephyr Project documentation](https://docs.zephyrproject.org/): the `arduino_uno_q` board has been upstream since Zephyr 4.3; this integration builds Zephyr 4.4.

# Known issues

* The SWD link is bit-banged through GPIO, so flashing and dumping are slow compared to a dedicated probe; expect the install step of a deployment to take a while.
* While applying the boot option bytes on the first deployment, OpenOCD prints a harmless `option load failed` message; the triggered reset drops the debugger connection, but the bytes are applied.
* OpenOCD leaves the two SWD GPIO lines configured as outputs after a session. This is harmless; the next session reconfigures them.
* There is no MCUboot and no signature verification on the MCU: the firmware is a plain image linked at flash base (0x08000000), and the SWD read-back verifies integrity, not authenticity. Treat the Mender server access as the trust boundary.
* The first deployment persistently (though reversibly, over SWD) changes the STM32 boot option bytes.
* The rollback depends on the backup at `/data/mcu-fw/previous.bin`. If that file is missing (for example after wiping `/data`), a failed installation leaves the MCU halted on the partial image until the next successful deployment.
* `artifact_name` is shared across update types; track the rootfs and MCU versions through their provides keys instead.
* The Cortex-M33 tune of current oe-core emits a `-mcpu=cortex-m33+dsp` flag that GCC 16 rejects; the `arduino-uno-q` machine configuration carries the workaround (`TUNE_CCARGS_MARCH_OPTS = ""`), so this only concerns you if you build the firmware outside the provided configuration.

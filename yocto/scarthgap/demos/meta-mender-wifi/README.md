# meta-mender-wifi

A small, board-agnostic demo layer that bakes WiFi credentials into an image.
It generalizes the former `meta-mender-raspberrypi-wifi` layer: no BSP-specific
recipes or appends, just one `demo-wifi` package that works on any machine with
working WLAN hardware/firmware, `wpa-supplicant`, and systemd + systemd-networkd.

## What it does

Adding the `demo-wifi` package to an image installs:

- `/etc/wpa_supplicant/wpa_supplicant-<iface>.conf` — generated at build time
  from `DEMO_WIFI_SSID` / `DEMO_WIFI_PASSKEY`
- `/etc/systemd/network/25-wlan.network` — DHCP on `wlan*` via systemd-networkd
- the enablement symlink for `wpa_supplicant@<iface>.service` (the template unit
  is shipped, disabled, by the openembedded-core `wpa-supplicant` recipe)

## Usage

Add the layer, then:

```
IMAGE_INSTALL:append = " demo-wifi"
DEMO_WIFI_SSID = "MyNetwork"
DEMO_WIFI_PASSKEY = "MyPassphrase"
```

`DEMO_WIFI_INTERFACE` (default `wlan0`) selects the interface instance.

The layer does not pull in WLAN firmware — that is a board concern and belongs
in the machine/BSP configuration (for Raspberry Pi boards this includes
accepting the `synaptics-killswitch` license, see the consuming kas files).

## A note on credentials

The passkey is stored in plaintext in the image and in every Mender artifact
built from this configuration — that is the point (a lab/demo device stays
connected across A/B deployments, unlike credentials injected into a flashed
image post-build), but it also means such images and artifacts must not be
redistributed. For production, provision credentials at runtime instead.

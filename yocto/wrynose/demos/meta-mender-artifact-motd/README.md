# meta-mender-artifact-motd

A one-class, board-agnostic demo layer that writes `MENDER_ARTIFACT_NAME`
into `/etc/motd`, so that two builds differing only in their artifact name
also differ on the device and an A/B switch or a rollback is visible.

## Usage

Add the layer and inherit the class:

```yaml
repos:
  mender-community-images:
    layers:
      yocto/wrynose/demos/meta-mender-artifact-motd:

local_conf_header:
  motd: |
    INHERIT += "artifact-motd"
```

Then build twice with different names, for instance by appending a small
local fragment that sets `MENDER_ARTIFACT_NAME`. Logging in on the device
shows `Mender image - <artifact name>`.

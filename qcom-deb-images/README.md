# qcom-deb-images-based Mender integrations

This tree holds Mender integrations for boards built with
[qcom-deb-images](https://github.com/qualcomm-linux/qcom-deb-images),
Qualcomm's official **Debian** image build for their Linux-capable SoCs — a
build-system axis parallel to `../yocto/` (Yocto/kas), `../debos/`,
`../pi-gen/` and `../mender-convert/`.

qcom-deb-images is itself debos-based, but unlike `../debos/` (which carries a
self-contained recipe) this tree consumes the *upstream recipes unmodified*, at
a pinned commit, and layers the Mender integration on top: an additional debos
stage between the upstream rootfs and image recipes, plus a replacement for the
upstream flash-directory generation that produces an A/B partition layout.

## Layout

```
qcom-deb-images/
  floating/            # tracks a pinned upstream commit, moved forward manually
    uno-q/
      build-uno-q.sh              # build wrapper (all stages)
      uno-q-mender.yaml           # the Mender debos stage
      make-flash-ab.sh            # A/B EDL flash-dir generator
      make-artifact.sh            # .mender artifact wrapper
      partitions-ab-append.conf   # A/B partition table block
      overlay/                    # files installed into the rootfs
```

(`tagged/` — pinned to upstream release tags — is added once upstream tags
releases usable for this.)

## uno-q

Arduino Uno Q (Qualcomm QRB2210 / qcm2290). Debian **trixie** / arm64 with the
Mender client (`mender-client4`) from the Mender APT repository. A/B via the
platform's native Qualcomm boot slots (`qbootctl` + ABL), driven by the same
`qbootctl-rootfs` update module as the Yocto uno-q integration
(`meta-mender-community`/`meta-mender-qcom`) — see `floating/uno-q/README.md`.

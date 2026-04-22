# mender-convert configurations

This tree holds community-curated [mender-convert](https://github.com/mendersoftware/mender-convert) configuration files, organised in parallel to the `yocto/` tree.

## Layout

```
mender-convert/
├── include/             # sourceable shell fragments shared across configs
├── tagged/              # configs mirroring upstream at a pinned mender-convert tag
├── floating/            # configs mirroring upstream master (may pick up changes sooner)
└── validation/
    ├── tagged/          # validation-only variants, pinned
    └── floating/        # validation-only variants, master-tracking
```

Mender-convert configs are **shell fragments**, not YAML — they are sourced by the mender-convert engine and typically contain `export` statements and `source` directives.

## Tagged vs floating

Upstream mender-convert itself has no Yocto-style layer pinning. Here, the split expresses **which upstream revision the community file was copied from**:

- `tagged/` — copied from the upstream tag currently consumed by the `build-mender-convert-tagged` and `build-mender-convert-validation-tagged` workflows (presently `5.2.1`).
- `floating/` — copied from upstream `master`, tracking the ref used by `build-mender-convert-floating` and `build-mender-convert-validation-floating`.

At the point these files were first imported (mender-convert 5.2.1 vs master), they were byte-identical. The split exists to allow future divergence without breaking the workflow contract, and to keep the directory layout symmetric with the `yocto/` tree.

## Implicit dependency on upstream

Several config files `source configs/raspberrypi/uboot/include/...` — i.e. they reference include fragments that live only in the upstream mender-convert repository. This works because the build script runs mender-convert with CWD at its own repo root, so `configs/...` resolves against the upstream tree at runtime. Community configs that want to be self-contained should place their own fragments under `mender-convert/include/` and reference them with an absolute path.

## Shadowing upstream configs

Community configs are allowed to shadow an upstream config (same platform + OS, different contents) provided the shadow is listed in the table below with a reason.

| Path | Upstream counterpart | Reason |
|------|----------------------|--------|
| `tagged/raspberrypi/raspberrypi0w_config` | `raspberrypi/uboot/raspberrypi0w_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi3_bullseye_32bit_config` | `raspberrypi/uboot/debian/raspberrypi3_bullseye_32bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi3_bullseye_64bit_config` | `raspberrypi/uboot/debian/raspberrypi3_bullseye_64bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi3_bookworm_64bit_config` | `raspberrypi/uboot/debian/raspberrypi3_bookworm_64bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi4_bullseye_64bit_config` | `raspberrypi/uboot/debian/raspberrypi4_bullseye_64bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi4_bookworm_64bit_config` | `raspberrypi/uboot/debian/raspberrypi4_bookworm_64bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi4_trixie_64bit_config` | `raspberrypi/uboot/debian/raspberrypi4_trixie_64bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi5_bookworm_64bit_config` | `raspberrypi/uboot/debian/raspberrypi5_bookworm_64bit_config` | unmodified mirror |
| `tagged/raspberrypi/raspberrypi5_trixie_64bit_config` | `raspberrypi/uboot/debian/raspberrypi5_trixie_64bit_config` | unmodified mirror |
| `tagged/qemu-x86-64/debian-qemux86-64_config` | `debian-qemux86-64_config` | unmodified mirror |

`floating/` entries mirror the same upstream counterparts at `master`. The `uboot/debian/` intermediate path used by upstream is flattened here — all raspberrypi configs live directly under `raspberrypi/`.

## Adding a new configuration

1. Drop the config file under `tagged/<platform>/<name>_config`. Mirror it under `floating/<platform>/<name>_config` if you also want a master-tracking variant.
2. If the config needs a rootfs overlay, place it at `tagged/overlays/<name>/` (or `floating/overlays/<name>/`).
3. In the `mender-integration-builds` repo, add (or update) an entry in `.forgejo/configs/build-configs.json` whose `config_file` is `mender-community-images/mender-convert/tagged/<platform>/<name>_config`. Set `overlay_dir` if applicable.
4. Bump the `mender-community-images` submodule pointer in `mender-integration-builds` after the community-side commit lands.
5. If the config shadows an upstream counterpart with modifications, append a row to the table above describing the reason for the divergence.

## Path conventions

- Always reference community configs from `build-configs.json` by their full `mender-community-images/...` path. A bare filename matching an upstream file will resolve to upstream, not here.
- Avoid putting shared fragments outside `include/`. The rest of the tree is for leaf configs that `build-configs.json` can reference directly.

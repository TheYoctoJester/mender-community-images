#!/bin/bash -e
# py3compile/py3clean byte-compilation randomly segfaults under qemu-user-static 10.x
# while building the arm64 rootfs in an amd64 container (e.g. the linux-kbuild and
# python3-smbus2 maintainer hooks crash). Divert them to a no-op for the whole build;
# .pyc precompilation is simply skipped (Python still works, recompiling on demand).
# Registered before the heavy python installs (stage1/stage2) so re-installs of these
# tools land on the diverted path and never run under emulation.
for tool in py3compile py3clean; do
    dpkg-divert --local --rename --divert "/usr/bin/${tool}.disabled" "/usr/bin/${tool}" || true
    ln -sf /bin/true "/usr/bin/${tool}"
done

#!/usr/bin/env bash
# Builds the C sysroot for the static build with zig cc:
#   hack/build-sysroot.sh <sysroot>
# skopeo links nothing but musl, so the sysroot holds only hack/musl-compat.h, which
# .goreleaser.yaml includes for the releases that need it. buildah and podman build their
# static libraries here.
set -euo pipefail

sysroot="$(realpath -m "$1")"
mkdir -p "${sysroot}"
cp "$(dirname "$0")/musl-compat.h" "${sysroot}/"

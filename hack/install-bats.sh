#!/usr/bin/env bash
# Installs the pinned bats-core release, checked against its SHA-256, so every test
# environment runs the same version:
#   hack/install-bats.sh <prefix>
# Puts bats in <prefix>/bin/bats. Needs curl and shasum or sha256sum.
set -euo pipefail

# renovate: datasource=github-releases depName=bats-core/bats-core
BATS_VERSION=1.14.0
# SHA-256 of GitHub's source tarball for that tag; update it with BATS_VERSION.
BATS_SHA256=bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177

mkdir -p "$1"
prefix="$(cd "$1" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

tarball="${work}/bats-core.tar.gz"
curl -fsSL -o "${tarball}" \
  "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz"
if command -v shasum >/dev/null; then
  actual="$(shasum -a 256 "${tarball}" | cut -d ' ' -f 1)"
else
  actual="$(sha256sum "${tarball}" | cut -d ' ' -f 1)"
fi
if [[ "${actual}" != "${BATS_SHA256}" ]]; then
  echo "bats-core ${BATS_VERSION}: SHA-256 ${actual}, expected ${BATS_SHA256}" >&2
  exit 1
fi
mkdir "${work}/src"
tar -xzf "${tarball}" -C "${work}/src" --strip-components=1
"${work}/src/install.sh" "${prefix}" >/dev/null

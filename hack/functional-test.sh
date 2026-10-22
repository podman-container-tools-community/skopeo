#!/usr/bin/env bash
# Exercises the transports people use most with a built binary:
#   hack/functional-test.sh <skopeo> <registry host:port>
# Needs network access to quay.io, a plain-HTTP registry at <registry> and, unless run as
# root, sudo for containers-storage. The test cases are in test/functional.bats.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
SKOPEO="$(realpath "$1")"
REGISTRY="$2"
export SKOPEO REGISTRY

bats="$(mktemp -d)"
trap 'rm -rf "${bats}"' EXIT
"${repo}/hack/install-bats.sh" "${bats}"
"${bats}/bin/bats" --formatter tap "${repo}/test/functional.bats"

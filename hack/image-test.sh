#!/usr/bin/env bash
# Builds the image from a goreleaser dist directory or a directory with the release
# archives (hack/build-image.sh --load) and runs
# test/image.bats against it:
#   hack/image-test.sh <dist dir|release dir>
# Needs Docker with buildx, jq, bats from mise.toml on PATH (mise install) and network
# access to quay.io, Docker Hub and dl-cdn.alpinelinux.org.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export IMAGE=localhost/skopeo:test
"${repo}/hack/build-image.sh" --load "$1" "${IMAGE}"

status=0
bats --formatter tap "${repo}/test/image.bats" || status=1
docker image rm "${IMAGE}" >/dev/null
exit "${status}"

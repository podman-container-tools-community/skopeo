#!/usr/bin/env bash
# Builds the image from a goreleaser dist directory, laid out like goreleaser's dockers_v2
# context, and runs the checks in test/image.bats against it:
#   hack/image-test.sh <dist dir> <default-policy.json>
# Builds every architecture found in <dist dir> (no emulation needed) and tests the
# host's. Needs Docker with buildx, curl and network access to quay.io, Docker Hub and
# dl-cdn.alpinelinux.org.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
dist="$(realpath "$1")"
policy="$(realpath "$2")"
export IMAGE=localhost/skopeo:test
host="$(docker version --format '{{.Server.Arch}}')"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/ctx/.build/packaging"
cp -r "${repo}/packaging/image" "${work}/ctx/.build/packaging/"
cp "${policy}" "${work}/ctx/default-policy.json"
platforms=()
for arch in amd64 arm64; do
  binary=("${dist}/skopeo_linux_${arch}_"*/skopeo)
  [[ -f "${binary[0]}" ]] || continue
  mkdir -p "${work}/ctx/linux/${arch}"
  cp "${binary[0]}" "${work}/ctx/linux/${arch}/"
  platforms+=("linux/${arch}")
done

build() {
  docker buildx build --quiet -f "${repo}/Dockerfile" "$@" "${work}/ctx" >/dev/null
}
for platform in "${platforms[@]}"; do
  if [[ "${platform}" != "linux/${host}" ]]; then
    echo "+ building ${platform}" >&2
    build --platform "${platform}"
  fi
done
echo "+ building linux/${host}" >&2
build --load --platform "linux/${host}" -t "${IMAGE}"

"${repo}/hack/install-bats.sh" "${work}/bats"
status=0
"${work}/bats/bin/bats" --formatter tap "${repo}/test/image.bats" || status=1
docker image rm "${IMAGE}" >/dev/null
exit "${status}"

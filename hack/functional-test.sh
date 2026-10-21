#!/usr/bin/env bash
# Exercises the transports people use most with a built binary:
#   hack/functional-test.sh <skopeo> <registry host:port>
# Needs network access to quay.io, a plain-HTTP registry at <registry> and sudo for
# containers-storage.
set -euo pipefail

skopeo="$(realpath "$1")"
registry="$2"
src=docker://quay.io/libpod/alpine:latest
work="$(mktemp -d)"

# Up to 1.17, containers/storage only registers the overlay driver in cgo builds.
version="$("${skopeo}" --version | awk '{print $3}')"
driver=overlay
if [[ "$(printf '%s\n' "${version}" 1.18.0 | sort -V | head -1)" != 1.18.0 ]]; then
  driver=vfs
fi
storage="containers-storage:[${driver}@${work}/storage+${work}/run]"

run() {
  echo "+ skopeo $*" >&2
  "${skopeo}" --insecure-policy "$@"
}

run --version
run inspect --raw "${src}" | jq -e '.manifests | length > 1' >/dev/null
run inspect "${src}" | jq -e '.Os == "linux"' >/dev/null

# Registry -> OCI layout with every platform, then back to a registry.
run copy --all "${src}" "oci:${work}/oci:alpine"
run copy --all --dest-tls-verify=false "oci:${work}/oci:alpine" "docker://${registry}/alpine:latest"
run inspect --tls-verify=false "docker://${registry}/alpine:latest" | jq -e '.Name' >/dev/null

# Registry -> dir, and sync of a whole repository.
run copy --src-tls-verify=false "docker://${registry}/alpine:latest" "dir:${work}/dir"
test -s "${work}/dir/manifest.json"
run sync --src docker --dest dir --src-tls-verify=false "${registry}/alpine" "${work}/sync"
test -s "${work}/sync/alpine:latest/manifest.json"

# containers-storage, as root.
echo "+ sudo skopeo copy oci -> ${storage}" >&2
sudo "${skopeo}" --insecure-policy copy "oci:${work}/oci:alpine" "${storage}localhost/alpine:latest"
sudo "${skopeo}" --insecure-policy inspect "${storage}localhost/alpine:latest" | jq -e '.Layers | length > 0' >/dev/null
sudo "${skopeo}" --insecure-policy copy --dest-tls-verify=false "${storage}localhost/alpine:latest" "docker://${registry}/alpine:from-storage"
run inspect --tls-verify=false "docker://${registry}/alpine:from-storage" >/dev/null

# containers-storage leaves its overlay mount behind.
sudo umount -R "${work}/storage/${driver}" 2>/dev/null || true
sudo rm -rf "${work}"
echo "functional tests passed" >&2

#!/usr/bin/env bats
# Functional tests for a built binary; run through hack/functional-test.sh, which sets
# SKOPEO (the binary) and REGISTRY (a plain-HTTP registry, host:port).
# The cases run in order and later ones use what earlier ones copied.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export SOURCE_IMAGE="${SOURCE_IMAGE:-docker://quay.io/libpod/alpine:latest}"
  WORK="$(mktemp -d)"
  export WORK

  export DRIVER=overlay
  export STORAGE="containers-storage:[${DRIVER}@${WORK}/storage+${WORK}/run]"

  SUDO=sudo
  if [[ "$(id -u)" == 0 ]]; then
    SUDO=
  fi
  export SUDO
}

teardown_file() {
  # containers-storage leaves its overlay mount behind.
  ${SUDO} umount -R "${WORK}/storage/${DRIVER}" 2>/dev/null || true
  ${SUDO} rm -rf "${WORK}"
}

skopeo() {
  "${SKOPEO}" --insecure-policy "$@"
}

# containers-storage needs root.
skopeo_root() {
  ${SUDO} "${SKOPEO}" --insecure-policy "$@"
}

@test "version" {
  run -0 skopeo --version
  [[ "${output}" == "skopeo version "* ]]
}

@test "inspect --raw shows a multi-platform index" {
  run -0 skopeo inspect --raw "${SOURCE_IMAGE}"
  jq -e '.manifests | length > 1' <<<"${output}"
}

@test "inspect shows the image for this platform" {
  run -0 skopeo inspect "${SOURCE_IMAGE}"
  jq -e '.Os == "linux"' <<<"${output}"
}

@test "copy --all from a registry to an OCI layout" {
  skopeo copy --all "${SOURCE_IMAGE}" "oci:${WORK}/oci:alpine"
  jq -e '.manifests | length == 1' "${WORK}/oci/index.json"
}

@test "copy --all from an OCI layout to a registry" {
  skopeo copy --all --dest-tls-verify=false "oci:${WORK}/oci:alpine" \
    "docker://${REGISTRY}/alpine:latest"
  run -0 skopeo inspect --raw --tls-verify=false "docker://${REGISTRY}/alpine:latest"
  jq -e '.manifests | length > 1' <<<"${output}"
}

@test "copy from a registry to dir" {
  skopeo copy --src-tls-verify=false "docker://${REGISTRY}/alpine:latest" \
    "dir:${WORK}/dir"
  test -s "${WORK}/dir/manifest.json"
}

@test "sync a repository to dir" {
  skopeo sync --src docker --dest dir --src-tls-verify=false "${REGISTRY}/alpine" \
    "${WORK}/sync"
  test -s "${WORK}/sync/alpine:latest/manifest.json"
}

@test "copy from an OCI layout to containers-storage" {
  skopeo_root copy "oci:${WORK}/oci:alpine" "${STORAGE}localhost/alpine:latest"
  run -0 skopeo_root inspect "${STORAGE}localhost/alpine:latest"
  jq -e '.Layers | length > 0' <<<"${output}"
}

@test "copy from containers-storage to a registry" {
  skopeo_root copy --dest-tls-verify=false "${STORAGE}localhost/alpine:latest" \
    "docker://${REGISTRY}/alpine:from-storage"
  skopeo inspect --tls-verify=false "docker://${REGISTRY}/alpine:from-storage"
}

@test "list-tags shows both pushed tags" {
  run -0 skopeo list-tags --tls-verify=false "docker://${REGISTRY}/alpine"
  jq -e '.Tags | index("latest") and index("from-storage")' <<<"${output}"
}

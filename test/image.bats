#!/usr/bin/env bats
# Tests for the image; run through hack/image-test.sh, which builds it and sets IMAGE.
# A registry:3 container on a private network stands in for a registry with credentials;
# the cases run in order and later ones use what earlier ones copied.

# The scripts in single quotes are expanded by the shell in the image.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export SOURCE_IMAGE="${SOURCE_IMAGE:-docker://quay.io/libpod/alpine:latest}"
  export NETWORK=skopeo-image-test
  export REGISTRY=registry:5000
  docker network create "${NETWORK}" >/dev/null
  docker run -d --rm --name "${NETWORK}-registry" --network "${NETWORK}" \
    --network-alias registry registry:3 >/dev/null
}

teardown_file() {
  docker rm -f "${NETWORK}-registry" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
}

# Runs skopeo (the entrypoint) in the image; options before -- go to docker run.
in_image() {
  local opts=()
  while [[ $# -gt 0 && "$1" != -- ]]; do
    opts+=("$1")
    shift
  done
  shift
  docker run --rm --network "${NETWORK}" "${opts[@]}" "${IMAGE}" "$@"
}

# Runs a shell script in the image, with REGISTRY set; options before -- go to docker run.
sh_in_image() {
  local opts=()
  while [[ $# -gt 0 && "$1" != -- ]]; do
    opts+=("$1")
    shift
  done
  shift
  docker run --rm --network "${NETWORK}" -e REGISTRY --entrypoint /bin/sh "${opts[@]}" \
    "${IMAGE}" -euc "$@"
}

@test "skopeo is the entrypoint" {
  run -0 in_image -- --version
  [[ "${output}" == "skopeo version "* ]]
}

@test "copy --all from a remote registry to the test registry" {
  in_image -- copy --all --dest-tls-verify=false "${SOURCE_IMAGE}" \
    "docker://${REGISTRY}/alpine:latest"
  run -0 in_image -- inspect --raw --tls-verify=false "docker://${REGISTRY}/alpine:latest"
  [[ "$(jq '.manifests | length' <<<"${output}")" -gt 1 ]]
}

@test "default policy is in place" {
  run -0 sh_in_image -- 'cat /etc/containers/policy.json'
  jq -e '.default' <<<"${output}"
}

@test "login as root writes REGISTRY_AUTH_FILE" {
  sh_in_image -- '
    test "${REGISTRY_AUTH_FILE}" = /tmp/auth.json
    skopeo login --tls-verify=false -u user -p secret "${REGISTRY}"
    grep -q "${REGISTRY}" /tmp/auth.json'
}

@test "login as uid 1000 writes REGISTRY_AUTH_FILE" {
  sh_in_image --user 1000 -- '
    skopeo login --tls-verify=false -u user -p secret "${REGISTRY}"
    grep -q "${REGISTRY}" /tmp/auth.json'
}

@test "skopeo user with subordinate ids" {
  run -0 sh_in_image --user skopeo -- 'echo "$(id -u) ${HOME}"'
  expect_output "1000 /home/skopeo"
  run -0 sh_in_image -- 'grep -c "^skopeo:" /etc/subuid /etc/subgid'
  expect_output "/etc/subuid:2
/etc/subgid:2"
}

@test "newuidmap and newgidmap map the skopeo user's subordinate ids" {
  # Alpine installs them with file capabilities, which have to survive the image build.
  sh_in_image --privileged --user skopeo -- '
    unshare -U sleep 30 &
    pid=$!
    sleep 1
    newuidmap "${pid}" 0 1000 1 1 1 999
    newgidmap "${pid}" 0 1000 1 1 1 999
    test "$(wc -l <"/proc/${pid}/uid_map")" -eq 2
    test "$(wc -l <"/proc/${pid}/gid_map")" -eq 2
    kill "${pid}"'
}

@test "update-ca-certificates is available" {
  sh_in_image -- 'command -v update-ca-certificates'
}

@test "copy to containers-storage as root" {
  # overlay through fuse-overlayfs; vfs for releases before 1.18 (no overlay without cgo).
  sh_in_image --privileged -- '
    driver="$(sed -n "s/^driver = \"\(.*\)\"/\1/p" /etc/containers/storage.conf)"
    if [ "${driver}" = overlay ]; then
      grep -q "mount_program = \"/usr/bin/fuse-overlayfs\"" /etc/containers/storage.conf
    fi
    skopeo copy --src-tls-verify=false docker://${REGISTRY}/alpine:latest \
      containers-storage:localhost/alpine:latest
    skopeo inspect containers-storage:localhost/alpine:latest >/dev/null
    test -d "/var/lib/containers/storage/${driver}"'
}

@test "copy to containers-storage as the skopeo user (rootless)" {
  # containers/storage enters the user namespace in a cgo constructor (pkg/unshare), so a
  # cgo-free skopeo re-executes itself forever instead.
  skip "rootless containers-storage: needs a cgo build of skopeo"
  sh_in_image --privileged --user skopeo -- '
    skopeo copy --src-tls-verify=false docker://${REGISTRY}/alpine:latest \
      containers-storage:localhost/alpine:latest
    skopeo inspect containers-storage:localhost/alpine:latest >/dev/null
    test -d "${HOME}/.local/share/containers/storage/overlay"'
}

@test "additional image store is configured" {
  sh_in_image -- '
    test -f /var/lib/shared/overlay-images/images.lock
    test -f /var/lib/shared/overlay-layers/layers.lock
    grep -q "/var/lib/shared" /etc/containers/storage.conf'
}

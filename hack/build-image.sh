#!/usr/bin/env bash
# Builds the multi-arch image from built or released binaries and loads or pushes it:
#   hack/build-image.sh --load <dist dir> <local tag>
#   hack/build-image.sh --push <dist dir|release dir> <image>
# <dist dir> is goreleaser's dist/ (binaries in <name>_linux_<arch>_*/); a <release dir>
# holds a release's <name>_<version>_linux_<arch>.tar.gz archives instead (rebuild.yaml).
# The build context is linux/<arch>/<binary> plus packaging/image/. Every architecture
# found is built (no emulation needed); --load loads the host's as <local tag>.
# --push pushes all of them to <image> with the tags for VERSION: vX.Y.Z, vX.Y if
# IS_LATEST_MINOR=true, vX and latest if IS_LATEST=true, and vX.Y.Z-immutable if
# IMMUTABLE=true (only the release pushes that one, and only if it does not exist yet),
# then signs the manifest list
# with cosign (keyless). VERSION, REVISION (the upstream commit) and CREATED (its date,
# RFC 3339) are set by the workflows.
# Needs Docker with buildx (a docker-container builder for --push), jq and, for --push,
# cosign and a login to the registry.
set -euo pipefail

NAME=skopeo
BINARIES=(skopeo)
UPSTREAM=podman-container-tools/skopeo

mode="$1"
src="$(realpath "$2")"
target="$3"
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The build context: the binaries of every architecture present and the configuration.
ctx="${work}/ctx"
mkdir -p "${ctx}/packaging"
cp -r "${repo}/packaging/image" "${ctx}/packaging/"
platforms=()
for arch in amd64 arm64; do
  dir="${ctx}/linux/${arch}"
  mkdir -p "${dir}"
  if [[ -f "${src}/metadata.json" ]]; then
    for binary in "${BINARIES[@]}"; do
      built=("${src}/${binary}_linux_${arch}_"*/"${binary}")
      [[ ! -f "${built[0]}" ]] || cp "${built[0]}" "${dir}/"
    done
  else
    archive=("${src}/${NAME}_"*"_linux_${arch}.tar.gz")
    [[ ! -f "${archive[0]}" ]] || tar -xzf "${archive[0]}" -C "${dir}" "${BINARIES[@]}"
  fi
  if [[ "$(find "${dir}" -type f | wc -l)" -eq "${#BINARIES[@]}" ]]; then
    platforms+=("linux/${arch}")
  else
    rm -rf "${dir}"
  fi
done
if [[ "${#platforms[@]}" -eq 0 ]]; then
  echo "no binaries for any architecture in ${src}" >&2
  exit 1
fi

build() {
  docker buildx build --quiet -f "${repo}/Dockerfile" "$@" "${ctx}" >/dev/null
}

case "${mode}" in
--load)
  host="$(docker version --format '{{.Server.Arch}}')"
  for platform in "${platforms[@]}"; do
    if [[ "${platform}" != "linux/${host}" ]]; then
      echo "+ building ${platform}" >&2
      build --platform "${platform}"
    fi
  done
  echo "+ building linux/${host}" >&2
  build --load --platform "linux/${host}" -t "${target}"
  ;;
--push)
  : "${VERSION:?}" "${REVISION:?}" "${CREATED:?}"
  tags=("${VERSION}")
  # The -immutable tag is pushed once: a retried release must not move it.
  if [[ "${IMMUTABLE:-false}" == true ]]; then
    if existing="$(docker buildx imagetools inspect "${target}:${VERSION}-immutable" 2>&1)"; then
      echo "::notice::${target}:${VERSION}-immutable exists already and is kept" >&2
    elif grep -qiE 'not found|MANIFEST_UNKNOWN|NAME_UNKNOWN' <<<"${existing}"; then
      tags+=("${VERSION}-immutable")
    else
      # Any other error (registry, login, network) must not end in a second push.
      echo "${existing}" >&2
      echo "::error::cannot tell whether ${target}:${VERSION}-immutable exists" >&2
      exit 1
    fi
  fi
  [[ "${IS_LATEST_MINOR:-false}" != true ]] || tags+=("${VERSION%.*}")
  [[ "${IS_LATEST:-false}" != true ]] || tags+=("${VERSION%%.*}" latest)
  # The pinned base image, for the base.* annotations.
  base="$(sed -n 's/^FROM \([^ ]*\) AS base$/\1/p' "${repo}/Dockerfile")"
  description="Community-built static ${NAME} ${VERSION} (upstream: github.com/${UPSTREAM})"
  source="https://github.com/${GITHUB_REPOSITORY:?}"
  annotations=(
    "org.opencontainers.image.title=${NAME}"
    "org.opencontainers.image.description=${description}"
    "org.opencontainers.image.version=${VERSION#v}"
    "org.opencontainers.image.created=${CREATED}"
    "org.opencontainers.image.source=${source}"
    "org.opencontainers.image.revision=${REVISION}"
    "org.opencontainers.image.licenses=Apache-2.0"
    "org.opencontainers.image.base.name=docker.io/library/${base%@*}"
    "org.opencontainers.image.base.digest=${base#*@}"
  )
  printf -v platform_list '%s,' "${platforms[@]}"
  args=(--sbom=true --platform "${platform_list%,}" --metadata-file "${work}/metadata.json")
  for tag in "${tags[@]}"; do
    args+=(-t "${target}:${tag}")
  done
  for annotation in "${annotations[@]}"; do
    args+=(--annotation "index,manifest:${annotation}")
  done
  # ghcr.io shows the description and links the repository from labels only.
  args+=(--label "org.opencontainers.image.description=${description}" --label "org.opencontainers.image.source=${source}")
  echo "+ pushing ${target} ${tags[*]} (${platforms[*]})" >&2
  build --push "${args[@]}"
  digest="$(jq -r '."containerimage.digest"' "${work}/metadata.json")"
  cosign sign --yes "${target}@${digest}"
  echo "${target}@${digest}"
  ;;
*)
  echo "usage: $0 --load <dist dir> <local tag> | --push <dist dir|release dir> <image>" >&2
  exit 2
  ;;
esac

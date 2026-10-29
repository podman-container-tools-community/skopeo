#!/usr/bin/env bash
# Builds the multi-arch image from built or released binaries and loads or pushes it:
#   hack/build-image.sh --load <dist dir> <local tag>
#   hack/build-image.sh --push <dist dir|release dir> <image>
# <dist dir> is goreleaser's dist/ (binaries in <name>_linux_<arch>_*/); a <release dir>
# holds a release's <name>_<version>_linux_<arch>.tar.gz archives instead (rebuild.yaml).
# The build context is linux/<arch>/<binary> plus packaging/image/. Every architecture
# found is built (no emulation needed); --load loads the host's as <local tag>.
# --push pushes all of them to <image> with the tags for VERSION: vX.Y.Z, vX.Y if it is
# the newest upstream release of its minor, vX and latest if it is the newest upstream
# release (hack/upstream-releases.sh, asked right before the push), then signs the
# manifest list with cosign (keyless). With IMMUTABLE=true (the release only) the signed
# manifest list also gets the tag vX.Y.Z-immutable, unless that tag exists already. VERSION (also needed to
# pick the archives of a <release dir>), REVISION (the upstream commit) and CREATED (its
# date, RFC 3339) are set by the workflows.
# Needs Docker with buildx (a docker-container builder for --push), jq and, for --push,
# cosign, the GitHub CLI (GH_TOKEN) and a login to the registry.
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
    # The release's archive by its exact name, listed in the checksums.txt next to it
    # (verified by images.yaml): an extra asset must not get in, and a missing archive
    # must not end in an image for one architecture only.
    : "${VERSION:?needed to pick the archives}"
    archive="${NAME}_${VERSION#v}_linux_${arch}.tar.gz"
    if [[ ! -f "${src}/${archive}" || ! -f "${src}/checksums.txt" ]]; then
      echo "${src} has no ${archive} or no checksums.txt" >&2
      exit 1
    fi
    if ! grep -qE "^[0-9a-f]{64}  ${archive//./\\.}$" "${src}/checksums.txt"; then
      echo "${archive} is not listed in ${src}/checksums.txt" >&2
      exit 1
    fi
    tar -xzf "${src}/${archive}" -C "${dir}" "${BINARIES[@]}"
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
  # Floating tags: latest and vX follow the newest upstream release, vX.Y the newest
  # release of that minor. The newest by version, not upstream's GitHub "latest" flag:
  # that flag moves to a backport release of an older minor unless upstream resets it.
  # Asked here, right before the push (a cache hit after the image test), not when the
  # workflow starts: a run still going when upstream releases a newer version must not
  # move these tags back to its own version.
  releases="$("${repo}/hack/upstream-releases.sh")"
  tags=("${VERSION}")
  [[ "${VERSION}" != "$(grep -F "${VERSION%.*}." <<<"${releases}" | tail -1)" ]] || tags+=("${VERSION%.*}")
  [[ "${VERSION}" != "$(tail -1 <<<"${releases}")" ]] || tags+=("${VERSION%%.*}" latest)
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
  # The -immutable tag is a copy of the manifest list just signed (same digest), made
  # only after the signature, so an existing one was always signed by this script. It is
  # pushed once: a retried release keeps it. The registry's repository exists at this
  # point, so "not found" is the only answer for a missing tag.
  if [[ "${IMMUTABLE:-false}" == true ]]; then
    immutable="${target}:${VERSION}-immutable"
    if existing="$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "${immutable}" 2>&1)"; then
      echo "::notice::${immutable} exists already (${existing}) and is kept" >&2
    elif grep -qiE 'not found|MANIFEST_UNKNOWN' <<<"${existing}"; then
      docker buildx imagetools create -t "${immutable}" "${target}@${digest}"
    else
      # Any other error (registry, login, network) must not end in a second push.
      echo "${existing}" >&2
      echo "::error::cannot tell whether ${immutable} exists" >&2
      exit 1
    fi
  fi
  echo "${target}@${digest}"
  ;;
*)
  echo "usage: $0 --load <dist dir> <local tag> | --push <dist dir|release dir> <image>" >&2
  exit 2
  ;;
esac

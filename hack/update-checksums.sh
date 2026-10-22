#!/usr/bin/env bash
# Recomputes the SHA-256 pinned next to each version Renovate bumps:
#   hack/update-checksums.sh
# Runs on Renovate pull requests via .github/workflows/renovate.yaml, and locally.
# Needs curl and shasum or sha256sum.
set -euo pipefail

cd "$(dirname "$0")/.."

sha256() {
  if command -v shasum >/dev/null; then
    shasum -a 256 | cut -d ' ' -f 1
  else
    sha256sum | cut -d ' ' -f 1
  fi
}

# pin FILE NAME URL: downloads URL, with {version} replaced by NAME_VERSION from FILE,
# and writes its SHA-256 to NAME_SHA256 in FILE.
pin() {
  local file="$1" name="$2" url="$3" version hash
  # NAME_VERSION=value in shell, NAME_VERSION: value in YAML.
  local sep='(=|:[[:space:]]*)'
  version="$(sed -nE "s/^[[:space:]]*${name}_VERSION${sep}([^[:space:]]+).*$/\2/p" "${file}")"
  if [[ -z "${version}" ]]; then
    echo "${file}: ${name}_VERSION not found" >&2
    exit 1
  fi
  hash="$(curl -fsSL "${url//\{version\}/${version}}" | sha256)"
  sed -E "s/^([[:space:]]*${name}_SHA256${sep})[0-9a-f]{64}/\1${hash}/" \
    "${file}" >"${file}.tmp"
  # cat instead of mv keeps the file's mode, such as the executable bit.
  cat "${file}.tmp" >"${file}"
  rm "${file}.tmp"
  if ! grep -q "${name}_SHA256.*${hash}" "${file}"; then
    echo "${file}: ${name}_SHA256 not found" >&2
    exit 1
  fi
  echo "${name} ${version}: ${hash}"
}

pin hack/install-bats.sh BATS \
  "https://github.com/bats-core/bats-core/archive/refs/tags/v{version}.tar.gz"

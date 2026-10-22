#!/usr/bin/env bash
# Adds the SHA-256 of downloads that mise.lock has no checksum for, after Renovate bumps
# a tool in mise.toml:
#   hack/update-checksums.sh
# Runs on Renovate pull requests via .github/workflows/renovate.yaml, and locally.
# Needs mise, curl and shasum or sha256sum.
set -euo pipefail

cd "$(dirname "$0")/.."

sha256() {
  if command -v shasum >/dev/null; then
    shasum -a 256 | cut -d ' ' -f 1
  else
    sha256sum | cut -d ' ' -f 1
  fi
}

# lock_checksums: refreshes mise.lock for mise.toml and adds a SHA-256 to every download
# that has none. mise lock records checksums only where a release publishes them, and
# GitHub's source archives, which bats-core is installed from, come without.
lock_checksums() {
  local line url checksum="" hashed="" hash="" out
  mise lock
  out="$(mktemp)"
  while IFS= read -r line; do
    case "${line}" in
    '['*) checksum="" ;;
    'checksum = '*) checksum=yes ;;
    'url = '*)
      if [[ -z "${checksum}" ]]; then
        url="${line#url = \"}"
        url="${url%\"}"
        # Platforms that share one download follow each other.
        if [[ "${url}" != "${hashed}" ]]; then
          hash="$(curl -fsSL "${url}" | sha256)"
          hashed="${url}"
          echo "${url}: ${hash}" >&2
        fi
        echo "checksum = \"sha256:${hash}\""
      fi
      ;;
    esac
    printf '%s\n' "${line}"
  done <mise.lock >"${out}"
  # cat instead of mv keeps the file's mode.
  cat "${out}" >mise.lock
  rm "${out}"
}

lock_checksums

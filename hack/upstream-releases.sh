#!/usr/bin/env bash
# Prints the tags of upstream skopeo's GitHub releases since MIN_VERSION, oldest first.
# Drafts and pre-releases are skipped.
set -euo pipefail

UPSTREAM="${UPSTREAM:-podman-container-tools/skopeo}"
MIN_VERSION="${MIN_VERSION:-v1.11.0}"

gh api --paginate "repos/${UPSTREAM}/releases" --jq '.[] | select(.draft or .prerelease | not) | .tag_name' |
  sort -V |
  while read -r tag; do
    if [[ "$(printf '%s\n' "${MIN_VERSION}" "${tag}" | sort -V | head -1)" == "${MIN_VERSION}" ]]; then
      echo "${tag}"
    fi
  done

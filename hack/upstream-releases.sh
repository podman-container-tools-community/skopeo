#!/usr/bin/env bash
# Prints the tags of upstream's GitHub releases since MIN_VERSION, oldest first. Drafts
# and pre-releases are skipped.
# GitHub's releases API sometimes answers with an empty or short list, so the list is
# fetched up to five times and accepted only if it contains upstream's latest release
# and reaches back to MIN_VERSION (which must not predate upstream's first release).
set -euo pipefail

UPSTREAM="${UPSTREAM:-podman-container-tools/skopeo}"
MIN_VERSION="${MIN_VERSION:-v1.11.0}"

# True if $1 sorts before or equal to $2 as a version.
version_le() {
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

latest="$(gh api "repos/${UPSTREAM}/releases/latest" --jq .tag_name)"
for attempt in 1 2 3 4 5; do
  tags="$(gh api --paginate "repos/${UPSTREAM}/releases" \
    --jq '.[] | select(.draft or .prerelease | not) | .tag_name' | sort -V)"
  oldest="$(head -1 <<<"${tags}")"
  if grep -qxF "${latest}" <<<"${tags}" && [[ -n "${oldest}" ]] && version_le "${oldest}" "${MIN_VERSION}"; then
    break
  fi
  if ((attempt == 5)); then
    echo "::error::release list of ${UPSTREAM} is incomplete after ${attempt} attempts (latest ${latest} or releases before ${MIN_VERSION} missing)" >&2
    exit 1
  fi
  sleep $((attempt * 5))
done

while read -r tag; do
  if version_le "${MIN_VERSION}" "${tag}"; then
    echo "${tag}"
  fi
done <<<"${tags}"

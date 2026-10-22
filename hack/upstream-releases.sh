#!/usr/bin/env bash
# Prints the tags of upstream skopeo's GitHub releases since MIN_VERSION, oldest first.
# Drafts and pre-releases are skipped.
# GitHub's releases API sometimes answers with an empty or short list, so the list is
# fetched up to five times and accepted only if it contains upstream's latest release
# and reaches back to MIN_VERSION (which must not predate upstream's first release);
# otherwise the script fails.
set -euo pipefail

UPSTREAM="${UPSTREAM:-podman-container-tools/skopeo}"
MIN_VERSION="${MIN_VERSION:-v1.11.0}"
ATTEMPTS=5

retry() {
  local attempt
  for attempt in $(seq "${ATTEMPTS}"); do
    if "$@"; then
      return 0
    fi
    echo "attempt ${attempt}/${ATTEMPTS} failed: $*" >&2
    if [[ "${attempt}" -lt "${ATTEMPTS}" ]]; then
      sleep $((attempt * 5))
    fi
  done
  return 1
}

fetch_latest() {
  latest="$(gh api "repos/${UPSTREAM}/releases/latest" --jq .tag_name)" && [[ -n "${latest}" ]]
}

fetch_tags() {
  tags="$(gh api --paginate "repos/${UPSTREAM}/releases" \
    --jq '.[] | select(.draft or .prerelease | not) | .tag_name' | sort -V)" || return 1
  if ! grep -qxF "${latest}" <<<"${tags}"; then
    echo "release list lacks the latest release ${latest}" >&2
    return 1
  fi
  # The oldest release must not be newer than MIN_VERSION, or pages are missing.
  local oldest
  oldest="$(head -1 <<<"${tags}")"
  if [[ "$(printf '%s\n' "${MIN_VERSION}" "${oldest}" | sort -V | head -1)" != "${oldest}" ]]; then
    echo "release list does not reach back to ${MIN_VERSION}" >&2
    return 1
  fi
}

if ! retry fetch_latest; then
  echo "::error::cannot get the latest release of ${UPSTREAM}" >&2
  exit 1
fi
if ! retry fetch_tags; then
  echo "::error::cannot get a complete release list of ${UPSTREAM}" >&2
  exit 1
fi

while read -r tag; do
  if [[ "$(printf '%s\n' "${MIN_VERSION}" "${tag}" | sort -V | head -1)" == "${MIN_VERSION}" ]]; then
    echo "${tag}"
  fi
done <<<"${tags}"

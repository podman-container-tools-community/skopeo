#!/usr/bin/env bats
# Signing and signature verification with a built binary; run through
# hack/functional-test.sh, which sets SKOPEO and REGISTRY like for functional.bats.
# Releases are built with containers_image_openpgp: GPG signatures verify, but signing
# with GPG (--sign-by) is not supported. Sigstore signing is pure Go and works.
# The cases run in order and later ones use what earlier ones pushed.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export SOURCE_IMAGE="${SOURCE_IMAGE:-docker://quay.io/libpod/alpine:latest}"
  WORK="$(mktemp -d)"
  export WORK
  export SIGSTORE_REPO="${REGISTRY}/signed/sigstore" GPG_REPO="${REGISTRY}/signed/gpg"

  # One image, single-platform, signed below.
  "${SKOPEO}" --insecure-policy copy "${SOURCE_IMAGE}" "dir:${WORK}/image"

  # Sigstore attachments for one repository, a lookaside directory for the other.
  mkdir "${WORK}/registries.d" "${WORK}/lookaside"
  cat >"${WORK}/registries.d/test.yaml" <<EOF
docker:
  ${SIGSTORE_REPO}:
    use-sigstore-attachments: true
  ${GPG_REPO}:
    lookaside: file://${WORK}/lookaside
EOF

  # A GPG key for simple signing, and a second one nothing is signed with.
  local name
  for name in signer other; do
    GNUPGHOME="${WORK}/gnupg-${name}" gpg_quiet --quick-gen-key "${name} <${name}@example.com>" rsa2048 sign never
    GNUPGHOME="${WORK}/gnupg-${name}" gpg_quiet --export >"${WORK}/${name}.gpg"
  done
}

teardown_file() {
  local name
  for name in signer other; do
    gpgconf --homedir "${WORK}/gnupg-${name}" --kill gpg-agent 2>/dev/null || true
  done
  rm -rf "${WORK}"
}

# gpg without prompts, in the home directory GNUPGHOME names.
gpg_quiet() {
  [[ -d "${GNUPGHOME}" ]] || mkdir -m 0700 "${GNUPGHOME}"
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' "$@"
}

# skopeo with the test's registries.d and, unless a policy is given, no policy checks.
skopeo() {
  local policy=(--insecure-policy)
  if [[ "$1" == --policy ]]; then
    policy=(--policy "$2")
    shift 2
  fi
  "${SKOPEO}" "${policy[@]}" --registries.d "${WORK}/registries.d" "$@"
}

# write_policy <file> <repository> <requirement JSON>: rejects everything but <repository>.
write_policy() {
  jq -n --arg repo "$2" --argjson req "$3" \
    '{default: [{type: "reject"}], transports: {docker: {($repo): [$req]}}}' >"$1"
}

@test "sigstore: generate a key pair" {
  printf 'test passphrase' >"${WORK}/passphrase"
  local name
  for name in signer other; do
    skopeo generate-sigstore-key --output-prefix "${WORK}/${name}" --passphrase-file "${WORK}/passphrase"
    test -s "${WORK}/${name}.private"
    test -s "${WORK}/${name}.pub"
  done
}

@test "sigstore: sign with a private key on copy to a registry" {
  skopeo copy --dest-tls-verify=false \
    --sign-by-sigstore-private-key "${WORK}/signer.private" --sign-passphrase-file "${WORK}/passphrase" \
    "dir:${WORK}/image" "docker://${SIGSTORE_REPO}:latest"
  run -0 --separate-stderr skopeo inspect --tls-verify=false --format '{{.Digest}}' "docker://${SIGSTORE_REPO}:latest"
  local digest="${output}"
  # The signature is an attachment tagged after the image's digest.
  run -0 --separate-stderr skopeo list-tags --tls-verify=false "docker://${SIGSTORE_REPO}"
  jq -e --arg tag "${digest/:/-}.sig" '.Tags | index($tag)' <<<"${output}"
}

@test "sigstore: policy accepts the signed image" {
  write_policy "${WORK}/sigstore-policy.json" "${SIGSTORE_REPO}" \
    "{\"type\": \"sigstoreSigned\", \"keyPath\": \"${WORK}/signer.pub\", \"signedIdentity\": {\"type\": \"matchRepository\"}}"
  skopeo --policy "${WORK}/sigstore-policy.json" copy --src-tls-verify=false \
    "docker://${SIGSTORE_REPO}:latest" "dir:${WORK}/sigstore-verified"
}

@test "sigstore: policy rejects the image for another key" {
  write_policy "${WORK}/sigstore-other.json" "${SIGSTORE_REPO}" \
    "{\"type\": \"sigstoreSigned\", \"keyPath\": \"${WORK}/other.pub\", \"signedIdentity\": {\"type\": \"matchRepository\"}}"
  run -1 skopeo --policy "${WORK}/sigstore-other.json" copy --src-tls-verify=false \
    "docker://${SIGSTORE_REPO}:latest" "dir:${WORK}/sigstore-rejected"
  [[ "${output}" == *"Source image rejected"* ]]
}

@test "gpg: signing with --sign-by fails with a clear error" {
  GNUPGHOME="${WORK}/gnupg-signer" run -1 skopeo copy --dest-tls-verify=false --sign-by signer@example.com \
    "dir:${WORK}/image" "docker://${GPG_REPO}:sign-by"
  [[ "${output}" == *"signing is not supported"*"containers_image_openpgp"* ]]
}

# The signature is made with gpg, as by a signer outside this build, and stored where the
# lookaside configuration in registries.d points.
@test "gpg: policy accepts an image signed by gpg in a lookaside" {
  skopeo copy --dest-tls-verify=false "dir:${WORK}/image" "docker://${GPG_REPO}:latest"
  run -0 --separate-stderr skopeo inspect --tls-verify=false --format '{{.Digest}}' "docker://${GPG_REPO}:latest"
  local digest="${output}"
  local sigdir="${WORK}/lookaside/signed/gpg@${digest/:/=}"
  mkdir -p "${sigdir}"
  jq -nc --arg ref "${GPG_REPO}:latest" --arg digest "${digest}" \
    '{critical: {identity: {"docker-reference": $ref}, image: {"docker-manifest-digest": $digest},
      type: "atomic container signature"}, optional: {}}' |
    GNUPGHOME="${WORK}/gnupg-signer" gpg_quiet --sign --output "${sigdir}/signature-1"

  write_policy "${WORK}/gpg-policy.json" "${GPG_REPO}" \
    "{\"type\": \"signedBy\", \"keyType\": \"GPGKeys\", \"keyPath\": \"${WORK}/signer.gpg\"}"
  skopeo --policy "${WORK}/gpg-policy.json" copy --src-tls-verify=false \
    "docker://${GPG_REPO}:latest" "dir:${WORK}/gpg-verified"
}

@test "gpg: policy rejects the image for another key" {
  write_policy "${WORK}/gpg-other.json" "${GPG_REPO}" \
    "{\"type\": \"signedBy\", \"keyType\": \"GPGKeys\", \"keyPath\": \"${WORK}/other.gpg\"}"
  run -1 skopeo --policy "${WORK}/gpg-other.json" copy --src-tls-verify=false \
    "docker://${GPG_REPO}:latest" "dir:${WORK}/gpg-rejected"
  [[ "${output}" == *"Source image rejected"* ]]
}

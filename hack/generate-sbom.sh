#!/usr/bin/env bash
# Writes an SPDX document for the C code linked statically into skopeo, which syft
# cannot see in the binary: musl (zig's copy) and SQLite (bundled by
# github.com/mattn/go-sqlite3). libseccomp is listed when the sysroot has it (buildah
# and podman):
#   hack/generate-sbom.sh <output file>
# Runs in the upstream checkout (a goreleaser before hook) with zig, Go and jq on PATH
# and SYSROOT set; the versions are read from what the build uses, so Renovate bumps
# need no change here. The file goes into the archives, where syft's sbom-cataloger
# merges it into the archive SBOMs (.goreleaser.yaml), and into the image, where
# BuildKit's SBOM scanner does the same (hack/build-image.sh).
set -euo pipefail

NAME=skopeo

out="$1"
mkdir -p "$(dirname "${out}")"

# One entry per library: name version license download_url purl cpe_vendor:cpe_product
components=()

# zig env prints ZON; lib_dir may be relative to the working directory.
lib_dir="$(zig env | sed -n 's/^ *\.lib_dir = "\(.*\)",$/\1/p')"
musl="$(sed -n 's/^#define VERSION "\(.*\)"$/\1/p' "${lib_dir}/libc/musl/src/internal/version.h")"
components+=("musl ${musl} MIT https://musl.libc.org/releases/musl-${musl}.tar.gz pkg:generic/musl@${musl} musl-libc:musl")

pc="${SYSROOT:?}/x86_64/lib/pkgconfig/libseccomp.pc"
if [[ -f "${pc}" ]]; then
  seccomp="$(sed -n 's/^Version: //p' "${pc}")"
  components+=("libseccomp ${seccomp} LGPL-2.1-only https://github.com/seccomp/libseccomp/releases/download/v${seccomp}/libseccomp-${seccomp}.tar.gz pkg:github/seccomp/libseccomp@v${seccomp} libseccomp_project:libseccomp")
fi

# The module version go.mod requires is the one the binary links (setup downloaded it).
sqlite_dir="$(go mod download -json github.com/mattn/go-sqlite3 2>/dev/null | jq -r '.Dir // empty' || true)"
if [[ -n "${sqlite_dir}" ]]; then
  sqlite="$(sed -n 's/^#define SQLITE_VERSION *"\(.*\)"$/\1/p' "${sqlite_dir}/sqlite3-binding.h")"
  components+=("sqlite ${sqlite} blessing https://sqlite.org/ pkg:generic/sqlite@${sqlite} sqlite:sqlite")
fi

for component in "${components[@]}"; do
  read -r name version _ <<<"${component}"
  if [[ ! "${version}" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "no version found for ${name}" >&2
    exit 1
  fi
done

printf '%s\n' "${components[@]}" | jq -R -s \
  --arg name "${NAME}" \
  --arg zig "$(zig version)" \
  --arg tag "$(git describe --tags --exact-match 2>/dev/null || git rev-parse HEAD)" \
  --arg created "$(TZ=UTC0 git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ)" \
  --arg repository "${GITHUB_REPOSITORY:-podman-container-tools-community/${NAME}}" '
  [split("\n")[] | select(. != "") | split(" ")
    | {name: .[0], version: .[1], license: .[2], url: .[3], purl: .[4], cpe: .[5]}] as $c
  | {
      spdxVersion: "SPDX-2.3",
      dataLicense: "CC0-1.0",
      SPDXID: "SPDXRef-DOCUMENT",
      name: "\($name)-static-libraries",
      documentNamespace: "https://github.com/\($repository)/releases/tag/\($tag)#static-libraries",
      creationInfo: {created: $created, creators: ["Tool: hack/generate-sbom.sh"]},
      comment: "C libraries linked statically into \($name) \($tag), built with zig \($zig)",
      documentDescribes: [$c[] | "SPDXRef-Package-\(.name)"],
      packages: [$c[] | {
        SPDXID: "SPDXRef-Package-\(.name)",
        name: .name,
        versionInfo: .version,
        downloadLocation: .url,
        filesAnalyzed: false,
        licenseDeclared: .license,
        externalRefs: [
          {
            referenceCategory: "SECURITY",
            referenceType: "cpe23Type",
            referenceLocator: "cpe:2.3:a:\(.cpe):\(.version):*:*:*:*:*:*:*"
          },
          {referenceCategory: "PACKAGE-MANAGER", referenceType: "purl", referenceLocator: .purl}
        ]
      }]
    }' >"${out}"

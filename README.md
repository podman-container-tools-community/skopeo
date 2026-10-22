[![CI](https://github.com/podman-container-tools-community/skopeo/actions/workflows/ci.yaml/badge.svg)](https://github.com/podman-container-tools-community/skopeo/actions/workflows/ci.yaml)
[![Release](https://github.com/podman-container-tools-community/skopeo/actions/workflows/release.yaml/badge.svg)](https://github.com/podman-container-tools-community/skopeo/actions/workflows/release.yaml)
[![GitHub license](https://img.shields.io/github/license/podman-container-tools-community/skopeo)](https://github.com/podman-container-tools-community/skopeo/blob/main/LICENSE)
[![Current Release](https://img.shields.io/github/release/podman-container-tools-community/skopeo.svg?logo=github)](https://github.com/podman-container-tools-community/skopeo/releases/latest)
[![GitHub Repo stars](https://img.shields.io/github/stars/podman-container-tools-community/skopeo?style=flat&logo=github)](https://github.com/podman-container-tools-community/skopeo/stargazers)
[![GitHub all releases](https://img.shields.io/github/downloads/podman-container-tools-community/skopeo/total?logo=github)](https://github.com/podman-container-tools-community/skopeo/releases/latest)
[![ghcr.io Pulls](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fipitio.github.io%2Fbackage%2Fpodman-container-tools-community%2Fskopeo%2Fskopeo.json&query=%24.downloads&logo=github&label=ghcr.io%20pulls)](https://github.com/podman-container-tools-community/skopeo/pkgs/container/skopeo)

# skopeo (community build)

⭐ Don't forget to star this repository! ⭐

Community-maintained, static binaries and container images of
[skopeo](https://github.com/podman-container-tools/skopeo), part of
[podman-container-tools](https://github.com/podman-container-tools).
**These are not official releases.** They are built from unmodified upstream source
and are not supported by the upstream maintainers.

## Why this exists

Upstream does not publish distribution-independent binaries. For skopeo this was requested
in [containers/skopeo#1478](https://github.com/containers/skopeo/issues/1478); the
maintainers prefer distribution packages or the container image, while being open to
contributed build rules. Upstream images are based on Fedora packages, so they can lag
behind upstream releases
([podman-container-tools/buildah#6902](https://github.com/podman-container-tools/buildah/issues/6902)).

Distribution packages are often several releases behind, and some environments (CI
runners, minimal or non-Linux-distribution hosts) have no package at all. This project
fills that gap with:

- static binaries for `linux/amd64` and `linux/arm64` (more on request),
- `.deb` and `.rpm` packages of the same binaries that replace the distribution's
  `skopeo` package,
- a multi-arch image based on Alpine, with a shell for use as a CI job image,
- every maintained upstream minor version (1.11 and newer), not only the newest one.

## Install

### apt (Debian, Ubuntu)

The apt repository follows upstream's latest release. It needs apt 2.3.10 or newer
(Debian 12, Ubuntu 22.04 and later) for the inline key in the sources file:

```sh
curl -fsSL https://raw.githubusercontent.com/podman-container-tools-community/skopeo/main/packaging/apt/skopeo.sources |
  sudo tee /etc/apt/sources.list.d/skopeo.sources
sudo apt update
sudo apt install skopeo
```

To stay on one release, replace `releases/latest/download` in the URI with
`releases/download/vX.Y.Z`.

The packages use epoch 2, so they stay installed when the distribution ships its own
skopeo update. To go back to the distribution's package, remove the source and run
`sudo apt install --allow-downgrades skopeo=<version>`.

### rpm (Fedora, RHEL, openSUSE)

There is no dnf repository. Download the package from the release, check its signature
(`dnf install` does not check local files) and install it:

```sh
sudo rpm --import https://raw.githubusercontent.com/podman-container-tools-community/skopeo/main/packaging/gpg.asc
rpm -K skopeo-1.24.1-1.x86_64.rpm
sudo dnf install ./skopeo-1.24.1-1.x86_64.rpm
```

`rpm -K` has to report `signatures OK`. The packages use epoch 2, so `dnf upgrade` does
not switch back to the distribution's skopeo.

The deb and rpm packages and the apt repository are signed with the GPG key in
[`packaging/gpg.asc`](packaging/gpg.asc)
(`59E1 335F 8162 F5DF FE1D  4DA9 7243 E2C2 DA62 80BC`).

## Use the image

The image has skopeo as its entrypoint, like upstream's `quay.io/skopeo/stable`:

```sh
docker run --rm ghcr.io/podman-container-tools-community/skopeo:v1 inspect docker://quay.io/libpod/alpine:latest
```

As a GitLab CI job image:

```yaml
copy:
  image:
    name: ghcr.io/podman-container-tools-community/skopeo:v1
    entrypoint: [""]
  script:
    - skopeo login --username "$CI_REGISTRY_USER" --password "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"
    - skopeo copy --all docker://quay.io/libpod/alpine:latest "docker://$CI_REGISTRY_IMAGE/alpine:latest"
```

`skopeo login` writes to `$REGISTRY_AUTH_FILE`, `/tmp/auth.json` in the image, so it
works as any user (Kubernetes `runAsUser`, `docker run --user`). The image runs as root
by default and, like upstream's, has a `skopeo` user (uid 1000) with subordinate IDs,
`newuidmap`/`newgidmap` and `fuse-overlayfs`, so `containers-storage:` also works inside
a container (`/etc/containers/storage.conf`), as root and as the `skopeo` user (with its
own `~/.config/containers/storage.conf`).

Differences from `quay.io/skopeo/stable`: Alpine instead of Fedora (BusyBox `sh`, no
`bash`), `linux/amd64` and `linux/arm64` only, no GPG signing (see
[Limitations](#limitations)), and only `vX.Y.Z-immutable` as immutable tag. Upstream also
has `vX-immutable` and `vX.Y-immutable`, but those are pushed once and therefore stay at
the first release of that line. `vX.Y.Z` can be rebuilt on a newer base image, weekly
for the newest release of every minor (see [Release flow](#release-flow));
`vX.Y.Z-immutable` and the digest never change.

## Trust model

This repository contains **only build configuration**. Nothing here can change what is
compiled:

- Source comes from the Go module proxy (`proxy.golang.org`) at the upstream tag and is
  verified against the Go checksum database (`sum.golang.org`), using
  [goreleaser verifiable builds](https://goreleaser.com/customization/builds/verifiable_builds/).
  Dependencies and their hashes are upstream's own `go.sum`.
- Builds run only in GitHub Actions. Binaries and checksums are signed keyless with
  [cosign](https://github.com/sigstore/cosign) via GitHub OIDC, images are signed the
  same way, and every file in `checksums.txt` gets a GitHub build provenance
  attestation.
- The apt repository metadata (`InRelease`) and the rpm packages are additionally signed
  with a GPG key, because apt and rpm cannot verify sigstore signatures; apt verifies
  the deb packages through the checksums in the signed `InRelease`. The key is kept in
  this repository's secrets and used only by the release workflow.
- Builds are reproducible: with the same Go version, anyone gets bit-for-bit identical
  binaries.

## Which versions are released

Every upstream [GitHub release](https://github.com/podman-container-tools/skopeo/releases)
since `v1.11.0`, drafts and prereleases excluded
([`hack/upstream-releases.sh`](hack/upstream-releases.sh)). Upstream maintains several
minor versions at once (1.11, 1.14, 1.18, 1.20 and 1.22 all had patch releases in 2026),
so there is no version list to maintain here.

## Release flow

1. [`sync.yaml`](.github/workflows/sync.yaml) runs every 6 hours, on every push to `main`
   and on demand. For every upstream release that has no tag here yet, it creates the tag
   on the current commit and dispatches [`release.yaml`](.github/workflows/release.yaml)
   on it.
2. `release.yaml` builds that tag: GitHub release, images on `ghcr.io`, signatures and
   attestations. Image tags: `vX.Y.Z` always, `vX.Y` for the newest release of a minor,
   `vX` and `latest` for upstream's latest release. `vX.Y.Z-immutable` is pushed only by
   the release itself and never moves.
3. Before anything is published, [`test.yaml`](.github/workflows/test.yaml) builds the
   release and runs two [bats-core](https://github.com/bats-core/bats-core) suites.
   [`test/functional.bats`](test/functional.bats) uses the amd64 binary: copies between
   registries, OCI layouts, `dir:` and `containers-storage:` (overlay), plus `inspect`,
   `sync` and `list-tags`. [`test/image.bats`](test/image.bats) uses the image built from
   the release: `skopeo login` as root and as uid 1000, the `skopeo` user and its
   subordinate IDs and `newuidmap`, and `containers-storage:` with fuse-overlayfs as root
   and rootless. Upstream's own integration tests are not run, because for older releases
   they fail on registry content that changed since and on test infrastructure that no
   longer exists, not on the binary.
4. [`ci.yaml`](.github/workflows/ci.yaml) runs `test.yaml` for the newest release of every
   minor version on pull requests.

A release can also be started by hand for an existing tag:

```sh
gh workflow run release.yaml --ref v1.24.1
```

Tags point at the commit that was current when they were created, so a run on a tag uses
that commit's `Dockerfile`. To rebuild only the images of existing releases with the
current `Dockerfile`, for example after a base image change, run `release.yaml` on `main`
with the `images` input. It builds with the Go version of the release, checks that the
binaries match the released ones, then pushes and signs the image tags; the
`-immutable` tag, the GitHub release, its assets and the packages stay unchanged:

```sh
gh workflow run release.yaml --ref main -f images=v1.24.1
```

[`rebuild.yaml`](.github/workflows/rebuild.yaml) does this automatically every week for
the newest release of every minor, and after a merge to `main` that changes the
`Dockerfile`, `packaging/image` or `.goreleaser.yaml`. Its `all` input rebuilds every
release:

```sh
gh workflow run rebuild.yaml --repo podman-container-tools-community/skopeo -f all=true
```

## How it works

- The workflows check out upstream skopeo at the release tag into the workspace root and
  this repository into `.build/`. [`.github/actions/setup`](.github/actions/setup/action.yaml)
  hides `.build/` from Git (`.git/info/exclude`), so goreleaser sees a clean upstream
  checkout and takes module path, `go.sum`, tag and `default-policy.json` from it. The
  goreleaser configuration and `Dockerfile` are used from `.build/`.
- goreleaser's `gomod.proxy` then compiles `<module>/cmd/skopeo@<tag>` from the Go module
  proxy, verified against sum.golang.org, rather than from the checkout. The module path
  changed from `github.com/containers/skopeo` to `go.podman.io/skopeo` in 1.23; both work.
- Every release is built with the newest stable Go, not the version in upstream's
  `go.mod` (only a minimum, and end-of-life for older releases: `go 1.19` for 1.14.x).
  Exceptions for releases whose pinned dependencies break with the newest Go are listed
  in [`.github/actions/setup`](.github/actions/setup/action.yaml): 1.23.x uses Go 1.26.
  The Go version used is recorded in each binary (`go version -m`).
- skopeo is built with cgo and linked statically against musl, with
  [zig](https://ziglang.org) as C compiler for both architectures. cgo is needed for
  rootless `containers-storage:`: containers/storage enters the user namespace from a C
  constructor (`pkg/unshare`).
- Build tags leave out what needs shared C libraries: `containers_image_openpgp`
  (pure-Go OpenPGP instead of gpgme), `exclude_graphdriver_btrfs` and
  `exclude_graphdriver_devicemapper` (needed up to 1.15).
- The upstream commit is passed with `-X main.gitCommit`, as upstream's Makefile does.
  From 1.21 on skopeo reads it from Go's VCS build info instead, which a module-proxy
  build lacks, so `skopeo --version` shows no commit there.
- The release is signed keyless with cosign through GitHub OIDC: the checksum file
  (`checksums.txt.sigstore.json`) and the images. A GitHub build provenance
  attestation is created for every file in `checksums.txt`.

## Verify a binary

Download the binary (or archive, or package), `checksums.txt` and `checksums.txt.sigstore.json` from
the release. The examples use skopeo `v1.24.1`.

1. **Signature of the checksums**, proving the file came from this repository's workflow:

   ```sh
   cosign verify-blob \
     --certificate-identity-regexp '^https://github.com/podman-container-tools-community/skopeo/\.github/workflows/release\.yaml@' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     --bundle checksums.txt.sigstore.json \
     checksums.txt
   ```

2. **Checksum of the binary**:

   ```sh
   sha256sum --check --ignore-missing checksums.txt
   ```

3. **Build provenance** (optional, needs the GitHub CLI):

   ```sh
   gh attestation verify skopeo-linux-amd64 --repo podman-container-tools-community/skopeo
   ```

4. **Source**: the module hash embedded in the binary must match the Go checksum database,
   which proves the binary was built from the upstream tag:

   ```sh
   go version -m skopeo-linux-amd64 | grep -P '^\tmod'
   # mod  go.podman.io/skopeo  v1.24.1  h1:QJdN+2hXYrYbOxhvU1PMmnFJGpvNM+feoRvxKXqxciQ=
   curl -s https://sum.golang.org/lookup/go.podman.io/skopeo@v1.24.1
   # go.podman.io/skopeo v1.24.1 h1:QJdN+2hXYrYbOxhvU1PMmnFJGpvNM+feoRvxKXqxciQ=
   ```

   Before 1.23 the module path is `github.com/containers/skopeo`.

### Verify an image

```sh
cosign verify ghcr.io/podman-container-tools-community/skopeo:v1.24.1 \
  --certificate-identity-regexp '^https://github.com/podman-container-tools-community/skopeo/\.github/workflows/release\.yaml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Reproduce a build

See [Reproduce locally](#reproduce-locally). Use the Go version shown by `go version -m`
on the released binary.

## Limitations

The binaries are static, linked against musl. Compared to a distribution package, this
means:

- **No GPG signing.** `skopeo copy --sign-by <fingerprint>` and `skopeo standalone-sign`
  fail with "signing is not supported". Verifying GPG signatures through `policy.json`
  (`signedBy` with `keyPath`) works. Sigstore signing and verification work fully.
  Without `keyPath`, only the legacy `~/.gnupg/pubring.gpg` is read, not `pubring.kbx`.
- **No Sequoia-PGP** signature backend.
- **No btrfs or devicemapper storage driver.** overlay and vfs work for
  `containers-storage:`, as root and rootless.
- **No libsubid.** Subordinate ID ranges served by NSS providers (sssd, FreeIPA) are not
  supported; libsubid loads those with `dlopen`, which is impossible in a static binary.
- **No NSS.** musl has none: user lookups read `/etc/passwd` only, and name resolution
  uses `/etc/hosts` and DNS only: no LDAP users, mDNS (`.local`) or systemd-resolved
  specific behaviour.
- **No default configuration.** The binary does not install
  `/etc/containers/policy.json`; the archive contains upstream's default as
  `default-policy.json`, and the image ships it at `/etc/containers/policy.json`.
  The packages recommend the distribution's package that owns
  `/etc/containers/policy.json` (`golang-github-containers-common` on Debian and
  Ubuntu, `containers-common` on rpm distributions) and ship upstream's default as
  `/usr/share/doc/skopeo/default-policy.json`.
- **No commit in `skopeo --version` from 1.21 on.** Up to 1.20 the commit is set at
  link time like upstream does (`-X main.gitCommit`). Newer releases read it from Go's
  VCS build info, which a module-proxy build does not have; `go version -m` shows the
  exact module version and hash instead.
- **Linux only**, `amd64` and `arm64`.

## Reproduce locally

```sh
git clone --branch v1.24.1 https://github.com/podman-container-tools/skopeo
cd skopeo
git clone https://github.com/podman-container-tools-community/skopeo .build
printf '/.build/\n/dist/\n/.zig-cache/\n' >> .git/info/exclude
GITHUB_REPOSITORY_OWNER=podman-container-tools-community GITHUB_REPOSITORY=podman-container-tools-community/skopeo \
GITHUB_REPOSITORY_NAME=skopeo IS_LATEST=false IS_LATEST_MINOR=false \
  goreleaser release --config .build/.goreleaser.yaml --clean --skip=publish,sign,docker,sbom
```

Needs Go, goreleaser and zig 0.17.0 (`CC` is set in `.goreleaser.yaml`). With the same Go
and zig versions (see `go version -m`), the binaries are bit-for-bit identical.

## Layout

This repository is checked out to `.build/` inside an upstream checkout.

```
.goreleaser.yaml                     build, archive, package, image and signing configuration
Dockerfile                           image on Alpine; packages cross-installed with apk, no emulation
hack/upstream-releases.sh            upstream releases to build
hack/functional-test.sh              run test/functional.bats against a built binary
hack/image-test.sh                   build the image from a dist directory, run test/image.bats
hack/install-bats.sh                 install the pinned bats-core release, SHA-256 checked
hack/update-checksums.sh             recompute the sha256 pins after a version bump
test/functional.bats                 functional tests for the binary
test/image.bats                      tests for the image
.github/actions/setup/               hide .build/ from Git, pick and install Go, zig, syft, goreleaser
.github/workflows/test.yaml          build one release, run functional and image tests
.github/workflows/ci.yaml            pull requests: test.yaml for newest release per minor
.github/workflows/sync.yaml          schedule and main: tag new releases, dispatch release.yaml
.github/workflows/rebuild.yaml       weekly and on image changes: dispatch image rebuilds
.github/workflows/release.yaml       dispatch on a tag: test.yaml, then release, images, signing;
                                     on main with -f images=<tag>: rebuild images only
.github/workflows/renovate.yaml      Renovate pull requests: commit recomputed sha256 pins
packaging/gpg.asc                    public GPG key for packages and the apt repository
packaging/apt/skopeo.sources         apt source for the latest release
packaging/image/storage.conf         containers-storage configuration in the image
renovate.json                        base image, action and bats-core updates
```

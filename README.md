# skopeo (community build)

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
- a multi-arch image based on `gcr.io/distroless/static-debian13`,
- every maintained upstream minor version (1.11 and newer), not only the newest one.

## Trust model

This repository contains **only build configuration**. Nothing here can change what is
compiled:

- Source comes from the Go module proxy (`proxy.golang.org`) at the upstream tag and is
  verified against the Go checksum database (`sum.golang.org`), using
  [goreleaser verifiable builds](https://goreleaser.com/customization/builds/verifiable_builds/).
  Dependencies and their hashes are upstream's own `go.sum`.
- Builds run only in GitHub Actions. Binaries and checksums are signed keyless with
  [cosign](https://github.com/sigstore/cosign) via GitHub OIDC, images are signed the
  same way, and every file gets a GitHub build provenance attestation.
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
   `vX` and `latest` for upstream's latest release.
3. Before anything is published, [`test.yaml`](.github/workflows/test.yaml) builds the
   release and runs [`hack/functional-test.sh`](hack/functional-test.sh) against the
   amd64 binary: copies between registries, OCI layouts, `dir:` and `containers-storage:`
   (overlay), plus `inspect` and `sync`. Upstream's own integration tests are not run,
   because for older releases they fail on registry content that changed since and on
   test infrastructure that no longer exists, not on the binary.
4. [`ci.yaml`](.github/workflows/ci.yaml) runs `test.yaml` for the newest release of every
   minor version on pull requests.

A release can also be started by hand for an existing tag:

```sh
gh workflow run release.yaml --ref v1.24.1
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
- Build tags match upstream's own `DISABLE_CGO=1` builds: `containers_image_openpgp`
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

The binaries are static and built without cgo (`CGO_ENABLED=0`). Compared to a
distribution package, this means:

- **No GPG signing.** `skopeo copy --sign-by <fingerprint>` and `skopeo standalone-sign`
  fail with "signing is not supported". Verifying GPG signatures through `policy.json`
  (`signedBy` with `keyPath`) works. Sigstore signing and verification work fully.
  Without `keyPath`, only the legacy `~/.gnupg/pubring.gpg` is read, not `pubring.kbx`.
- **No Sequoia-PGP** signature backend.
- **No btrfs storage driver.** overlay and vfs work for `containers-storage:` from 1.18
  on. **Up to 1.17 only vfs works**: containers/storage registered the overlay driver
  for cgo builds only, so `[overlay@...]` fails with "driver not supported".
- **No libsubid.** Rootless user namespaces still work: `/etc/subuid` and `/etc/subgid`
  are read directly and `newuidmap`/`newgidmap` are used. Subordinate ID ranges served
  by NSS providers (sssd, FreeIPA) are not supported; libsubid loads those with
  `dlopen`, which is impossible in a static binary.
- **No NSS.** User lookups read `/etc/passwd` only, and name resolution uses
  `/etc/hosts` and DNS only: no LDAP users, mDNS (`.local`) or systemd-resolved
  specific behaviour.
- **No default configuration.** The binary does not install
  `/etc/containers/policy.json`; the archive contains upstream's default as
  `default-policy.json`, and the image ships it at `/etc/containers/policy.json`.
  The `.deb` and `.rpm` packages recommend the distribution's `containers-common`,
  which owns `/etc/containers/policy.json`, and ship upstream's default as
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
printf '/.build/\n/dist/\n' >> .git/info/exclude
GITHUB_REPOSITORY_OWNER=podman-container-tools-community GITHUB_REPOSITORY=podman-container-tools-community/skopeo \
GITHUB_REPOSITORY_NAME=skopeo IS_LATEST=false IS_LATEST_MINOR=false \
  goreleaser release --config .build/.goreleaser.yaml --clean --skip=publish,sign,docker,sbom
```

With the same Go version (see `go version -m`), the binaries are bit-for-bit identical.

## Layout

This repository is checked out to `.build/` inside an upstream checkout.

```
.goreleaser.yaml                     build, archive, package, image and signing configuration
Dockerfile                           image, COPY only (no emulation needed for arm64)
hack/upstream-releases.sh            upstream releases to build
hack/functional-test.sh              functional tests for a built binary
.github/actions/setup/               hide .build/ from Git, pick and install Go, syft, goreleaser
.github/workflows/test.yaml          build one release, run functional tests
.github/workflows/ci.yaml            pull requests: test.yaml for newest release per minor
.github/workflows/sync.yaml          schedule and main: tag new releases, dispatch release.yaml
.github/workflows/release.yaml       dispatch on a tag: test.yaml, then release, images, signing
renovate.json                        base image and action updates
```

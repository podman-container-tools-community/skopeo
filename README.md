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

The repository only serves the newest release: after a new upstream release, the `.deb`
URLs in an older cached index are gone (404), so run `sudo apt update` before
`apt install` or `apt upgrade`. To stay on one release, replace
`releases/latest/download` in the URI with `releases/download/vX.Y.Z`.

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
own `~/.config/containers/storage.conf`). Any other uid takes `graphroot` from
`/etc/containers/storage.conf`, which only root can write, as in upstream's image: give it
its own `storage.conf` via `CONTAINERS_STORAGE_CONF` for rootless storage.

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
- Every release is built with the newest stable Go, not the minimum in upstream's
  `go.mod` (exceptions are listed in [`.github/actions/setup`](.github/actions/setup/action.yaml)).
  The Go version used is recorded in each binary (`go version -m`).
- Builds are reproducible: with the same Go and zig versions, anyone gets bit-for-bit
  identical binaries.

## Which versions are released

Every upstream [GitHub release](https://github.com/podman-container-tools/skopeo/releases)
since `v1.11.0`, drafts and prereleases excluded
([`hack/upstream-releases.sh`](hack/upstream-releases.sh)). Upstream maintains several
minor versions at once (1.11, 1.14, 1.18, 1.20 and 1.22 all had patch releases in 2026),
so there is no version list to maintain here.

## Release flow

New upstream releases are picked up automatically, usually within six hours. Each
release is built and tested ([`test/`](test)) before anything is published, then
released here with binaries, packages, the apt repository and images on `ghcr.io`, all
signed.

Image tags: `vX.Y.Z` and `vX.Y.Z-immutable` always, `vX.Y` for the newest release of a
minor, `vX` and `latest` for the newest upstream release by version (not upstream's
GitHub "latest" flag, which a backport release of an older minor can take).
`vX.Y.Z-immutable` is pushed once by the release and never moves.

Releases are built by the pipeline on `main`; the release notes name the pipeline
commit. The release's Git tag in this repository only anchors the GitHub release (it
points at the repository's first commit) and never moves.

Images are rebuilt without a new release when the Alpine base image or its packages
change: weekly for the newest release of every minor, and after changes to the image
definition. A rebuild takes the released archives, checks them against the
cosign-signed `checksums.txt` and builds the image with the current `Dockerfile`, so the
images always contain exactly the released binaries. It updates every tag of that
release except `vX.Y.Z-immutable`, which keeps the digest of the original release.

## Verify a binary

Download the binary (or archive, or package), `checksums.txt` and `checksums.txt.sigstore.json` from
the release. The examples use skopeo `v1.24.1`.

1. **Signature of the checksums**, proving the file came from this repository's release
   workflow on `main`:

   ```sh
   cosign verify-blob \
     --certificate-identity https://github.com/podman-container-tools-community/skopeo/.github/workflows/release.yaml@refs/heads/main \
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

Every image, released or rebuilt, is signed by the `images.yaml` workflow on `main`:

```sh
cosign verify ghcr.io/podman-container-tools-community/skopeo:v1.24.1 \
  --certificate-identity https://github.com/podman-container-tools-community/skopeo/.github/workflows/images.yaml@refs/heads/main \
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
  `containers-storage:`, as root and rootless. Rootless needs user namespaces: Ubuntu
  24.04 and newer restrict them through AppArmor (`unshare(...): Operation not
  permitted`) unless a profile allows `userns` for the binary or
  `kernel.apparmor_restrict_unprivileged_userns` is 0.
- **No libsubid.** Subordinate ID ranges served by NSS providers (sssd, FreeIPA) are not
  supported; libsubid loads those with `dlopen`, which is impossible in a static binary.
- **No NSS.** musl has none: user lookups read `/etc/passwd` only, and name resolution
  uses `/etc/hosts` and DNS only: no LDAP users, mDNS (`.local`) or systemd-resolved
  specific behaviour.
- **No default configuration.** The binary does not install
  `/etc/containers/policy.json`; the archive contains upstream's default as
  `default-policy.json`, and the image ships it at `/etc/containers/policy.json`.
  The packages depend on the distribution's package that owns
  `/etc/containers/policy.json` (`golang-github-containers-common` on Debian and
  Ubuntu, `containers-common` on rpm distributions), because skopeo fails without
  it, and ship upstream's default as `/usr/share/doc/skopeo/default-policy.json`.
- **No commit in `skopeo --version` from 1.21 on.** Up to 1.20 the commit is set at
  link time like upstream does (`-X main.gitCommit`). Newer releases read it from Go's
  VCS build info, which a module-proxy build does not have; `go version -m` shows the
  exact module version and hash instead.
- **The apt repository serves only the newest release.** Its sources point at
  `releases/latest/download`, so once a new upstream release is published, the `.deb`
  URLs in a cached index return 404 until `sudo apt update` runs (see
  [apt](#apt-debian-ubuntu)). This is by design; there is no package pool with older
  releases.
- **Linux only**, `amd64` and `arm64`.

## Reproduce locally

Needs Go and [mise](https://mise.jdx.dev), which installs zig, goreleaser and syft from
`.build/mise.lock`:

```sh
git clone --branch v1.24.1 https://github.com/podman-container-tools/skopeo
cd skopeo
git clone https://github.com/podman-container-tools-community/skopeo .build
printf '/.build/\n/dist/\n/.zig-cache/\n' >> .git/info/exclude
(cd .build && mise install)
eval "$(mise env -C .build)"
.build/hack/build-sysroot.sh /tmp/sysroot
SYSROOT=/tmp/sysroot GOTOOLCHAIN=local \
GITHUB_REPOSITORY_OWNER=podman-container-tools-community GITHUB_REPOSITORY=podman-container-tools-community/skopeo \
  goreleaser release --config .build/.goreleaser.yaml --clean --skip=publish,sign,sbom
```

With the same Go version (see `go version -m`) and the zig version from
[`mise.toml`](mise.toml) at the pipeline commit named in the release notes, the
binaries are bit-for-bit identical.
How to run the tests is described in [`AGENTS.md`](AGENTS.md).

## Contributing

Bug reports and pull requests are welcome. [`CONTRIBUTING.md`](CONTRIBUTING.md) explains
how to report a problem, what changes we accept and how to propose one. How the build
works, how to run the tests and the release workflows are described in
[`AGENTS.md`](AGENTS.md).

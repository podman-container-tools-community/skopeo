# AGENTS.md

Notes for maintainers and coding agents working on this repository.
[`README.md`](README.md) is for users: install, image, verification and limitations.
[`CONTRIBUTING.md`](CONTRIBUTING.md) is the short guide for people contributing: issues,
pull requests and what reviewers expect. This file covers how the build works, how to test changes and the rules for changing
the repository.

## What this repository is

- Build configuration only, for community builds of upstream
  [skopeo](https://github.com/podman-container-tools/skopeo). Upstream source is never
  vendored, patched or copied in; it comes from the Go module proxy at the upstream tag
  (see "Trust model" in `README.md`). A change that would alter what gets compiled does
  not belong here.
- One of three sibling repositories built the same way:
  [skopeo](https://github.com/podman-container-tools-community/skopeo),
  [buildah](https://github.com/podman-container-tools-community/buildah) and
  [podman](https://github.com/podman-container-tools-community/podman). The org's
  [`.github`](https://github.com/podman-container-tools-community/.github) repository
  holds the shared community health files (issue templates, code of conduct, security
  policy); each repository has its own `CONTRIBUTING.md`.

## Layout

The workflows check this repository out to `.build/` inside an upstream checkout.

```
.goreleaser.yaml                     build, archive, package and signing configuration
Dockerfile                           image on Alpine; packages cross-installed with apk, no emulation
hack/upstream-releases.sh            upstream releases to build
hack/build-sysroot.sh                C headers for the static build (here only musl-compat.h)
hack/musl-compat.h                   declares basename() for releases before 1.16
hack/build-image.sh                  builds, pushes and signs the image from built or released binaries
hack/functional-test.sh              runs test/functional.bats and test/signing.bats against a built binary
hack/image-test.sh                   builds the image from a dist directory, runs test/image.bats
test/                                bats tests for the binary and the image
.github/actions/setup/               hide .build/ from Git, install Go and the mise tools, build the sysroot
.github/workflows/test.yaml          build one release, run functional and image tests
.github/workflows/ci.yaml            pull requests: test.yaml for newest release per minor
.github/workflows/lint.yaml          pull requests: super-linter
.github/workflows/sync.yaml          schedule and main: tag new releases, dispatch release.yaml on main
.github/workflows/release.yaml       dispatch on main with a version: test.yaml, release, images.yaml, publish
.github/workflows/images.yaml        called by release.yaml and rebuild.yaml: image build, test, push, signing
.github/workflows/rebuild.yaml       weekly and on image changes: rebuild images from released binaries
.github/linters/                     actionlint and zizmor configuration for super-linter
packaging/gpg.asc                    public GPG key for packages and the apt repository
packaging/apt/skopeo.sources         apt source for the latest release
packaging/image/                     storage.conf and policy.json for the image
renovate.json                        base image, action, mise tool and sysroot updates
mise.toml, mise.lock                 zig, goreleaser, syft, cosign and bats, installed with mise
```

## How the build works

- The workflows check out upstream skopeo at the release tag into the workspace root and
  this repository into `.build/`. [`.github/actions/setup`](.github/actions/setup/action.yaml)
  hides `.build/` from Git (`.git/info/exclude`), so goreleaser sees a clean upstream
  checkout and takes module path, `go.sum`, tag and `default-policy.json` from it. The
  goreleaser configuration is used from `.build/`.
- goreleaser's `gomod.proxy` then compiles `<module>/cmd/skopeo@<tag>` from the Go module
  proxy, verified against sum.golang.org, rather than from the checkout. The module path
  changed from `github.com/containers/skopeo` to `go.podman.io/skopeo` in 1.23; both work.
  A release whose `go.mod` has `replace` directives is built from the checkout instead
  (`proxy: false`, picked by the setup action), because the module proxy ignores them.
- Before goreleaser runs, the setup action downloads the modules with `go mod download`
  and retries it up to five times, because proxy.golang.org sometimes cuts a download off
  and neither go build nor goreleaser (which retries only its `go get`, on a 404) retries
  that. goreleaser then finds the modules in the module cache.
- Every release is built with the newest stable Go, not the version in upstream's
  `go.mod` (only a minimum, and end-of-life for older releases: `go 1.19` for 1.14.x),
  with `GOTOOLCHAIN=local`. Exceptions for releases whose pinned dependencies break with
  the newest Go are listed in the `setup-go` step of
  [`.github/actions/setup`](.github/actions/setup/action.yaml): 1.23.x uses Go 1.26.
- skopeo is built with cgo and linked statically against musl, with
  [zig](https://ziglang.org) as C compiler for both architectures (`zig cc -target
  <arch>-linux-musl`), from one goreleaser run on an amd64 runner. cgo is needed for
  rootless `containers-storage:`: containers/storage enters the user namespace from a C
  constructor (`pkg/unshare`); a cgo-free build re-executes itself endlessly. Before 1.16
  that code calls `basename()` without including `libgen.h`, which musl 1.2.4 requires,
  so for those releases [`hack/musl-compat.h`](hack/musl-compat.h) is included into
  every C file.
- Per-architecture build settings (`CC`) are templated `env` entries in
  `.goreleaser.yaml` (`{{- if and (eq .Os "linux") (eq .Arch "amd64") }}...`), not
  `overrides`.
- Build tags leave out what needs shared C libraries: `containers_image_openpgp`
  (pure-Go OpenPGP instead of gpgme), `exclude_graphdriver_btrfs` and
  `exclude_graphdriver_devicemapper` (needed up to 1.15).
- The upstream commit is passed with `-X main.gitCommit`, as upstream's Makefile does.
  From 1.21 on skopeo reads it from Go's VCS build info instead, which a module-proxy
  build lacks, so `skopeo --version` shows no commit there.
- `-extldflags '-static -s'` strips the binaries. That also strips the build paths of
  the C objects, which is what keeps builds bit-for-bit reproducible; do not remove it.
- The image is built by [`hack/build-image.sh`](hack/build-image.sh) from the binaries
  goreleaser built (or, for rebuilds, the released archives) and `packaging/image/`,
  with Docker buildx for both architectures, then signed with cosign. The same script
  builds the image for the tests, so the image build is exercised on every pull request.
- The release is signed keyless with cosign through GitHub OIDC: the checksum file
  (`checksums.txt.sigstore.json`) and the images. A GitHub build provenance attestation
  is created for every file in `checksums.txt`. The apt repository and rpm packages are
  also signed with the GPG key from the repository secrets.

## Build and test locally

Tools come from [mise](https://mise.jdx.dev): `mise install` reads
[`mise.toml`](mise.toml) and [`mise.lock`](mise.lock), which pin zig, goreleaser, syft,
cosign and bats with their download checksums. Go is not in mise, because its version
depends on the release being built. Run the `hack/` scripts with mise activated or
through `mise exec --`.

Build a release as described in "Reproduce locally" in `README.md`. Then, from the
upstream checkout:

```sh
mise exec -C .build -- .build/hack/functional-test.sh dist/skopeo_linux_amd64_v1/skopeo localhost:5000
mise exec -C .build -- .build/hack/image-test.sh dist
```

`functional-test.sh` needs a plain-HTTP registry (`docker run -d -p 5000:5000
registry:3`), network access to quay.io, gpg, jq and, unless run as root, sudo.
`image-test.sh` needs Docker with buildx. On Ubuntu 24.04 and newer, rootless tests
need `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`.

[`lint.yaml`](.github/workflows/lint.yaml) runs super-linter on pull requests:
shellcheck, shfmt, hadolint, actionlint, zizmor, gitleaks, codespell, textlint,
EditorConfig, JSON, Renovate config and `goreleaser check`. Shell scripts use two-space
indentation ([`.editorconfig`](.editorconfig)) and `set -euo pipefail`.

## Tests

[`test.yaml`](.github/workflows/test.yaml) builds one release without publishing and
runs three [bats-core](https://github.com/bats-core/bats-core) suites, each case
reported in TAP:

- [`test/functional.bats`](test/functional.bats) uses the amd64 binary: copies between
  registries, OCI layouts, `dir:` and `containers-storage:` (overlay), plus `inspect`,
  `sync` and `list-tags`.
- [`test/signing.bats`](test/signing.bats) signs with a sigstore key and verifies
  sigstore and GPG (simple signing) signatures through a `policy.json`, and checks that
  `--sign-by` fails with a clear error.
- [`test/image.bats`](test/image.bats) uses the image built from the release:
  `skopeo login` as root and as uid 1000, the `skopeo` user and its subordinate IDs and
  `newuidmap`, and `containers-storage:` with fuse-overlayfs as root and rootless.

Conventions:

- One `@test` per check. [`test/helpers.bash`](test/helpers.bash) has `expect_output`;
  there is no bats-assert.
- Use `run --separate-stderr` when the output is parsed (jq, `expect_output`):
  containers/storage logs warnings to stderr on some kernels.
- The images have BusyBox `sh` only, no Bash: commands inside the image run with
  `sh -c`.
- Tests run on amd64 only, inside the single `build` job of `test.yaml`. arm64 is built
  and checked to be static, but not tested; do not add arm64 or separate test jobs. New
  tests go into the existing suites or that job.
- Upstream's own integration tests are not run: for older releases they fail on
  registry content that changed since (registry.k8s.io tag lists), an OpenShift 1.5
  cluster and upstream's CI VMs, not on the binary.

## CI and release workflows

- [`ci.yaml`](.github/workflows/ci.yaml) runs `test.yaml` on pull requests for the
  newest release of every minor version. Its `fail` job is the single required check: it
  is skipped when everything passed (which counts as passed) and fails when a job failed
  or was cancelled. Keep it that way; do not make it run always.
- [`sync.yaml`](.github/workflows/sync.yaml) runs every 6 hours, on every push to `main`
  and on demand. For every upstream release (from
  [`hack/upstream-releases.sh`](hack/upstream-releases.sh), `v1.11.0` and newer) that has
  no published release here yet, it creates the tag on the repository's first commit
  (if missing) and dispatches [`release.yaml`](.github/workflows/release.yaml) on `main`
  with the version as input, newest first, at most `MAX_RELEASES_PER_RUN` per run
  (repository variable, default 10). Only a 404 counts as "no release" or "no tag"; any
  other API error stops the run, so a flaky API never starts a second release.
- `release.yaml` runs on `main` only (it fails on any other ref, before the build) and
  takes the upstream tag as `version` input, so every release is built by the current
  pipeline and signed as `release.yaml@refs/heads/main`. The release's tag never moves
  and carries no pipeline state; the pipeline commit is in the release notes
  (`PIPELINE_COMMIT`). It runs `test.yaml` first, then creates the draft release with
  binaries, packages, apt repository, signatures and attestations, calls `images.yaml`
  for the images on `ghcr.io` and publishes the release only when those are pushed.
  Image tags: `vX.Y.Z` and `vX.Y.Z-immutable` always, `vX.Y` for the newest release of a
  minor, `vX` and `latest` for the newest upstream release by version.
  `vX.Y.Z-immutable` is pushed only by the release itself and never moves: it is a copy
  of the signed manifest list, made after the signature, so a retried run finds a signed
  tag and keeps it.
- [`images.yaml`](.github/workflows/images.yaml) (`workflow_call`) builds, tests, pushes
  and signs the images of one release from its archives, verified against the
  cosign-signed `checksums.txt`, with the current `Dockerfile`. `release.yaml` calls it
  with `immutable: true` and the archives as an Actions artifact (the release is still a
  draft), then publishes the release; `rebuild.yaml` calls it per release. One caller
  file means one signing identity for every image: `images.yaml@refs/heads/main`; it
  fails when called on any other ref. The archives are downloaded by their exact names
  and have to be listed in the verified `checksums.txt`.
- [`rebuild.yaml`](.github/workflows/rebuild.yaml) rebuilds images without a new release:
  weekly for the newest release of every minor, after a merge to `main` that changes the
  `Dockerfile`, `packaging/image` or `hack/build-image.sh`, and on demand. It only lists
  the releases and calls `images.yaml` for each, which updates every tag of that release
  except `vX.Y.Z-immutable`. No toolchain is involved.
- `sync.yaml` and `rebuild.yaml` do nothing until the repository variable
  `RELEASES_ENABLED` is `true`, so pull requests can be merged without creating tags or
  releases. Setting that variable and starting releases by hand is the maintainer's
  call:

  ```sh
  gh workflow run release.yaml --ref main -f version=v1.24.1
  gh workflow run rebuild.yaml -f version=v1.24.1   # or -f all=true
  ```

- GitHub's releases API sometimes answers with empty or truncated pages.
  `hack/upstream-releases.sh` retries and accepts the list only if it contains upstream's
  latest release and reaches back to `MIN_VERSION`; keep that check. The symptom of a
  bad list is "Matrix vector 'version' does not contain any values".

## Rules

- Work through pull requests; never push to `main`. Sign off every commit
  (`git commit -s`) for the DCO.
- Keep skopeo, buildah and podman equal: same filenames, workflow and step structure,
  script interfaces and wording, differing only where the tool needs it. A change to
  one repository is ported to the other two, one pull request per repository. Each
  repository stays self-contained: no reusable workflows, composite actions or
  templates shared across repositories.
- Never use a cache in a release. Only `ci.yaml` passes `cache: true` to `test.yaml`
  (the C sysroot in the Actions cache); `release.yaml`, `rebuild.yaml` and any new
  workflow that publishes build everything from source, against cache poisoning.
- Pin everything. Actions by commit SHA with a version comment, tools in `mise.lock`,
  C dependencies in `hack/build-sysroot.sh` with a
  `# renovate: datasource=<datasource> depName=<name>` comment above the version line
  (and its sha256 or commit on the line after). Renovate runs on Fridays (Europe/Berlin)
  with a 7-day minimum release age and automerges everything but major updates.
- Runners are `ubuntu-26.04`. zig is pinned in `mise.toml`; the Go version comes from
  the setup action, and an exception there needs a comment with the error it avoids.
- The image is Alpine with BusyBox `sh`; do not add Bash. The binary has no GPG
  signing (verification works), no libsubid and no NSS; these are accepted limitations
  of a static musl build and documented in `README.md`.
- Known limitation, by design: the apt repository lives in the GitHub release that
  `latest` points to (`releases/latest/download`), so `.deb` URLs from a cached index
  return 404 after a new release until `apt update` runs. A rolling package-pool
  release that keeps older packages was considered and not chosen; don't add one
  without the maintainer's decision. It is documented under "Limitations" in
  `README.md`.
- Signing identities are the workflow file at `refs/heads/main`: `release.yaml` for
  `checksums.txt`, `images.yaml` for every image. `release.yaml` and `rebuild.yaml`
  must keep running on `main` only, and images are signed only inside `images.yaml`; a
  signature from another ref or file changes what users have to accept when verifying.
- Pull requests that only change Markdown build nothing (`ci.yaml` skips `test`).
- Keep `README.md` user-facing and `CONTRIBUTING.md` short and written for people
  contributing; link here instead of repeating details. Build internals, tests,
  workflows and rules belong here.

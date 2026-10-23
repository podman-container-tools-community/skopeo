# Contributing

Thanks for helping out! This repository builds and publishes community builds of upstream
[skopeo](https://github.com/podman-container-tools/skopeo): static binaries, packages and
container images. It holds build and release configuration only. Changes to skopeo itself
belong [upstream](https://github.com/podman-container-tools/skopeo).

## Reporting a problem

- **Something wrong with our binaries, packages, images or releases**: open an
  [issue](https://github.com/podman-container-tools-community/skopeo/issues/new/choose) here.
  Tell us the version, how you installed it (archive, apt, rpm or image) and what you ran.
- **A bug in skopeo itself**: check whether it also happens with an official build and, if
  it does, report it upstream.
- **A security issue**: don't open a public issue; follow the
  [security policy](https://github.com/podman-container-tools-community/.github/blob/main/SECURITY.md).

Missing a release, an architecture or a package format? An issue is the right place for
that too.

## What we accept

- Fixes and improvements to the build, packaging, image and workflows.
- New platforms, architectures or package formats.
- Tests and documentation.

We don't accept patches to upstream source code or builds from anything other than the
unmodified upstream release. That is what makes our builds verifiable. Dependency updates
are handled by Renovate.

## Making a change

1. For anything larger than a small fix, open an issue first so we can agree on the
   approach before you spend time on it.
2. Fork the repository and work on a branch.
3. Sign off every commit (`git commit -s`) to certify the
   [Developer Certificate of Origin](https://developercertificate.org/). The DCO check
   fails without it.
4. Open a pull request. Say what you changed, why, and how you tested it.

Every pull request builds the newest release of each minor version, runs the tests
against it and lints the repository. You don't need to run anything locally to open a
pull request, but if you want to, "Build and test locally" in [`AGENTS.md`](AGENTS.md)
has the commands.

## What reviewers look for

- **Focused changes.** One topic per pull request is quicker to review.
- **The three repositories stay alike.**
  [skopeo](https://github.com/podman-container-tools-community/skopeo),
  [buildah](https://github.com/podman-container-tools-community/buildah) and
  [podman](https://github.com/podman-container-tools-community/podman) are built the same
  way. A change that applies to all three should be made in all three; if you only change
  one, we'll help port it.
- **Pinned dependencies.** Actions by commit SHA, tools in `mise.lock`, C libraries with a
  checksum, so Renovate can keep them current.
- **Tests for new behaviour**, added to the existing bats suites in [`test/`](test).
- **User-facing documentation in [`README.md`](README.md)**, build internals in
  [`AGENTS.md`](AGENTS.md).

[`AGENTS.md`](AGENTS.md) explains how the build, the tests and the release workflows work
and lists the rules behind these points. It is written for people and coding agents
alike; you don't need to read it all for a small fix.

## Code of Conduct

Everyone taking part is expected to follow our
[Code of Conduct](https://github.com/podman-container-tools-community/.github/blob/main/CODE_OF_CONDUCT.md).

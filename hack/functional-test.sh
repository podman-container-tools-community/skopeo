#!/usr/bin/env bash
# Exercises the transports people use most with a built binary:
#   hack/functional-test.sh <skopeo> <registry host:port>
# Needs network access to quay.io, a plain-HTTP registry at <registry> and, unless run as
# root, sudo for containers-storage, and bats from mise.toml on PATH (mise install). The
# test cases are in test/functional.bats and test/signing.bats (needs gpg and jq).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
SKOPEO="$(realpath "$1")"
REGISTRY="$2"
export SKOPEO REGISTRY

bats --formatter tap "${repo}/test/functional.bats" "${repo}/test/signing.bats"

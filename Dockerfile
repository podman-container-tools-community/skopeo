# syntax=docker/dockerfile:1

# Alpine brings a shell, CA certificates, /etc/passwd, /tmp and /var/tmp, so the image
# also works as a CI job image. skopeo itself is static and needs nothing from it.
# Nothing runs during the build, so arm64 needs no emulation.
# Pinned by version and index digest so image builds stay reproducible; Renovate bumps it.
FROM alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6
ARG TARGETPLATFORM
COPY default-policy.json /etc/containers/policy.json
COPY $TARGETPLATFORM/skopeo /usr/bin/skopeo
ENTRYPOINT ["/usr/bin/skopeo"]

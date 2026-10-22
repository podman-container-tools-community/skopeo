# syntax=docker/dockerfile:1

# distroless/static brings CA certificates, /etc/passwd, /tmp and /var/tmp.
# Pinned by index digest so image builds stay reproducible; Renovate bumps it.
FROM gcr.io/distroless/static-debian13:latest@sha256:034df5c1737e8241f6ed6423a12e720ee0f6d6f088609ee172f98f6f2166ef5d
ARG TARGETPLATFORM
COPY default-policy.json /etc/containers/policy.json
COPY $TARGETPLATFORM/skopeo /usr/bin/skopeo
ENTRYPOINT ["/usr/bin/skopeo"]

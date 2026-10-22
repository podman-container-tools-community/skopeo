# syntax=docker/dockerfile:1

# Alpine brings a shell, CA certificates, /etc/passwd, /tmp and /var/tmp, so the image
# also works as a CI job image. skopeo itself is static.
# Pinned by version and index digest so image builds stay reproducible; Renovate bumps it
# (both FROM lines name the same image).
FROM alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6 AS base

# Everything that has to run happens here, on the build host's platform, so no emulation
# is needed: apk installs the target architecture's packages into a copy of the target's
# file system, without their scripts. Only what changed ends up in /delta, so the final
# image adds one layer on top of Alpine's.
FROM --platform=$BUILDPLATFORM alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6 AS delta
ARG TARGETARCH
SHELL ["/bin/ash", "-euo", "pipefail", "-c"]
# Versions come from the Alpine release the base image pins; apk cannot pin older ones,
# because the repositories only keep the newest.
# hadolint ignore=DL3018
RUN apk add --no-cache findutils tar
COPY --from=base / /rootfs/
# hadolint ignore=DL3018
RUN <<EOF
case "${TARGETARCH}" in
  amd64) arch=x86_64 ;;
  arm64) arch=aarch64 ;;
  *) echo "unsupported architecture ${TARGETARCH}" >&2; exit 1 ;;
esac
touch /marker
# Same extras as upstream's quay.io/skopeo/stable image, so containers-storage: works
# inside a container. fuse-overlayfs: overlay mount program
# (packaging/image/storage.conf). shadow-subids: newuidmap and newgidmap for rootless
# storage. ca-certificates: update-ca-certificates for CI jobs that add their own CA.
apk --root /rootfs --arch "${arch}" --no-cache --no-scripts add \
  fuse-overlayfs shadow-subids ca-certificates

# Unprivileged user with subordinate ID ranges, as in upstream's image.
echo 'skopeo:x:1000:1000:skopeo:/home/skopeo:/bin/sh' >> /rootfs/etc/passwd
echo 'skopeo:x:1000:' >> /rootfs/etc/group
echo 'skopeo:!::0:::::' >> /rootfs/etc/shadow
printf '%s\n' root:1:65535 skopeo:1:999 skopeo:1001:64535 > /rootfs/etc/subuid
cp /rootfs/etc/subuid /rootfs/etc/subgid
# Its own storage configuration: containers/storage takes runroot and graphroot from
# /etc/containers/storage.conf for rootless too, and only root can write those. Without
# them it uses ~/.local/share/containers/storage and a run directory in /tmp.
mkdir -p /rootfs/home/skopeo/.config/containers
printf '%s\n' '[storage]' 'driver = "overlay"' '' '[storage.options.overlay]' \
  'mount_program = "/usr/bin/fuse-overlayfs"' 'mountopt = "nodev,fsync=0"' \
  > /rootfs/home/skopeo/.config/containers/storage.conf
chown -R 1000:1000 /rootfs/home/skopeo

# Additional image store, as in upstream's image.
mkdir -p /rootfs/var/lib/shared/overlay-images /rootfs/var/lib/shared/overlay-layers
touch /rootfs/var/lib/shared/overlay-images/images.lock
touch /rootfs/var/lib/shared/overlay-layers/layers.lock

# ctime cannot be preserved, so -cnewer finds exactly what the steps above wrote.
mkdir /delta
find /rootfs -mindepth 1 -cnewer /marker -printf '%P\0' |
  tar -C /rootfs --null --no-recursion --xattrs --xattrs-include='security.*' -T - -cf - |
  tar -C /delta --xattrs --xattrs-include='security.*' -xpf -
EOF

FROM base
ARG TARGETPLATFORM
COPY --from=delta /delta/ /
COPY .build/packaging/image/storage.conf /etc/containers/storage.conf
COPY default-policy.json /etc/containers/policy.json
COPY $TARGETPLATFORM/skopeo /usr/bin/skopeo
# Same default as upstream's image. Without it the credentials file defaults to
# /run/containers/UID/auth.json, which only root can create, so skopeo login fails for
# any other user (Kubernetes runAsUser, docker run --user).
ENV REGISTRY_AUTH_FILE=/tmp/auth.json
# ghcr.io shows the description from this label, not from the manifest annotation.
LABEL org.opencontainers.image.description="Community-built static skopeo (upstream: github.com/podman-container-tools/skopeo)"
ENTRYPOINT ["/usr/bin/skopeo"]

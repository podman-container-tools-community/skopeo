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
ARG SKOPEO_VERSION
SHELL ["/bin/ash", "-euo", "pipefail", "-c"]
# Versions come from the Alpine release the base image pins; apk cannot pin older ones,
# because the repositories only keep the newest.
# hadolint ignore=DL3018
RUN apk add --no-cache findutils tar
COPY --from=base / /rootfs/
COPY .build/packaging/image/storage.conf /storage.conf
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
mkdir -p /rootfs/home/skopeo
chown 1000:1000 /rootfs/home/skopeo

# Additional image store, as in upstream's image.
mkdir -p /rootfs/var/lib/shared/overlay-images /rootfs/var/lib/shared/overlay-layers
touch /rootfs/var/lib/shared/overlay-images/images.lock
touch /rootfs/var/lib/shared/overlay-layers/layers.lock

# Up to 1.17 containers/storage registers the overlay driver only in cgo builds, so
# those images use vfs, with the same paths and the same kind of additional image store.
: "${SKOPEO_VERSION:?build arg SKOPEO_VERSION is required}"
mkdir -p /rootfs/etc/containers
if [ "$(printf '%s\n' "${SKOPEO_VERSION}" 1.18.0 | sort -V | head -1)" = 1.18.0 ]; then
  cp /storage.conf /rootfs/etc/containers/storage.conf
else
  {
    echo '# skopeo before 1.18 has no overlay driver without cgo: vfs instead of overlay.'
    sed -e 's/^driver = "overlay"/driver = "vfs"/' -e '/^\[storage\.options\.overlay\]/,$d' \
      /storage.conf
  } > /rootfs/etc/containers/storage.conf
  mkdir -p /rootfs/var/lib/shared/vfs-images /rootfs/var/lib/shared/vfs-layers
  touch /rootfs/var/lib/shared/vfs-images/images.lock
  touch /rootfs/var/lib/shared/vfs-layers/layers.lock
fi

# ctime cannot be preserved, so -cnewer finds exactly what the steps above wrote.
mkdir /delta
find /rootfs -mindepth 1 -cnewer /marker -printf '%P\0' |
  tar -C /rootfs --null --no-recursion --xattrs --xattrs-include='security.*' -T - -cf - |
  tar -C /delta --xattrs --xattrs-include='security.*' -xpf -
EOF

FROM base
ARG TARGETPLATFORM
COPY --from=delta /delta/ /
COPY default-policy.json /etc/containers/policy.json
COPY $TARGETPLATFORM/skopeo /usr/bin/skopeo
# Same default as upstream's image. Without it the credentials file defaults to
# /run/containers/UID/auth.json, which only root can create, so skopeo login fails for
# any other user (Kubernetes runAsUser, docker run --user).
ENV REGISTRY_AUTH_FILE=/tmp/auth.json
# ghcr.io shows the description from this label, not from the manifest annotation.
LABEL org.opencontainers.image.description="Community-built static skopeo (upstream: github.com/podman-container-tools/skopeo)"
ENTRYPOINT ["/usr/bin/skopeo"]

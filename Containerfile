# --- composefs build --- #
FROM debian:trixie-slim as composefs
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libfsverity-dev libssl-dev

COPY vendor/composefs /src/composefs

# --- ostree build --- #
FROM debian:trixie-slim as ostree
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libfsverity-dev libssl-dev

COPY vendor/ostree    /src/ostree

# --- bootupc build
FROM debian:trixie-slim as bootupc
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libfsverity-dev libssl-dev

COPY vendor/bootc     /src/bootc

# --- bootupd build
FROM debian:trixie-slim as bootupd
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libfsverity-dev libssl-dev

COPY vendor/bootupd   /src/bootupd

# --- oras fetch --- #
FROM ghcr.io/oras-project/oras:v1.3.4 as oras
ARG DEBIAN_FRONTEND=noninteractive
RUN oras pull ghcr.io/opengamingcollective/kernel-packages-ubuntu:7.2.4-ogc3.1 -o /tmp/ogc
# --- final image --- #

FROM debian:trixie-slim
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=oras /tmp/ogc /tmp/ogc
RUN apt-get update && apt-get install -y /tmp/ogc/*.deb && rm -rf /tmp/ogc

RUN mkdir -p /sysroot /var/home /var/roothome \
 && rm -rf /home /root /opt /srv /mnt \
 && ln -s /var/home /home \
 && ln -s /var/roothome /root \
 && ln -s /var/opt /opt \
 && ln -s /var/srv /srv \
 && ln -s /var/mnt /mnt

RUN mkdir -p /usr/lib/ostree \
  && printf "[sysroot]\nreadonly=true\n\n\[composefs]\nenabled=yes\n" > /usr/lib/ostree/prepare-root.conf

RUN set -eux; KVER="$(ls /usr/lib/modules)"; \
    [ -e "/boot/vmlinuz-$KVER" ] && mv "/boot/vmlinuz-$KVER" "/usr/lib/modules/$KVER/vmlinuz"; \
    dracut --force --no-hostonly --zstd --add "bootc ostree" \
      --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img"; \
    bootupctl backend generate-update-metadata; \
    rm -rf /boot/*

LABEL containers.bootc=1
LABEL ostree.bootable=1
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

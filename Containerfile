# --- bootupd build
FROM debian:testing-slim AS bootc
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates build-essential autoconf automake libtool pkg-config \
    libfsverity-dev libssl-dev curl libostree-dev ostree libssl-dev libzstd-dev \
    libclang-dev go-md2man cargo rustc

COPY vendors/bootupd /src/bootupd
COPY vendors/bootc /src/bootc
RUN cargo install cargo-deb && cd /src/bootupd && make && cargo deb -p bootupd --no-build --maintainer="Dominic Parry <why_context@pm.me>" \
 && cd /src/bootc && make && cargo deb -p bootc --no-build --maintainer="Dominic Parry <why_context@pm.me>"

# --- oras fetch --- #
FROM ghcr.io/oras-project/oras:v1.3.4 as oras
ARG DEBIAN_FRONTEND=noninteractive
RUN oras pull ghcr.io/opengamingcollective/kernel-packages-ubuntu:7.2.4-ogc3.1 -o /tmp/ogc
# --- final image --- #

FROM debian:testing-slim
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=oras /tmp/ogc /tmp/debs
COPY --from=bootc /src/bootupd/target/debian/*.deb /tmp/debs
COPY --from=bootc /src/bootc/target/debian/*.deb /tmp/debs
COPY --from=bootc /src/bootc/systemd/ /usr/lib/systemd/system/

RUN apt-get update && apt-get install -y --no-install-recommends \
    ostree skopeo composefs \
    /tmp/debs/*.deb systemd systemd-sysv udev \
    initramfs-tools \
    grub-efi-amd64-signed shim-signed \
 && rm -rf /tmp/debs

RUN mkdir -p /sysroot /var/home /var/roothome \
 && rm -rf /home /root /opt /srv /mnt \
 && ln -s /var/home /home \
 && ln -s /var/roothome /root \
 && ln -s /var/opt /opt \
 && ln -s /var/srv /srv \
 && ln -s /var/mnt /mnt

RUN mkdir -p /usr/lib/ostree \
  && printf "[sysroot]\nreadonly=true\n\n\[composefs]\nenabled=yes\n" > /usr/lib/ostree/prepare-root.conf

RUN printf 'MODULES=most\nCOMPRESS=zstd\n' > /etc/initramfs-tools/conf.d/bootc.conf

RUN set -eux; KVER="$(ls /usr/lib/modules)"; \
    [ -e "/boot/vmlinuz-$KVER" ] && mv "/boot/vmlinuz-$KVER" "/usr/lib/modules/$KVER/vmlinuz"; \
    mkinitramfs -o "/usr/lib/modules/$KVER/initramfs.img" "$KVER"; \
    bootupctl backend generate-update-metadata; \
    rm -rf /boot/*

RUN bootc container lint

LABEL containers.bootc=1
LABEL ostree.bootable=1
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

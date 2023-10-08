FROM alpine:3 AS build

ARG VERSION="2.89"
ARG CHECKSUM="8651373d000cae23776256e83dcaa6723dee72c06a39362700344e0c12c4e7e4"

ADD http://www.thekelleys.org.uk/dnsmasq/dnsmasq-$VERSION.tar.gz /tmp/dnsmasq.tar.gz

RUN [ "$(sha256sum /tmp/dnsmasq.tar.gz | awk '{print $1}')" = "$CHECKSUM" ] && \
    apk add gcc linux-headers make musl-dev libcap && \
    tar -C /tmp -xf /tmp/dnsmasq.tar.gz && \
    cd /tmp/dnsmasq-$VERSION && \
      make LDFLAGS="-static"

RUN mkdir -p /rootfs/bin && \
      cp /tmp/dnsmasq-$VERSION/src/dnsmasq /rootfs/bin/ && \
    mkdir -p /rootfs/etc && \
      echo "nogroup:*:10000:nobody" > /rootfs/etc/group && \
      echo "nobody:*:10000:10000:::" > /rootfs/etc/passwd
RUN setcap CAP_NET_ADMIN,CAP_NET_RAW,CAP_NET_BIND_SERVICE+ep /rootfs/bin/dnsmasq

COPY ./docker/dnsmasq/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

FROM busybox:latest

COPY --from=build --chown=10000:10000 /rootfs /
COPY --from=build --chown=10000:10000 /entrypoint.sh /entrypoint.sh
USER 10000:10000

# 初期化スクリプトを実行
ENTRYPOINT ["/entrypoint.sh"]

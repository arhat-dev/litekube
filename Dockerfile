ARG MATRIX_OS
ARG MATRIX_ARCH

FROM ghcr.io/arhat-dev/builder-python3.8:${MATRIX_OS}-${MATRIX_ARCH} as builder

COPY scripts /app
RUN sh /build.sh

FROM ghcr.io/arhat-dev/python3.8:${MATRIX_OS}-${MATRIX_ARCH}

ARG MATRIX_OS
ARG MATRIX_ARCH

COPY scripts/create-user.sh /create-user.sh
RUN sh /create-user.sh "${MATRIX_OS}" && rm -f /create-user.sh

RUN mkdir -p /data /etcd-certs && \
    chown -R litekube:litekube /data /etcd-certs

VOLUME [/etcd-certs, /data]

COPY --chmod=0555 scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY --from=builder /app /litekube
COPY --chmod=0555 build/kine.${MATRIX_OS}.${MATRIX_ARCH} /usr/local/bin/kine
COPY --chmod=0555 build/litestream.${MATRIX_OS}.${MATRIX_ARCH} /usr/local/bin/litestream

ENTRYPOINT [ "/usr/local/bin/entrypoint" ]

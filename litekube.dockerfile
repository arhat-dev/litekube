ARG MATRIX_OS
ARG MATRIX_ARCH

FROM ghcr.io/arhat-dev/builder-python3.8:${MATRIX_OS}-${MATRIX_ARCH} as builder

COPY scripts/Pipfile /app/Pipfile
RUN sh /build.sh

FROM ghcr.io/arhat-dev/python3.8:${MATRIX_OS}-${MATRIX_ARCH}

LABEL org.opencontainers.image.source https://github.com/arhat-dev/litekube

ARG MATRIX_OS
ARG MATRIX_ARCH

COPY scripts/prepare.sh /prepare.sh
RUN sh /prepare.sh "${MATRIX_OS}" && rm -f /prepare.sh

RUN mkdir -p /data /etcd-certs /var/lib/supervisord /run/keepalived && \
    chown -R litekube:litekube /data /etcd-certs /var/lib/supervisord /run/keepalived

USER litekube

VOLUME /etcd-certs
VOLUME /data

COPY --chmod=0555 scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY --from=builder /app /app
COPY --chmod=0555 build/kine.${MATRIX_OS}.${MATRIX_ARCH} /usr/local/bin/kine
COPY --chmod=0555 build/litestream.${MATRIX_OS}.${MATRIX_ARCH} /usr/local/bin/litestream

# kind etcd-client
EXPOSE 12379

ENTRYPOINT [ "/usr/local/bin/entrypoint" ]

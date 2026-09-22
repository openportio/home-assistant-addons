ARG BUILD_FROM
FROM $BUILD_FROM

ARG BUILD_ARCH
# The custom_domain option (end-to-end TLS) needs the client's
# --tls-passthrough support. Bump this to the first release that ships it
# before merging custom_domain to the published add-on, or that option will
# fail on an older binary.
ARG OPENPORT_VERSION=2.2.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Map the Home Assistant build arch to the openport release binary:
#   aarch64 -> arm64, amd64 -> amd64, armv7 -> armhf (ARMv7), armhf -> armv6
RUN case "${BUILD_ARCH}" in \
        aarch64) OPENPORT_BIN=openport-arm64 ;; \
        amd64)   OPENPORT_BIN=openport-amd64 ;; \
        armv7)   OPENPORT_BIN=openport-armhf ;; \
        armhf)   OPENPORT_BIN=openport-armv6 ;; \
        *) echo "Unsupported architecture: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /usr/local/bin/openport \
        "https://github.com/openportio/openport-go/releases/download/v${OPENPORT_VERSION}/${OPENPORT_BIN}" \
    && chmod +x /usr/local/bin/openport \
    && /usr/local/bin/openport version

COPY run.sh /
RUN chmod +x /run.sh

CMD [ "/run.sh" ]

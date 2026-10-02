ARG BUILD_FROM
FROM $BUILD_FROM

ARG BUILD_ARCH
# 2.3.0 is the first release with --tls-passthrough/--domain, which the
# custom_domain option needs. The "-1" is the deb revision.
ARG OPENPORT_VERSION=2.3.0

# Install the pinned client from the signed apt repository: since 2.3.0,
# releases ship as the signed apt tree (see openport-go-client
# packaging/sign-release.sh), not as bare GitHub release binaries, and apt
# verifies the signature against the keyring. The repo's armhf deb carries
# the ARMv6 binary on purpose, so both the armv7 and armhf images (dpkg
# arch armhf on either) get a binary that runs on every Pi.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://openport.io/apt/openport-archive-keyring.gpg \
        -o /usr/share/keyrings/openport-archive-keyring.gpg \
    && curl -fsSL https://openport.io/apt/openport.list \
        -o /etc/apt/sources.list.d/openport.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends "openport=${OPENPORT_VERSION}-1" \
    && rm -rf /var/lib/apt/lists/* \
    && openport version

COPY run.sh /
RUN chmod +x /run.sh

CMD [ "/run.sh" ]
